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

# Write Clawdbot gateway config (JSON5) into the expected location.
# Use pairing for DMs by default; no hardcoded chat allowlist needed.
cat > /data/.clawdbot/clawdbot.json <<EOF
{
  gateway: { mode: "local" },
  agents: {
    defaults: {
      workspace: "/data/clawd"
    },
    list: [
      { id: "main" }
    ]
  },
  channels: {
    telegram: {
      enabled: true,
      botToken: "${BOT_TOKEN}",
      dmPolicy: "pairing"
    }
  }
}
EOF

# Convenience info for later (MikroTik access path & HA token file)
cat > /data/CONNECTION_NOTES.txt <<EOF
Home Assistant token (if set): /data/secrets/homeassistant.token
MikroTik SSH:
  host=${MT_HOST}
  user=${MT_USER}
  key=${MT_KEY}
EOF

echo "Running clawdbot doctor (auto-fix) ..."
# Doctor is idempotent; it will apply any needed config migrations and exit 0.
clawdbot doctor --fix --yes || true

echo "Starting Clawdbot Gateway..."
exec clawdbot gateway run
