# Moltbot Assistant (Home Assistant Add-on)

This add-on runs a Moltbot Assistant instance on Home Assistant OS (Supervisor add-on).

> Note: Moltbot is the new name for the upstream Clawdbot project. Internally, this add-on may still use the `clawdbot` CLI/package as a compatibility layer.

## Features
- Ingress UI inside Home Assistant (no LAN port required)
- Telegram channel support (bot token)
- Optional Brave web search (Brave API key)
- Optional Home Assistant long-lived token persisted in the add-on secrets folder
- Optional web terminal inside Home Assistant (disabled by default)

## Installation
1. Home Assistant → Settings → Add-ons → Add-on store
2. Add repository URL:
   - Add-on store → ⋮ → Repositories → paste the GitHub repo URL
3. Install **Moltbot Assistant**

## Configuration
Configure via the add-on UI.

Required:
- `telegram_bot_token`

Recommended:
- `gateway_bind`: `loopback`
- `gateway_token`: set a fixed token (Ingress proxy uses it server-side)

Optional:
- `telegram_allow_from`: comma-separated Telegram user IDs
- `homeassistant_token`: written to `/config/secrets/homeassistant.token`
- `brave_api_key`: exported as `BRAVE_API_KEY` (for web search)
- `enable_terminal`: enables web terminal at `/terminal/`

## UI / Ingress
- The add-on uses **Ingress**. Open the add-on page to access the gateway UI.
- If `enable_terminal=true`, the terminal is available under the same ingress base at `/terminal/`.

## Security notes
- Keep `gateway_bind=loopback` unless you know what you’re doing.
- Terminal is powerful: only enable it if you trust all Home Assistant admins with shell access to the add-on container.

## Troubleshooting
- If Ingress loads but the gateway UI is unauthorized, verify `gateway_token` is set.
- If Telegram doesn’t connect, verify the bot token using @BotFather and check add-on logs.
- If search tools fail, check that `brave_api_key` is set and that your plan limits aren’t exceeded.
