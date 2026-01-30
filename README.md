# OpenClaw Assistant – Home Assistant Add-on (Draft)

This repository contains a Home Assistant add-on that runs an **OpenClaw Assistant** instance on **HAOS**.

Upstream note: the project has gone through renames. This add-on installs **OpenClaw**.

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
2. Install **OpenClaw Assistant**
3. Configure options (at minimum: Telegram bot token)

## Setup / Docs
See **DOCS.md** for the supported setups:
- embedded terminal via Ingress
- opening Gateway Web UI in a new tab (not embedded)

## Configuration
All configuration is done via the add-on UI.
See the schema in `openclaw_assistant/config.yaml`.

### Optional: Brave Search
If you provide `brave_api_key`, the add-on exports `BRAVE_API_KEY` for the assistant’s web search tool.

### Optional: Home Assistant token
If you provide `homeassistant_token`, it is written to `/config/secrets/homeassistant.token` inside the container for local scripts/tools.

### Optional: Router SSH (generic)
If you want the assistant to automate local network/router configuration over SSH, see **DOCS.md** (Router SSH section).

## UI
- The main add-on page loads the Gateway UI via **Ingress**.
- If enabled, web terminal is available at `/terminal/` under the ingress UI.

## Status
This is still in "draft" while we finalize naming, docs, and a public release process.
