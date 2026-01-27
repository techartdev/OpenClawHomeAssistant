#!/usr/bin/env bash
set -euo pipefail

# Home Assistant add-on options are usually rendered to /data/options.json
OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "Missing $OPTIONS_FILE (add-on options)."
  exit 1
fi

BOT_TOKEN=$(jq -r '.telegram_bot_token // empty' "$OPTIONS_FILE")
TZNAME=$(jq -r '.timezone // "Europe/Sofia"' "$OPTIONS_FILE")
ALLOW_FROM_RAW=$(jq -r '.telegram_allow_from // empty' "$OPTIONS_FILE")
MODEL_PRIMARY=$(jq -r '.model_primary // "openai-codex/gpt-5.2"' "$OPTIONS_FILE")
HA_TOKEN=$(jq -r '.homeassistant_token // empty' "$OPTIONS_FILE")
MT_HOST=$(jq -r '.mikrotik_host // "192.168.88.1"' "$OPTIONS_FILE")
MT_USER=$(jq -r '.mikrotik_ssh_user // "papur"' "$OPTIONS_FILE")
MT_KEY=$(jq -r '.mikrotik_ssh_key_path // "/data/keys/mikrotik_papur_nopw"' "$OPTIONS_FILE")

if [ -z "$BOT_TOKEN" ]; then
  echo "You must set telegram_bot_token in the add-on configuration."
  exit 1
fi

export TZ="$TZNAME"
# Reduce risk of secrets ending up in logs
set +x

# Persist everything under /data
export HOME=/data
mkdir -p /data/.clawdbot /data/clawd /data/keys /data/secrets

# Store HA token (optional) in a local file for later use by the HA skill/tooling.
if [ -n "$HA_TOKEN" ]; then
  umask 077
  printf '%s' "$HA_TOKEN" > /data/secrets/homeassistant.token
fi

# Decide Telegram DM access policy.
# If telegram_allow_from is set (comma-separated user ids), we use allowlist mode.
DM_POLICY="pairing"
ALLOW_FROM_JSON=""
if [ -n "$ALLOW_FROM_RAW" ]; then
  DM_POLICY="allowlist"
  # convert "1,2, 3" -> ["1","2","3"] using jq (no python dependency)
  ALLOW_FROM_JSON=$(printf '%s' "$ALLOW_FROM_RAW" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0))')
fi

# Write Clawdbot gateway config (JSON5) into the expected location.
cat > /data/.clawdbot/clawdbot.json <<EOF
{
  gateway: { mode: "local" },
  agents: {
    defaults: {
      workspace: "/data/clawd",
      model: { primary: "${MODEL_PRIMARY}" },
      models: {
        "${MODEL_PRIMARY}": {}
      }
    },
    list: [
      { id: "main" }
    ]
  },
  channels: {
    telegram: {
      enabled: true,
      botToken: "${BOT_TOKEN}",
      dmPolicy: "${DM_POLICY}"${ALLOW_FROM_RAW:+,
      allowFrom: ${ALLOW_FROM_JSON}}
    }
  }
}
EOF

echo "Model primary=${MODEL_PRIMARY}"

echo "Telegram dmPolicy=${DM_POLICY}${ALLOW_FROM_RAW:+ (allowFrom=${ALLOW_FROM_RAW})}"
echo "Telegram allowFrom JSON: ${ALLOW_FROM_JSON:-<none>}"

# Connectivity sanity checks (do NOT print the token)
echo "Sanity check: DNS + Telegram API reachability"
if curl -fsS --max-time 10 https://api.telegram.org/ >/dev/null; then
  echo "OK: api.telegram.org reachable"
else
  echo "WARN: api.telegram.org not reachable from add-on container"
fi

# Validate token (print only bot username)
BOT_USER=$(curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | jq -r '.result.username // empty' || true)
if [ -n "$BOT_USER" ]; then
  echo "OK: Telegram token valid for @${BOT_USER}"
else
  echo "WARN: Telegram token validation failed (getMe)"
fi

# Convenience info for later (MikroTik access path & HA token file)
cat > /data/CONNECTION_NOTES.txt <<EOF
Home Assistant token (if set): /data/secrets/homeassistant.token
MikroTik SSH:
  host=${MT_HOST}
  user=${MT_USER}
  key=${MT_KEY}
EOF

echo "Running clawdbot doctor (auto-fix) ..."
# Doctor is idempotent; but in containers it can occasionally hang on environment checks.
# Put a hard timeout so the gateway still starts.
(timeout 60s clawdbot doctor --fix --yes) || true

echo "Starting Clawdbot Gateway..."
exec clawdbot gateway run
