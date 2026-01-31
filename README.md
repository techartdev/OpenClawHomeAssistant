# OpenClaw Assistant – Home Assistant Add-on

This repository contains a Home Assistant add-on that runs **OpenClaw** inside **Home Assistant OS (HAOS)**.

> Upstream rename history (FYI): clawdbot → moltbot → **openclaw** (final).

## What you get

- An always-on OpenClaw gateway running as a Supervisor-managed add-on.
- A reliable **Ingress landing page** inside Home Assistant that includes:
  - an embedded **web terminal** (ttyd)
  - a button to open the **Gateway Web UI** in a **separate browser tab** (not embedded)
- Persistent state under the add-on config directory (in-container: `/config`).

## Why the Gateway UI is not embedded in Ingress

The Gateway Web UI requires WebSockets that can be flaky through HA Ingress depending on proxying/mixed-content.
So we **don’t embed** it. Instead, the Ingress page gives you a button that opens the Gateway UI directly using
`gateway_public_url`.

## Security model (high level)

- The add-on **does not** manage or overwrite OpenClaw’s full config.
- OpenClaw is configured via its own interactive tools (`openclaw setup`, `openclaw onboard`, `openclaw configure`) using the terminal.
- On first boot only (when config is missing), the add-on bootstraps a minimal config to let the gateway start:
  - `gateway.mode=local`
  - `gateway.auth.mode=token` with a generated token

## Install

1. Home Assistant → **Settings → Add-ons → Add-on store**
2. **⋮ → Repositories**
3. Add this repo:
   - `https://github.com/techartdev/OpenClawHomeAssistant`
4. Install **OpenClaw Assistant**

## First run (recommended)

1. Open the add-on page (Ingress) and use the embedded terminal.
2. Run one of:
   - `openclaw onboard`
   - `openclaw configure`
3. (Optional, but recommended) Set **gateway_public_url** in add-on options.
   - Then the Ingress page will show an "Open Gateway Web UI" button.

## Add-on options (kept intentionally small)

See `openclaw_assistant/config.yaml` for the authoritative schema.

- `enable_terminal` (default: **true**) — enables the embedded web terminal.
- `gateway_public_url` — only used to build the external Gateway UI link.
- `timezone`
- `homeassistant_token` (optional) — written to `/config/secrets/homeassistant.token` for local scripts.
- `router_ssh_*` (optional) — SSH settings for a router/network device (custom automation).

## Docs

See **DOCS.md** for a step-by-step first-time setup guide + troubleshooting.

## Support / Donations

Hey! You can send me money on Revolut by following this link:
- https://revolut.me/vanyo6dhw
