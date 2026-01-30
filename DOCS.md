# OpenClaw Assistant (Home Assistant Add-on)

This add-on runs **OpenClaw** inside **Home Assistant OS (HAOS)**.

The project deliberately keeps the add-on thin:
- Home Assistant provides the container lifecycle + Ingress
- OpenClaw provides onboarding/configuration and all assistant features

## UI / Ingress behavior

### Ingress page (inside Home Assistant)
The add-on’s Ingress UI is intentionally simple and reliable:
- A landing page
- An embedded **web terminal** (ttyd)
- A button that opens the **Gateway Web UI** in a separate tab

### Gateway Web UI (separate tab)
The Gateway Web UI requires WebSockets. Rather than tunneling it through HA Ingress,
we open it directly using a user-provided base URL (`gateway_public_url`).

## OpenClaw configuration philosophy

### We do NOT overwrite OpenClaw config
OpenClaw’s config/state lives under:
- `/config/.openclaw/` (inside the container)

The add-on **does not** rewrite OpenClaw’s configuration on each start.
You should use OpenClaw’s own interactive tooling:
- `openclaw setup`
- `openclaw onboard`
- `openclaw configure`

### Minimal bootstrap (first boot only)
If `/config/.openclaw/openclaw.json` is missing, the add-on bootstraps a minimal strict-JSON config so that
`openclaw gateway run` can start:
- `gateway.mode = local`
- `gateway.auth.mode = token`
- `gateway.auth.token` generated

After that, onboarding/configure can expand the config normally.

## Installation

1) Home Assistant → Settings → Add-ons → Add-on store
2) Add repository URL:
- Add-on store → ⋮ → Repositories → paste:
  - `https://github.com/techartdev/OpenClawHomeAssistant`
3) Install **OpenClaw Assistant**

## First-time setup checklist

1) Open the add-on page (Ingress)
2) Use the terminal and run:
   - `openclaw onboard`
   - or `openclaw configure`
3) Optional (recommended): set `gateway_public_url` in add-on options.
   - Example (LAN): `http://192.168.1.10:18789`
   - Example (public): `https://example.duckdns.org:12345`

Once `gateway_public_url` is set and OpenClaw has a gateway token, the landing page will show an “Open Gateway Web UI” button.

## Add-on options (custom / HA-specific)

### Terminal (Ingress)
- `enable_terminal` (default `true`)

Security note: the terminal gives shell access inside the add-on container.
Enable it only if you trust your HA admins.

### Gateway UI link
- `gateway_public_url` (optional)

This does not expose anything by itself; it just controls what URL the Ingress button opens.

### Home Assistant token
- `homeassistant_token` (optional)

If set, it is written to:
- `/config/secrets/homeassistant.token`

### Router SSH (generic)
These options are for custom automations that need SSH access to a router/firewall or other LAN device:
- `router_ssh_host`
- `router_ssh_user`
- `router_ssh_key_path` (default `/data/keys/router_ssh`)

How to provide the key:
- Put the private key file under the add-on config directory so it appears in-container at `/data/keys/...`
- Recommended permissions: `chmod 600`

## Troubleshooting

### Ingress loads but Gateway button is missing
- Set `gateway_public_url` in add-on options.
- If `gateway_public_url` is set but the button is still hidden, OpenClaw likely has not produced a gateway token yet.
  Use the terminal and run `openclaw onboard` / `openclaw configure`.

### Gateway UI opens but doesn’t connect
- Confirm the browser can reach `gateway_public_url` (LAN routing / DNS / NAT).
- WebSockets must be allowed end-to-end.

### Terminal isn’t visible
- Ensure `enable_terminal=true`
- Check logs for `Starting web terminal (ttyd)`
