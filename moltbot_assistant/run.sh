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
GW_BIND=$(jq -r '.gateway_bind // "loopback"' "$OPTIONS_FILE")
GW_PORT=$(jq -r '.gateway_port // 18789' "$OPTIONS_FILE")
GW_TOKEN=$(jq -r '.gateway_token // empty' "$OPTIONS_FILE")
HA_TOKEN=$(jq -r '.homeassistant_token // empty' "$OPTIONS_FILE")
BRAVE_KEY=$(jq -r '.brave_api_key // empty' "$OPTIONS_FILE")
ENABLE_TERMINAL=$(jq -r '.enable_terminal // false' "$OPTIONS_FILE")
MT_HOST=$(jq -r '.mikrotik_host // empty' "$OPTIONS_FILE")
MT_USER=$(jq -r '.mikrotik_ssh_user // empty' "$OPTIONS_FILE")
MT_KEY=$(jq -r '.mikrotik_ssh_key_path // "/data/keys/mikrotik"' "$OPTIONS_FILE")

# Optional: allow disabling lock cleanup if you ever need to debug
CLEAN_LOCKS_ON_START=$(jq -r '.clean_session_locks_on_start // true' "$OPTIONS_FILE")
CLEAN_LOCKS_ON_EXIT=$(jq -r '.clean_session_locks_on_exit // true' "$OPTIONS_FILE")

if [ -z "$BOT_TOKEN" ]; then
  echo "You must set telegram_bot_token in the add-on configuration."
  exit 1
fi

export TZ="$TZNAME"
# Reduce risk of secrets ending up in logs
set +x

# HA add-ons mount persistent storage at /config (maps to /addon_configs/<slug> on the host).
# Use /config as HOME so Clawdbot finds its auth store and config there.
export HOME=/config
mkdir -p /config/.clawdbot /config/clawd /config/keys /config/secrets

# Back-compat: some docs/scripts assume /data; point it at /config.
if [ ! -e /data ]; then
  ln -s /config /data || true
fi

# Ensure these exist so cleanup doesn't fail
mkdir -p /config/.clawdbot/agents/main/sessions || true

# ------------------------------------------------------------------------------
# SINGLE-INSTANCE GUARD (prevents multiple gateway runs racing each other)
# ------------------------------------------------------------------------------
STARTUP_LOCK="/config/.clawdbot/gateway.start.lock"
exec 9>"$STARTUP_LOCK"
if ! flock -n 9; then
  echo "ERROR: Another instance appears to be running (could not acquire $STARTUP_LOCK)."
  echo "If this is wrong, check for stuck processes or remove the lock file."
  exit 1
fi

# ------------------------------------------------------------------------------
# Session lock cleanup helpers
# ------------------------------------------------------------------------------

# Returns 0 if a clawdbot gateway process appears to be running, else 1
gateway_running() {
  pgrep -f "clawdbot.*gateway.*run" >/dev/null 2>&1
}

cleanup_session_locks() {
  local sessions_dir="/config/.clawdbot/agents/main/sessions"
  local glob1="${sessions_dir}"/*.jsonl.lock

  shopt -s nullglob
  local locks=( $glob1 )
  shopt -u nullglob

  if [ ${#locks[@]} -eq 0 ]; then
    return 0
  fi

  # If gateway is running, do NOT remove locks automatically (could be real).
  if gateway_running; then
    echo "INFO: Gateway appears to be running; leaving session lock files untouched."
    echo "INFO: Locks present: ${#locks[@]}"
    return 0
  fi

  echo "INFO: Removing stale session lock files (${#locks[@]}) from ${sessions_dir}"
  rm -f "${sessions_dir}"/*.jsonl.lock || true
}

# Cleanup on start (stale locks after crashes/restarts)
if [ "$CLEAN_LOCKS_ON_START" = "true" ]; then
  cleanup_session_locks
else
  echo "INFO: clean_session_locks_on_start=false; skipping session lock cleanup."
fi

# ------------------------------------------------------------------------------
# Store tokens / export env vars (optional)
# ------------------------------------------------------------------------------

# Home Assistant long-lived token (for local HA API scripts/tools)
if [ -n "$HA_TOKEN" ]; then
  umask 077
  printf '%s' "$HA_TOKEN" > /config/secrets/homeassistant.token
fi

# Brave Search API key (for clawdbot's web_search tool, which reads BRAVE_API_KEY)
if [ -n "$BRAVE_KEY" ]; then
  export BRAVE_API_KEY="$BRAVE_KEY"
  umask 077
  printf '%s' "$BRAVE_KEY" > /config/secrets/brave_api_key
fi

# Decide Telegram DM access policy.
DM_POLICY="pairing"
ALLOW_FROM_JSON=""
if [ -n "$ALLOW_FROM_RAW" ]; then
  DM_POLICY="allowlist"
  # convert "1,2, 3" -> ["1","2","3"] using jq (no python dependency)
  ALLOW_FROM_JSON=$(printf '%s' "$ALLOW_FROM_RAW" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0))')
fi

# Validate gateway exposure settings
if [ "$GW_BIND" = "lan" ] && [ -z "$GW_TOKEN" ]; then
  echo "ERROR: gateway_bind=lan requires gateway_token to be set (do not expose an unauthenticated gateway)."
  exit 1
fi

GW_AUTH_BLOCK="auth: { mode: \"token\", token: \"${GW_TOKEN}\" }"
if [ -z "$GW_TOKEN" ]; then
  # Let doctor generate one (loopback-only is still protected by local access)
  GW_AUTH_BLOCK="auth: { mode: \"token\" }"
fi

# Write Clawdbot gateway config (JSON5) into the expected location.
cat > /config/.clawdbot/clawdbot.json <<EOF
{
  gateway: {
    mode: "local",
    bind: "${GW_BIND}",
    port: ${GW_PORT},
    controlUi: { allowInsecureAuth: true },
    ${GW_AUTH_BLOCK}
  },
  agents: {
    defaults: {
      workspace: "/config/clawd",
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
echo "Gateway bind=${GW_BIND} port=${GW_PORT} token=${GW_TOKEN:+(set)}${GW_TOKEN:-(auto)}"
echo "Telegram dmPolicy=${DM_POLICY}${ALLOW_FROM_RAW:+ (allowFrom=${ALLOW_FROM_RAW})}"
echo "Telegram allowFrom JSON: ${ALLOW_FROM_JSON:-<none>}"

# Auth store debug (redacted): never print tokens
AUTH_STORE="/config/.clawdbot/agents/main/agent/auth-profiles.json"
if [ -f "$AUTH_STORE" ]; then
  echo "Auth store present at $AUTH_STORE"
  echo "Auth store summary (redacted):"
  jq -r '"version="+((.version//"?")|tostring),
         "profiles="+(((.profiles//{})|keys|join(","))),
         "providers="+(((.profiles//{})|to_entries|map(.value.provider // "?")|unique|join(",")))' "$AUTH_STORE" 2>/dev/null || echo "(could not parse auth store JSON)"
else
  echo "Auth store not found at $AUTH_STORE"
fi

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
cat > /config/CONNECTION_NOTES.txt <<EOF
Home Assistant token (if set): /config/secrets/homeassistant.token
MikroTik SSH:
  host=${MT_HOST}
  user=${MT_USER}
  key=${MT_KEY}
EOF

RUN_DOCTOR=$(jq -r '.run_doctor_on_start // false' "$OPTIONS_FILE")

if [ "$RUN_DOCTOR" = "true" ]; then
  echo "Running clawdbot doctor (auto-fix) ..."
  (timeout 60s clawdbot doctor --fix --yes) || true
else
  echo "Skipping clawdbot doctor on startup (run_doctor_on_start=false)"
fi

# ------------------------------------------------------------------------------
# Graceful shutdown handling (PID 1 trap) to reduce stale locks
# ------------------------------------------------------------------------------
GW_PID=""

shutdown() {
  echo "Shutdown requested; stopping services..."

  if [ -n "${NGINX_PID}" ] && kill -0 "${NGINX_PID}" >/dev/null 2>&1; then
    kill -TERM "${NGINX_PID}" >/dev/null 2>&1 || true
    wait "${NGINX_PID}" || true
  fi

  if [ -n "${TTYD_PID}" ] && kill -0 "${TTYD_PID}" >/dev/null 2>&1; then
    kill -TERM "${TTYD_PID}" >/dev/null 2>&1 || true
    wait "${TTYD_PID}" || true
  fi

  if [ -n "${GW_PID}" ] && kill -0 "${GW_PID}" >/dev/null 2>&1; then
    kill -TERM "${GW_PID}" >/dev/null 2>&1 || true
    wait "${GW_PID}" || true
  fi

  if [ "$CLEAN_LOCKS_ON_EXIT" = "true" ]; then
    cleanup_session_locks || true
  fi
}

trap shutdown INT TERM

NGINX_PID=""
TTYD_PID=""

echo "Starting Clawdbot Gateway..."
clawdbot gateway run &
GW_PID=$!

# Start web terminal (optional)
if [ "$ENABLE_TERMINAL" = "true" ]; then
  echo "Starting web terminal (ttyd) on 127.0.0.1:7681 ..."
  # -W: allow clients to write (interactive)
  # -p: port
  # bind localhost only; exposed to HA via ingress reverse proxy
  ttyd -W -i 127.0.0.1 -p 7681 bash &
  TTYD_PID=$!
else
  echo "Terminal disabled (enable_terminal=false)"
fi

# Start ingress reverse proxy (nginx). This provides the add-on UI inside HA.
# Token is injected server-side; never put it in the browser URL.

# Render nginx config from template with the gateway token.
python3 - <<'PY'
import os
from pathlib import Path

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
token = os.environ.get('GW_TOKEN','')
if not token:
    # Keep nginx running, but gateway UI will remain inaccessible.
    # This avoids breaking the add-on UI completely if token is unset.
    print('WARN: gateway_token is empty; ingress proxy will not be able to authenticate to gateway UI.')

conf = tpl.replace('__GATEWAY_TOKEN__', token)
Path('/etc/nginx/nginx.conf').write_text(conf)
PY

echo "Starting ingress proxy (nginx) on :8099 ..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Wait for gateway; if it exits, shut down others.
wait "${GW_PID}"
