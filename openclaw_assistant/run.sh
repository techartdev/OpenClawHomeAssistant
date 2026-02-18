#!/usr/bin/env bash
set -euo pipefail

# Ensure Homebrew and brew-installed binaries are in PATH
# This is needed for OpenClaw skills that depend on CLI tools (gemini, aider, etc.)
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

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
TERMINAL_PORT_RAW=$(jq -r '.terminal_port // 7681' "$OPTIONS_FILE")

# SECURITY: Validate TERMINAL_PORT to prevent nginx config injection
# Only allow numeric values in valid port range (1024-65535)
if [[ "$TERMINAL_PORT_RAW" =~ ^[0-9]+$ ]] && [ "$TERMINAL_PORT_RAW" -ge 1024 ] && [ "$TERMINAL_PORT_RAW" -le 65535 ]; then
  TERMINAL_PORT="$TERMINAL_PORT_RAW"
else
  echo "ERROR: Invalid terminal_port '$TERMINAL_PORT_RAW'. Must be numeric 1024-65535. Using default 7681."
  TERMINAL_PORT="7681"
fi

echo "DEBUG: enable_terminal config value: '$ENABLE_TERMINAL'"
echo "DEBUG: terminal_port config value: '$TERMINAL_PORT' (validated)"

# Generic router SSH settings
ROUTER_HOST=$(jq -r '.router_ssh_host // empty' "$OPTIONS_FILE")
ROUTER_USER=$(jq -r '.router_ssh_user // empty' "$OPTIONS_FILE")
ROUTER_KEY=$(jq -r '.router_ssh_key_path // "/data/keys/router_ssh"' "$OPTIONS_FILE")

# Optional: allow disabling lock cleanup if you ever need to debug
CLEAN_LOCKS_ON_START=$(jq -r '.clean_session_locks_on_start // true' "$OPTIONS_FILE")
CLEAN_LOCKS_ON_EXIT=$(jq -r '.clean_session_locks_on_exit // true' "$OPTIONS_FILE")

# Gateway configuration
GATEWAY_MODE=$(jq -r '.gateway_mode // "local"' "$OPTIONS_FILE")
GATEWAY_BIND_MODE=$(jq -r '.gateway_bind_mode // "loopback"' "$OPTIONS_FILE")
GATEWAY_PORT=$(jq -r '.gateway_port // 18789' "$OPTIONS_FILE")
ENABLE_OPENAI_API=$(jq -r '.enable_openai_api // false' "$OPTIONS_FILE")
ALLOW_INSECURE_AUTH=$(jq -r '.allow_insecure_auth // false' "$OPTIONS_FILE")
FORCE_IPV4_DNS=$(jq -r '.force_ipv4_dns // false' "$OPTIONS_FILE")

export TZ="$TZNAME"

# Reduce risk of secrets ending up in logs
set +x

# Optional network hardening/workaround: force IPv4-first DNS ordering for Node.js.
# Helps in environments where IPv6 resolves but has no working egress.
if [ "$FORCE_IPV4_DNS" = "true" ] || [ "$FORCE_IPV4_DNS" = "1" ]; then
  if [ -n "${NODE_OPTIONS:-}" ]; then
    export NODE_OPTIONS="${NODE_OPTIONS} --dns-result-order=ipv4first"
  else
    export NODE_OPTIONS="--dns-result-order=ipv4first"
  fi
  echo "INFO: Enabled IPv4-first DNS ordering (NODE_OPTIONS=--dns-result-order=ipv4first)"
fi

# HA add-ons mount persistent storage at /config (maps to /addon_configs/<slug> on the host).
export HOME=/config

# Explicitly set OpenClaw directories to ensure they persist across add-on updates
# This prevents loss of installed skills, configuration, and workspace state
export OPENCLAW_CONFIG_DIR=/config/.openclaw
export OPENCLAW_WORKSPACE_DIR=/config/clawd
export XDG_CONFIG_HOME=/config

mkdir -p /config/.openclaw /config/clawd /config/keys /config/secrets

# ------------------------------------------------------------------------------
# Sync built-in OpenClaw skills from image to persistent storage
# On each startup, copy new/updated built-in skills so they survive rebuilds.
# We sync them to /config/.openclaw/skills and symlink back.
# NOTE: We cannot use `npm root -g` here because HOME=/config may contain a
# persisted .npmrc with a custom prefix from a previous run. Instead, we
# resolve the real image path by temporarily overriding HOME.
# ------------------------------------------------------------------------------
IMAGE_SKILLS_DIR="$(HOME=/root npm root -g 2>/dev/null)/openclaw/skills"
PERSISTENT_SKILLS_DIR="/config/.openclaw/skills"

if [ -d "$IMAGE_SKILLS_DIR" ] && [ ! -L "$IMAGE_SKILLS_DIR" ]; then
  mkdir -p "$PERSISTENT_SKILLS_DIR"
  # Sync skills: --update replaces older files so upgrades propagate,
  # but doesn't delete user-added files in persistent storage.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --update "$IMAGE_SKILLS_DIR/" "$PERSISTENT_SKILLS_DIR/" 2>/dev/null || true
  else
    cp -ru "$IMAGE_SKILLS_DIR/"* "$PERSISTENT_SKILLS_DIR/" 2>/dev/null || true
  fi
  # Replace image skills dir with symlink to persistent copy
  rm -rf "$IMAGE_SKILLS_DIR"
  ln -sf "$PERSISTENT_SKILLS_DIR" "$IMAGE_SKILLS_DIR"
  echo "INFO: Synced built-in skills to persistent storage at $PERSISTENT_SKILLS_DIR"
elif [ -L "$IMAGE_SKILLS_DIR" ]; then
  echo "INFO: Built-in skills already linked to persistent storage"
else
  echo "WARN: Built-in skills directory not found at $IMAGE_SKILLS_DIR"
fi

# ------------------------------------------------------------------------------
# Persist user-installed node skills across Docker image rebuilds
# Redirect npm/pnpm global installs to /config/.node_global (persistent storage)
# so that skills installed via the dashboard survive container rebuilds.
# NOTE: This MUST come after the skills sync above (which needs the original npm root -g).
# ------------------------------------------------------------------------------
PERSISTENT_NODE_GLOBAL="/config/.node_global"
mkdir -p "$PERSISTENT_NODE_GLOBAL"
npm config set prefix "$PERSISTENT_NODE_GLOBAL" 2>/dev/null || true
export PATH="${PERSISTENT_NODE_GLOBAL}/bin:${PATH}"
export NODE_PATH="${PERSISTENT_NODE_GLOBAL}/lib/node_modules:${NODE_PATH:-}"

# Also configure pnpm global dir to persistent storage
export PNPM_HOME="${PERSISTENT_NODE_GLOBAL}/pnpm"
mkdir -p "$PNPM_HOME"
export PATH="${PNPM_HOME}:${PATH}"

# ------------------------------------------------------------------------------
# Persist Linuxbrew/Homebrew across Docker image rebuilds
# Homebrew installs to /home/linuxbrew/.linuxbrew/ which is ephemeral.
# We sync it to /config/.linuxbrew and symlink back so brew-installed CLI
# tools (gog, gh, bw, etc.) survive add-on updates.
# ------------------------------------------------------------------------------
IMAGE_BREW_DIR="/home/linuxbrew/.linuxbrew"
PERSISTENT_BREW_DIR="/config/.linuxbrew"

if [ -d "$IMAGE_BREW_DIR" ] && [ ! -L "$IMAGE_BREW_DIR" ]; then
  # Image has a real Homebrew install — sync to persistent storage
  if [ -d "$PERSISTENT_BREW_DIR" ]; then
    # Persistent copy exists: sync new/updated files from image (upgrades),
    # but preserve user-installed packages already in persistent storage.
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --update "$IMAGE_BREW_DIR/" "$PERSISTENT_BREW_DIR/" 2>/dev/null || true
    else
      cp -ru "$IMAGE_BREW_DIR/"* "$PERSISTENT_BREW_DIR/" 2>/dev/null || true
    fi
    echo "INFO: Synced Homebrew updates to persistent storage"
  else
    # First time: copy entire Homebrew install to persistent storage
    cp -a "$IMAGE_BREW_DIR" "$PERSISTENT_BREW_DIR" 2>/dev/null || true
    echo "INFO: Copied Homebrew to persistent storage at $PERSISTENT_BREW_DIR"
  fi
  # Replace image dir with symlink to persistent copy
  rm -rf "$IMAGE_BREW_DIR"
  ln -sf "$PERSISTENT_BREW_DIR" "$IMAGE_BREW_DIR"
elif [ -L "$IMAGE_BREW_DIR" ]; then
  echo "INFO: Homebrew already linked to persistent storage"
elif [ -d "$PERSISTENT_BREW_DIR" ]; then
  # Image doesn't have Homebrew (failed install?) but persistent copy exists
  mkdir -p "$(dirname "$IMAGE_BREW_DIR")"
  ln -sf "$PERSISTENT_BREW_DIR" "$IMAGE_BREW_DIR"
  echo "INFO: Restored Homebrew symlink from persistent storage"
else
  echo "INFO: Homebrew not available (install may have failed during image build)"
fi

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
    "port": 18789,
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": secrets.token_urlsafe(24)
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/config/clawd"
    }
  }
}

cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding='utf-8')
print("INFO: Wrote minimal OpenClaw config (gateway.mode=local, auth.token generated)")
PY
fi

# ------------------------------------------------------------------------------
# Apply gateway LAN mode settings safely using helper script
# This updates gateway.bind and gateway.port without touching other settings
# ------------------------------------------------------------------------------
export OPENCLAW_CONFIG_PATH="/config/.openclaw/openclaw.json"

# Find the helper script (copied to root in Dockerfile, or fallback to add-on dir)
HELPER_PATH="/oc_config_helper.py"
if [ ! -f "$HELPER_PATH" ] && [ -f "$(dirname "$0")/oc_config_helper.py" ]; then
  HELPER_PATH="$(dirname "$0")/oc_config_helper.py"
fi

if [ -f "$OPENCLAW_CONFIG_PATH" ]; then
  if [ -f "$HELPER_PATH" ]; then
    if ! python3 "$HELPER_PATH" apply-gateway-settings "$GATEWAY_MODE" "$GATEWAY_BIND_MODE" "$GATEWAY_PORT" "$ENABLE_OPENAI_API" "$ALLOW_INSECURE_AUTH"; then
      rc=$?
      echo "ERROR: Failed to apply gateway settings via oc_config_helper.py (exit code ${rc})."
      echo "ERROR: Gateway configuration may be incorrect; aborting startup."
      exit "${rc}"
    fi
  else
    echo "WARN: oc_config_helper.py not found, cannot apply gateway settings"
    echo "INFO: Ensure the add-on image includes oc_config_helper.py and restart"
  fi
else
  echo "WARN: OpenClaw config not found at $OPENCLAW_CONFIG_PATH, cannot apply gateway settings"
  echo "INFO: Run 'openclaw onboard' first, then restart the add-on"
fi

echo "Starting OpenClaw Assistant gateway (openclaw)..."
openclaw gateway run &
GW_PID=$!

# Start web terminal (optional)
TTYD_PID_FILE="/var/run/openclaw-ttyd.pid"

# Clean up stale ttyd process from previous run using PID file
if [ -f "$TTYD_PID_FILE" ]; then
  OLD_PID=$(cat "$TTYD_PID_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping previous ttyd process (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
    # Force kill if still running
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$TTYD_PID_FILE"
fi

if [ "$ENABLE_TERMINAL" = "true" ] || [ "$ENABLE_TERMINAL" = "1" ]; then
  # Check if the terminal port is already in use before starting ttyd
  if command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ":${TERMINAL_PORT} "; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!  WARNING: terminal_port ${TERMINAL_PORT} IS ALREADY IN USE  !!"
    echo "!!                                                             !!"
    echo "!!  The web terminal (ttyd) may FAIL to start because port     !!"
    echo "!!  ${TERMINAL_PORT} appears to be in use by another process.  !!"
    echo "!!                                                             !!"
    echo "!!  ACTION REQUIRED: If the terminal does not work, go to      !!"
    echo "!!  Add-on Configuration and change 'terminal_port' to a free  !!"
    echo "!!  port, then restart the add-on.                             !!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
  fi
  echo "Starting web terminal (ttyd) on 127.0.0.1:${TERMINAL_PORT} ..."
  ttyd -W -i 127.0.0.1 -p "${TERMINAL_PORT}" -b /terminal bash &
  TTYD_PID=$!
  echo "$TTYD_PID" > "$TTYD_PID_FILE"
  echo "ttyd started with PID $TTYD_PID"
else
  echo "Terminal disabled (enable_terminal=$ENABLE_TERMINAL)"
fi

# Start ingress reverse proxy (nginx). This provides the add-on UI inside HA.
# Token is injected server-side; never put it in the browser URL.
NGINX_PID_FILE="/var/run/openclaw-nginx.pid"

# Clean up stale nginx process from previous run (e.g., after crash/unclean restart)
if [ -f "$NGINX_PID_FILE" ]; then
  OLD_NGINX_PID=$(cat "$NGINX_PID_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_NGINX_PID" ] && kill -0 "$OLD_NGINX_PID" 2>/dev/null; then
    echo "Stopping previous nginx process (PID $OLD_NGINX_PID)..."
    kill "$OLD_NGINX_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD_NGINX_PID" 2>/dev/null || true
  fi
  rm -f "$NGINX_PID_FILE"
fi
# Also kill any orphaned nginx workers that might hold port 48099
if command -v pkill >/dev/null 2>&1; then
  pkill -f "nginx.*-c /etc/nginx/nginx.conf" 2>/dev/null || true
  sleep 1
fi
# Verify port 48099 is actually free before proceeding
if command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ':48099 '; then
  echo "WARN: Port 48099 still in use after cleanup; nginx may fail to start"
fi

# Render nginx config from template.
# The gateway token is NOT managed by the add-on; OpenClaw will generate/store it.
# Best-effort: query it via CLI (works even if openclaw.json is JSON5). If unknown, we hide the button.
GW_TOKEN="$(timeout 2s openclaw config get gateway.auth.token 2>/dev/null | tr -d '\n' || true)"
GW_PUBLIC_URL="$GW_PUBLIC_URL" GW_TOKEN="$GW_TOKEN" TERMINAL_PORT="$TERMINAL_PORT" python3 - <<'PY'
import os
from pathlib import Path

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
landing_tpl = Path('/etc/nginx/landing.html.tpl').read_text()
public_url = os.environ.get('GW_PUBLIC_URL','')
terminal_port = os.environ.get('TERMINAL_PORT', '7681')

# Token comes from environment (best-effort CLI query in run.sh)
token = os.environ.get('GW_TOKEN','')

gw_path = '' if public_url.endswith('/') else '/'

# Replace terminal port placeholder in nginx config
conf = tpl.replace('__TERMINAL_PORT__', terminal_port)
Path('/etc/nginx/nginx.conf').write_text(conf)

landing = landing_tpl.replace('__GATEWAY_TOKEN__', token)
landing = landing.replace('__GATEWAY_PUBLIC_URL__', public_url)
landing = landing.replace('__GW_PUBLIC_URL_PATH__', gw_path)

out_dir = Path('/etc/nginx/html')
out_dir.mkdir(parents=True, exist_ok=True)
out_file = out_dir / 'index.html'
out_file.write_text(landing)

# Ensure nginx can read it even if base image uses restrictive umask/permissions.
try:
    out_dir.chmod(0o755)
    out_file.chmod(0o644)
except Exception:
    pass
PY

echo "Starting ingress proxy (nginx) on :48099 ..."
nginx -g 'daemon off;' &
NGINX_PID=$!
sleep 1
if kill -0 "$NGINX_PID" 2>/dev/null; then
  echo "$NGINX_PID" > "$NGINX_PID_FILE"
  echo "nginx started with PID $NGINX_PID"
else
  echo "WARN: nginx failed to start (PID $NGINX_PID exited); ingress UI may be unavailable"
fi

# Wait for gateway; if it exits, shut down others.
wait "${GW_PID}"
