#!/usr/bin/env python3
"""
OpenClaw config helper for Home Assistant add-on.
Safely reads/writes openclaw.json without corrupting it.
"""

import json
import os
import re
import sys
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("OPENCLAW_CONFIG_PATH", "/config/.openclaw/openclaw.json"))



def read_config():
    """Read and parse openclaw.json."""
    if not CONFIG_PATH.exists():
        return None
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, IOError) as e:
        print(f"ERROR: Failed to read config: {e}", file=sys.stderr)
        return None


def write_config(cfg):
    """Write config back to file with nice formatting."""
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
        return True
    except IOError as e:
        print(f"ERROR: Failed to write config: {e}", file=sys.stderr)
        return False


def get_gateway_setting(key, default=None):
    """Get a gateway setting from config."""
    cfg = read_config()
    if cfg is None:
        return default
    return cfg.get("gateway", {}).get(key, default)


def set_gateway_setting(key, value):
    """Set a gateway setting, preserving other config."""
    cfg = read_config()
    if cfg is None:
        cfg = {}
    
    if "gateway" not in cfg:
        cfg["gateway"] = {}
    
    cfg["gateway"][key] = value
    return write_config(cfg)


def apply_gateway_settings(mode: str, remote_url: str, bind_mode: str, port: int, enable_openai_api: bool, auth_mode: str, trusted_proxies_csv: str):
    """
    Apply gateway settings to OpenClaw config.
    
    Args:
        mode: "local" or "remote"
        remote_url: remote Gateway websocket URL (used when mode=remote)
        bind_mode: "loopback", "lan", or "tailnet"
        port: Port number to listen on (must be 1-65535)
        enable_openai_api: Enable OpenAI-compatible Chat Completions endpoint
        auth_mode: Gateway auth mode (token|trusted-proxy)
        trusted_proxies_csv: Comma-separated trusted proxy IP/CIDR list
    """
    # Validate gateway mode
    if mode not in ["local", "remote"]:
        print(f"ERROR: Invalid mode '{mode}'. Must be 'local' or 'remote'")
        return False
    
    # Validate bind mode
    if bind_mode not in ["loopback", "lan", "tailnet"]:
        print(f"ERROR: Invalid bind_mode '{bind_mode}'. Must be 'loopback', 'lan', or 'tailnet'")
        return False
    
    # Validate port range
    if port < 1 or port > 65535:
        print(f"ERROR: Invalid port {port}. Must be between 1 and 65535")
        return False

    # Validate auth mode
    if auth_mode not in ["token", "trusted-proxy"]:
        print(f"ERROR: Invalid auth_mode '{auth_mode}'. Must be 'token' or 'trusted-proxy'")
        return False
    
    cfg = read_config()
    if cfg is None:
        cfg = {}
    
    if "gateway" not in cfg:
        cfg["gateway"] = {}
    
    gateway = cfg["gateway"]

    # gateway.remote settings
    if "remote" not in gateway or not isinstance(gateway.get("remote"), dict):
        gateway["remote"] = {}
    remote_cfg = gateway["remote"]

    # auth should be nested inside gateway
    if "auth" not in gateway:
        gateway["auth"] = {}

    # http.endpoints.chatCompletions should be nested inside gateway
    if "http" not in gateway:
        gateway["http"] = {}
    if "endpoints" not in gateway["http"]:
        gateway["http"]["endpoints"] = {}
    if "chatCompletions" not in gateway["http"]["endpoints"]:
        gateway["http"]["endpoints"]["chatCompletions"] = {}
    
    auth = gateway["auth"]
    chat_completions = gateway["http"]["endpoints"]["chatCompletions"]

    trusted_proxies = [p.strip() for p in trusted_proxies_csv.split(",") if p.strip()]

    # OpenClaw trusted-proxy mode requires nested auth.trustedProxy config.
    # Use a sane default user header expected from reverse proxies.
    trusted_proxy_cfg_default = {"userHeader": "x-forwarded-user"}

    current_mode = gateway.get("mode", "")
    current_remote_url = remote_cfg.get("url", "")
    current_bind = gateway.get("bind", "")
    current_port = gateway.get("port", 18789)
    current_openai_api = chat_completions.get("enabled", False)
    current_auth_mode = auth.get("mode", "token")
    current_trusted_proxies = gateway.get("trustedProxies", [])
    current_trusted_proxy_cfg = auth.get("trustedProxy")
    
    changes = []
    
    if current_mode != mode:
        gateway["mode"] = mode
        changes.append(f"mode: {current_mode} -> {mode}")

    if current_remote_url != remote_url:
        remote_cfg["url"] = remote_url
        changes.append(f"remote.url: {current_remote_url} -> {remote_url}")
    
    if current_bind != bind_mode:
        gateway["bind"] = bind_mode
        changes.append(f"bind: {current_bind} -> {bind_mode}")
    
    if current_port != port:
        gateway["port"] = port
        changes.append(f"port: {current_port} -> {port}")
    
    if current_openai_api != enable_openai_api:
        chat_completions["enabled"] = enable_openai_api
        changes.append(f"chatCompletions.enabled: {current_openai_api} -> {enable_openai_api}")
    
    if current_auth_mode != auth_mode:
        auth["mode"] = auth_mode
        changes.append(f"auth.mode: {current_auth_mode} -> {auth_mode}")

    if current_trusted_proxies != trusted_proxies:
        gateway["trustedProxies"] = trusted_proxies
        changes.append(f"trustedProxies: {current_trusted_proxies} -> {trusted_proxies}")

    if auth_mode == "trusted-proxy":
        if current_trusted_proxy_cfg != trusted_proxy_cfg_default:
            auth["trustedProxy"] = trusted_proxy_cfg_default
            changes.append("auth.trustedProxy: configured default userHeader=x-forwarded-user")
    
    if changes:
        if write_config(cfg):
            print(f"INFO: Updated gateway settings: {', '.join(changes)}")
            return True
        else:
            print("ERROR: Failed to write config")
            return False
    else:
        print(f"INFO: Gateway settings already correct (mode={mode}, remoteUrl={remote_url}, bind={bind_mode}, port={port}, chatCompletions={enable_openai_api}, authMode={auth_mode}, trustedProxies={trusted_proxies})")
        return True


def set_control_ui_origins(origins_csv: str, additional_origins_csv: str = "", disable_device_auth: bool = True): 
    """
    Configure gateway.controlUi for the built-in HTTPS proxy.

    Sets:
      - allowedOrigins: the HTTPS proxy origins so the browser WebSocket
        is accepted (required since v2026.2.21).
      - dangerouslyDisableDeviceAuth: controlled by add-on option
        `controlui_disable_device_auth` (default true). When true, skips
        interactive device pairing; token auth remains enforced.

    Also removes any stale/invalid keys (e.g. pairingMode) that may have
    been written by earlier add-on versions.

    Args:
        origins_csv: Comma-separated list of default origins provided by the add-on.
        additional_origins_csv: Comma-separated list of user-provided extra origins.
    """
    cfg = read_config()
    if cfg is None:
        cfg = {}

    if "gateway" not in cfg:
        cfg["gateway"] = {}
    gateway = cfg["gateway"]

    if "controlUi" not in gateway:
        gateway["controlUi"] = {}

    control_ui = gateway["controlUi"]
    default_origins = [o.strip() for o in origins_csv.split(",") if o.strip()]
    additional_origins = [o.strip() for o in (additional_origins_csv or "").split(",") if o.strip()]
    changes = []

    # --- allowedOrigins ---
    current_origins = control_ui.get("allowedOrigins", [])
    if not isinstance(current_origins, list):
        current_origins = []

    merged_origins = []
    for origin in [*default_origins, *current_origins, *additional_origins]:
        if isinstance(origin, str) and origin and origin not in merged_origins:
            merged_origins.append(origin)

    if current_origins != merged_origins:
        control_ui["allowedOrigins"] = merged_origins
        changes.append(f"allowedOrigins: {current_origins} -> {merged_origins}")

    # --- dangerouslyDisableDeviceAuth ---
    # Optional bypass of interactive per-device pairing (error 1008: pairing required).
    # Token auth is still enforced; this only controls the approval ceremony.
    desired_device_auth_flag = True if disable_device_auth else False
    if control_ui.get("dangerouslyDisableDeviceAuth") is not desired_device_auth_flag:
        prev = control_ui.get("dangerouslyDisableDeviceAuth")
        control_ui["dangerouslyDisableDeviceAuth"] = desired_device_auth_flag
        changes.append(f"dangerouslyDisableDeviceAuth: {prev} -> {desired_device_auth_flag}")

    # --- Remove invalid keys from earlier add-on versions ---
    for stale_key in ("pairingMode",):
        if stale_key in control_ui:
            del control_ui[stale_key]
            changes.append(f"removed invalid key: {stale_key}")

    if not changes:
        status = "disabled" if desired_device_auth_flag else "enabled"
        print(f"INFO: controlUi already correct: origins={merged_origins}, deviceAuth={status}")
        return True

    if write_config(cfg):
        print(f"INFO: Updated controlUi: {', '.join(changes)}")
        return True
    print("ERROR: Failed to write config")
    return False


def main():
    """CLI entry point for use by run.sh"""
    if len(sys.argv) < 2:
        print("Usage: oc_config_helper.py <command> [args...]")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "apply-gateway-settings":
        if len(sys.argv) != 9:
            print("Usage: oc_config_helper.py apply-gateway-settings <local|remote> <remote_url> <loopback|lan|tailnet> <port> <enable_openai_api:true|false> <auth_mode:token|trusted-proxy> <trusted_proxies_csv>")
            sys.exit(1)
        mode = sys.argv[2]
        remote_url = sys.argv[3]
        bind_mode = sys.argv[4]
        port = int(sys.argv[5])
        enable_openai_api = sys.argv[6].lower() == "true"
        auth_mode = sys.argv[7]
        trusted_proxies_csv = sys.argv[8]
        success = apply_gateway_settings(mode, remote_url, bind_mode, port, enable_openai_api, auth_mode, trusted_proxies_csv)
        sys.exit(0 if success else 1)
    
    elif cmd == "get":
        if len(sys.argv) != 3:
            print("Usage: oc_config_helper.py get <key>")
            sys.exit(1)
        key = sys.argv[2]
        value = get_gateway_setting(key)
        if value is not None:
            print(value)
        sys.exit(0)
    
    elif cmd == "set-control-ui-origins":
        if len(sys.argv) not in (3, 4, 5):
            print("Usage: oc_config_helper.py set-control-ui-origins <origins_csv> [additional_origins_csv] [disable_device_auth:true|false]")
            sys.exit(1)
        origins_csv = sys.argv[2]
        additional_origins_csv = sys.argv[3] if len(sys.argv) >= 4 else ""
        disable_device_auth = True
        if len(sys.argv) == 5:
            disable_device_auth = sys.argv[4].strip().lower() == "true"
        success = set_control_ui_origins(origins_csv, additional_origins_csv, disable_device_auth)
        sys.exit(0 if success else 1)

    elif cmd == "set":
        if len(sys.argv) != 4:
            print("Usage: oc_config_helper.py set <key> <value>")
            sys.exit(1)
        key = sys.argv[2]
        value = sys.argv[3]
        # Try to convert to int if it looks like a number
        try:
            value = int(value)
        except ValueError:
            pass
        success = set_gateway_setting(key, value)
        sys.exit(0 if success else 1)
    
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
