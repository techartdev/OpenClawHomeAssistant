#!/usr/bin/env bash
set -euo pipefail

# Home Assistant add-on options are usually rendered to /data/options.json
OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "Missing $OPTIONS_FILE (add-on options)."
  exit 1
fi

# ------------------------------------------------------------------------------
# Read add-on options (ALL optional; onboarding can fill the rest)
# ------------------------------------------------------------------------------

BOT_TOKEN=$(jq -r '.telegram_bot_token // empty' "$OPTIONS_FILE")
TZNAME=$(jq -r '.timezone // "Europe/Sofia"' "$OPTIONS_FILE")
ALLOW_FROM_RAW=$(jq -r '.telegram_allow_from // empty' "$OPTIONS_FILE")
MODEL_PRIMARY=$(jq -r '.model_primary // empty' "$OPTIONS_FILE")
GW_BIND=$(jq -r '.gateway_bind // empty' "$OPTIONS_FILE")
GW_PORT=$(jq -r '.gateway_port // empty' "$OPTIONS_FILE")
GW_TOKEN=$(jq -r '.gateway_token // empty' "$OPTIONS_FILE")
GW_PUBLIC_URL=$(jq -r '.gateway_public_url // empty' "$OPTIONS_FILE")
HA_TOKEN=$(jq -r '.homeassistant_token // empty' "$OPTIONS_FILE")
BRAVE_KEY=$(jq -r '.brave_api_key // empty' "$OPTIONS_FILE")
ENABLE_TERMINAL=$(jq -r '.enable_terminal // false' "$OPTIONS_FILE")

# Generic router SSH settings
ROUTER_HOST=$(jq -r '.router_ssh_host // empty' "$OPTIONS_FILE")
ROUTER_USER=$(jq -r '.router_ssh_user // empty' "$OPTIONS_FILE")
ROUTER_KEY=$(jq -r '.router_ssh_key_path // "/data/keys/router_ssh"' "$OPTIONS_FILE")

# Optional: allow disabling lock cleanup if you ever need to debug
CLEAN_LOCKS_ON_START=$(jq -r '.clean_session_locks_on_start // true' "$OPTIONS_FILE")
CLEAN_LOCKS_ON_EXIT=$(jq -r '.clean_session_locks_on_exit // true' "$OPTIONS_FILE")

export TZ="$TZNAME"

# Reduce risk of secrets ending up in logs
set +x

# HA add-ons mount persistent storage at /config (maps to /addon_configs/<slug> on the host).
export HOME=/config
mkdir -p /config/.openclaw /config/clawd /config/keys /config/secrets

# Back-compat: some docs/scripts assume /data; point it at /config.
if [ ! -e /data ]; then
  ln -s /config /data || true
fi

# Ensure these exist so cleanup doesn't fail
mkdir -p /config/.openclaw/agents/main/sessions || true

# ------------------------------------------------------------------------------
# SINGLE-INSTANCE GUARD (prevents multiple gateway runs racing each other)
# ------------------------------------------------------------------------------
STARTUP_LOCK="/config/.openclaw/gateway.start.lock"
exec 9>"$STARTUP_LOCK"
if ! flock -n 9; then
  echo "ERROR: Another instance appears to be running (could not acquire $STARTUP_LOCK)."
  echo "If this is wrong, check for stuck processes or remove the lock file."
  exit 1
fi

# ------------------------------------------------------------------------------
# Session lock cleanup helpers
# ------------------------------------------------------------------------------

gateway_running() {
  pgrep -f "openclaw.*gateway.*run" >/dev/null 2>&1
}

cleanup_session_locks() {
  local sessions_dir="/config/.openclaw/agents/main/sessions"
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

if [ "$CLEAN_LOCKS_ON_START" = "true" ]; then
  cleanup_session_locks
else
  echo "INFO: clean_session_locks_on_start=false; skipping session lock cleanup."
fi

# ------------------------------------------------------------------------------
# Store tokens / export env vars (optional)
# ------------------------------------------------------------------------------

if [ -n "$HA_TOKEN" ]; then
  umask 077
  printf '%s' "$HA_TOKEN" > /config/secrets/homeassistant.token
fi

if [ -n "$BRAVE_KEY" ]; then
  export BRAVE_API_KEY="$BRAVE_KEY"
  umask 077
  printf '%s' "$BRAVE_KEY" > /config/secrets/brave_api_key
fi

# ------------------------------------------------------------------------------
# Non-invasive OpenClaw config management
# - If config is missing: create it.
# - If config exists: ONLY patch the fields whose add-on options are set.
# - If config is not parseable as strict JSON (e.g. JSON5): do NOT touch it.
#   (This keeps onboarding-managed config intact.)
# ------------------------------------------------------------------------------

OPENCLAW_CONFIG_PATH="/config/.openclaw/openclaw.json"
export OPENCLAW_CONFIG_PATH

python3 - <<'PY'
import json
import os
from pathlib import Path

cfg_path = Path(os.environ.get('OPENCLAW_CONFIG_PATH', '/config/.openclaw/openclaw.json'))

def set_path(d, keys, value):
    cur = d
    for k in keys[:-1]:
        if k not in cur or not isinstance(cur[k], dict):
            cur[k] = {}
        cur = cur[k]
    cur[keys[-1]] = value

# Load existing config if possible
cfg = {}
if cfg_path.exists():
    try:
        cfg = json.loads(cfg_path.read_text(encoding='utf-8'))
    except Exception as e:
        print(f"INFO: {cfg_path} exists but is not strict JSON; leaving it untouched ({e}).")
        raise SystemExit(0)

# Patch only if env var is set (non-empty)

def env(name):
    v = os.environ.get(name, '')
    return v if v != '' else None

# gateway bind/port/token
bind_ = env('GW_BIND')
if bind_:
    set_path(cfg, ['gateway', 'bind'], bind_)

port_ = env('GW_PORT')
if port_:
    try:
        set_path(cfg, ['gateway', 'port'], int(port_))
    except Exception:
        pass

token_ = env('GW_TOKEN')
if token_:
    set_path(cfg, ['gateway', 'auth', 'mode'], 'token')
    set_path(cfg, ['gateway', 'auth', 'token'], token_)

# Agent defaults: workspace + primary model
# We always ensure workspace points to the add-on workspace (safe and expected).
set_path(cfg, ['agents', 'defaults', 'workspace'], '/config/clawd')

model_primary = env('MODEL_PRIMARY')
if model_primary:
    set_path(cfg, ['agents', 'defaults', 'model', 'primary'], model_primary)
    # Ensure models entry exists (minimal)
    models = cfg.get('agents', {}).get('defaults', {}).get('models', {})
    if not isinstance(models, dict):
        models = {}
    models.setdefault(model_primary, {})
    set_path(cfg, ['agents', 'defaults', 'models'], models)

# Telegram channel only if token provided in options
bot_token = env('BOT_TOKEN')
if bot_token:
    set_path(cfg, ['channels', 'telegram', 'enabled'], True)
    set_path(cfg, ['channels', 'telegram', 'botToken'], bot_token)

    allow_from_raw = env('ALLOW_FROM_RAW')
    if allow_from_raw:
        ids = [x.strip() for x in allow_from_raw.split(',') if x.strip()]
        if ids:
            set_path(cfg, ['channels', 'telegram', 'dmPolicy'], 'allowlist')
            set_path(cfg, ['channels', 'telegram', 'allowFrom'], ids)
    else:
        # If not set, do NOT override dmPolicy/allowFrom; let onboarding decide.
        pass

# Write (pretty JSON; JSON is valid JSON5 too)
cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(json.dumps(cfg, indent=2, sort_keys=True) + "\n", encoding='utf-8')
print(f"INFO: OpenClaw config written/patched at {cfg_path}")
PY

# Convenience info for later (router SSH access path & HA token file)
cat > /config/CONNECTION_NOTES.txt <<EOF
Home Assistant token (if set): /config/secrets/homeassistant.token
Router SSH (generic):
  host=${ROUTER_HOST}
  user=${ROUTER_USER}
  key=${ROUTER_KEY}
EOF

RUN_DOCTOR=$(jq -r '.run_doctor_on_start // false' "$OPTIONS_FILE")

# Run doctor ONLY if explicitly enabled; otherwise don't touch user-managed config/state.
if [ "$RUN_DOCTOR" = "true" ]; then
  echo "Running assistant doctor (auto-fix) ..."
  (timeout 60s openclaw doctor --fix --yes) || true
else
  echo "Skipping doctor on startup (run_doctor_on_start=false)"
fi

# ------------------------------------------------------------------------------
# Graceful shutdown handling (PID 1 trap) to reduce stale locks
# ------------------------------------------------------------------------------
GW_PID=""
NGINX_PID=""
TTYD_PID=""

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

if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is not installed."
  exit 1
fi

echo "Starting OpenClaw Assistant gateway (openclaw)..."
openclaw gateway run &
GW_PID=$!

# Start web terminal (optional)
if [ "$ENABLE_TERMINAL" = "true" ]; then
  echo "Starting web terminal (ttyd) on 127.0.0.1:7681 ..."
  ttyd -i 127.0.0.1 -p 7681 -b /terminal bash &
  TTYD_PID=$!
else
  echo "Terminal disabled (enable_terminal=false)"
fi

# Start ingress reverse proxy (nginx). This provides the add-on UI inside HA.
# Token is injected server-side; never put it in the browser URL.

# Render nginx config from template with the gateway token.
# NOTE: This intentionally exposes the token in the browser URL via a redirect.
# This matches OpenClaw Control UI's current expectations.
GW_TOKEN="$GW_TOKEN" GW_PUBLIC_URL="$GW_PUBLIC_URL" python3 - <<'PY'
import os
from pathlib import Path

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
token = os.environ.get('GW_TOKEN','')
public_url = os.environ.get('GW_PUBLIC_URL','')

conf = tpl.replace('__GATEWAY_TOKEN__', token)
conf = conf.replace('__GATEWAY_PUBLIC_URL__', public_url)
conf = conf.replace('__GW_PUBLIC_URL_PATH__', '' if public_url.endswith('/') else '/')

Path('/etc/nginx/nginx.conf').write_text(conf)
PY

echo "Starting ingress proxy (nginx) on :8099 ..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Wait for gateway; if it exits, shut down others.
wait "${GW_PID}"
