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


def apply_gateway_settings(mode: str, bind_mode: str, port: int, enable_openai_api: bool, allow_insecure_auth: bool):
    """
    Apply gateway settings to OpenClaw config.
    
    Args:
        mode: "local" or "remote"
        bind_mode: "loopback", "lan", "tailnet", or "auto"
        port: Port number to listen on (must be 1-65535)
        enable_openai_api: Enable OpenAI-compatible Chat Completions endpoint
        allow_insecure_auth: Allow insecure HTTP authentication
    """
    # Validate gateway mode
    if mode not in ["local", "remote"]:
        print(f"ERROR: Invalid mode '{mode}'. Must be 'local' or 'remote'")
        return False
    
    # Validate bind mode
    if bind_mode not in ["loopback", "lan", "tailnet", "auto"]:
        print(f"ERROR: Invalid bind_mode '{bind_mode}'. Must be 'loopback', 'lan', 'tailnet', or 'auto'")
        return False
    
    # Validate port range
    if port < 1 or port > 65535:
        print(f"ERROR: Invalid port {port}. Must be between 1 and 65535")
        return False
    
    cfg = read_config()
    if cfg is None:
        cfg = {}
    
    if "gateway" not in cfg:
        cfg["gateway"] = {}
    
    gateway = cfg["gateway"]
    
    # controlUi should be nested inside gateway
    if "controlUi" not in gateway:
        gateway["controlUi"] = {}
    
    # http.endpoints.chatCompletions should be nested inside gateway
    if "http" not in gateway:
        gateway["http"] = {}
    if "endpoints" not in gateway["http"]:
        gateway["http"]["endpoints"] = {}
    if "chatCompletions" not in gateway["http"]["endpoints"]:
        gateway["http"]["endpoints"]["chatCompletions"] = {}
    
    control_ui = gateway["controlUi"]
    chat_completions = gateway["http"]["endpoints"]["chatCompletions"]
    
    current_mode = gateway.get("mode", "")
    current_bind = gateway.get("bind", "")
    current_port = gateway.get("port", 18789)
    current_openai_api = chat_completions.get("enabled", False)
    current_insecure = control_ui.get("allowInsecureAuth", False)
    
    changes = []
    
    if current_mode != mode:
        gateway["mode"] = mode
        changes.append(f"mode: {current_mode} -> {mode}")
    
    if current_bind != bind_mode:
        gateway["bind"] = bind_mode
        changes.append(f"bind: {current_bind} -> {bind_mode}")
    
    if current_port != port:
        gateway["port"] = port
        changes.append(f"port: {current_port} -> {port}")
    
    if current_openai_api != enable_openai_api:
        chat_completions["enabled"] = enable_openai_api
        changes.append(f"chatCompletions.enabled: {current_openai_api} -> {enable_openai_api}")
    
    if current_insecure != allow_insecure_auth:
        control_ui["allowInsecureAuth"] = allow_insecure_auth
        changes.append(f"allowInsecureAuth: {current_insecure} -> {allow_insecure_auth}")
    
    if changes:
        if write_config(cfg):
            print(f"INFO: Updated gateway settings: {', '.join(changes)}")
            return True
        else:
            print("ERROR: Failed to write config")
            return False
    else:
        print(f"INFO: Gateway settings already correct (mode={mode}, bind={bind_mode}, port={port}, chatCompletions={enable_openai_api}, allowInsecureAuth={allow_insecure_auth})")
        return True


def main():
    """CLI entry point for use by run.sh"""
    if len(sys.argv) < 2:
        print("Usage: oc_config_helper.py <command> [args...]")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "apply-gateway-settings":
        if len(sys.argv) != 7:
            print("Usage: oc_config_helper.py apply-gateway-settings <local|remote> <loopback|lan|tailnet|auto> <port> <enable_openai_api:true|false> <allow_insecure:true|false>")
            sys.exit(1)
        mode = sys.argv[2]
        bind_mode = sys.argv[3]
        port = int(sys.argv[4])
        enable_openai_api = sys.argv[5].lower() == "true"
        allow_insecure_auth = sys.argv[6].lower() == "true"
        success = apply_gateway_settings(mode, bind_mode, port, enable_openai_api, allow_insecure_auth)
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
