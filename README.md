# Moltbot Assistant – Home Assistant Add-on (Draft)

This repository contains a Home Assistant add-on that runs a **Moltbot Assistant** instance on **HAOS**.

Upstream note: Moltbot is the new name for the Clawdbot project. The add-on may still install/use the `clawdbot` npm package/CLI for compatibility until the upstream transition fully settles.

## What you get
- Always-on personal assistant running as a Supervisor-managed container
- Home Assistant **Ingress UI** (the assistant Gateway UI inside the add-on page)
- Optional **web terminal** inside Home Assistant (disabled by default)
- Persistent data stored under the add-on config directory (in-container: `/config`)

## Security defaults
- Gateway binds to **loopback** by default (not exposed on LAN)
- Terminal is **off by default**
- Tokens/IDs are provided via add-on options and are never hardcoded

## Install (high level)
1. Add this repo in Home Assistant:
   Settings → Add-ons → Add-on Store → ⋮ → Repositories
2. Install **Moltbot Assistant**
3. Configure options (at minimum: Telegram bot token)

## Configuration
All configuration is done via the add-on UI.
See the schema in `moltbot_assistant/config.yaml`.

### Optional: Brave Search
If you provide `brave_api_key`, the add-on exports `BRAVE_API_KEY` for the assistant’s web search tool.

### Optional: Home Assistant token
If you provide `homeassistant_token`, it is written to `/config/secrets/homeassistant.token` inside the container for local scripts/tools.

### Optional: MikroTik SSH
If you want MikroTik automation, provide:
- `mikrotik_host`
- `mikrotik_ssh_user`
- `mikrotik_ssh_key_path` (default: `/data/keys/mikrotik`)

Place the SSH key file under the add-on config folder (e.g., with File editor), so it appears in-container at `/data/keys/...`.

## UI
- The main add-on page loads the Gateway UI via **Ingress**.
- If enabled, web terminal is available at `/terminal/` under the ingress UI.

## Status
This is still in "draft" while we finalize naming, docs, and a public release process.
