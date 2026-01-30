#!/usr/bin/env bash
set -euo pipefail

# Home Assistant add-on options are usually rendered to /data/options.json
OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "Missing $OPTIONS_FILE (add-on options)."
  exit 1
fi

# ------------------------------------------------------------------------------
# Read add-on options (only add-on-specific knobs; OpenClaw is configured via onboarding)
# ------------------------------------------------------------------------------

TZNAME=$(jq -r '.timezone // "Europe/Sofia"' "$OPTIONS_FILE")
GW_PUBLIC_URL=$(jq -r '.gateway_public_url // empty' "$OPTIONS_FILE")
HA_TOKEN=$(jq -r '.homeassistant_token // empty' "$OPTIONS_FILE")
ENABLE_TERMINAL=$(jq -r '.enable_terminal // true' "$OPTIONS_FILE")

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


# ------------------------------------------------------------------------------
# OpenClaw config is managed by OpenClaw itself (onboarding / configure).
# This add-on intentionally does NOT create/patch /config/.openclaw/openclaw.json.
# ------------------------------------------------------------------------------

# Convenience info for later (router SSH access path & HA token file)
cat > /config/CONNECTION_NOTES.txt <<EOF
Home Assistant token (if set): /config/secrets/homeassistant.token
Router SSH (generic):
  host=${ROUTER_HOST}
  user=${ROUTER_USER}
  key=${ROUTER_KEY}
EOF


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

# Bootstrap minimal OpenClaw config ONLY if missing.
# We do not overwrite or patch existing configs; onboarding owns everything else.
OPENCLAW_CONFIG_PATH="/config/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  echo "INFO: OpenClaw config missing; bootstrapping minimal config at $OPENCLAW_CONFIG_PATH"
  python3 - <<'PY'
import json
import secrets
from pathlib import Path

cfg_path = Path('/config/.openclaw/openclaw.json')
cfg_path.parent.mkdir(parents=True, exist_ok=True)

cfg = {
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": secrets.token_urlsafe(24)
    }
  }
}

cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding='utf-8')
print("INFO: Wrote minimal OpenClaw config (gateway.mode=local, auth.token generated)")
PY
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

# Render nginx config from template.
# The gateway token is NOT managed by the add-on; OpenClaw will generate/store it.
# Best-effort: query it via CLI (works even if openclaw.json is JSON5). If unknown, we hide the button.
GW_TOKEN="$(timeout 2s openclaw config get gateway.auth.token 2>/dev/null | tr -d '\n' || true)"
GW_PUBLIC_URL="$GW_PUBLIC_URL" GW_TOKEN="$GW_TOKEN" python3 - <<'PY'
import os
from pathlib import Path

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
landing_tpl = Path('/etc/nginx/landing.html.tpl').read_text()
public_url = os.environ.get('GW_PUBLIC_URL','')

# Token comes from environment (best-effort CLI query in run.sh)
token = os.environ.get('GW_TOKEN','')

gw_path = '' if public_url.endswith('/') else '/'

conf = tpl
Path('/etc/nginx/nginx.conf').write_text(conf)

landing = landing_tpl.replace('__GATEWAY_TOKEN__', token)
landing = landing.replace('__GATEWAY_PUBLIC_URL__', public_url)
landing = landing.replace('__GW_PUBLIC_URL_PATH__', gw_path)

Path('/etc/nginx/html').mkdir(parents=True, exist_ok=True)
Path('/etc/nginx/html/index.html').write_text(landing)
PY

echo "Starting ingress proxy (nginx) on :8099 ..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Wait for gateway; if it exits, shut down others.
wait "${GW_PID}"
