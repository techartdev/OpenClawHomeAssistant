# OpenClaw Assistant (Home Assistant Add-on)

This add-on runs **OpenClaw** inside **Home Assistant OS (HAOS)**.

It’s designed to be friendly to non-technical users:
- The add-on provides a simple Home Assistant page (Ingress) with a terminal.
- You complete setup using OpenClaw’s built-in onboarding commands.

---

## 0) What is what? (quick explanation)

- **Ingress page** (inside Home Assistant): a landing page + terminal.
- **Gateway**: the OpenClaw server running inside the add-on container.
- **Gateway Web UI (Control UI)**: the web interface you open in your browser.

The Gateway UI is opened in a **separate tab** (not embedded), because Home Assistant Ingress can have WebSocket issues.

---

## 1) Install the add-on

1) Home Assistant → **Settings → Add-ons → Add-on store**
2) Add repository URL:
- Add-on store → ⋮ → **Repositories** → paste:
  - `https://github.com/techartdev/OpenClawHomeAssistant`
3) Install **OpenClaw Assistant**
4) Start the add-on

---

## 2) First-time setup (step-by-step)

Open the add-on page (Ingress). You will see:
- **Open Gateway Web UI** button
- **Terminal** embedded on the page

### Step A — Run OpenClaw onboarding

In the terminal, run:

- **Recommended**:
  - `openclaw onboard`

If you prefer:
- `openclaw configure`

Follow the prompts.

### Step B — Get your Gateway token (needed for the Web UI)

In the terminal run:

```sh
openclaw config get gateway.auth.token
```

Copy the token somewhere safe.

### Step C — Make the Gateway reachable from your browser

You have two common setups:

#### Option 1: Use Home Assistant HTTPS (recommended)
If your Home Assistant is already exposed via HTTPS (Nabu Casa, reverse proxy, etc.), use that.
This avoids browser security issues.

#### Option 2: LAN access (http://192.168.x.x)
If you want to open it directly on your LAN, you must ensure OpenClaw binds to LAN.
In the terminal:

```sh
openclaw config set gateway.bind lan
openclaw config set gateway.port 18789
openclaw config set gateway.mode local
```

Then restart the add-on.

---

## 3) Configure the “Open Gateway Web UI” button

The button uses the add-on option:
- `gateway_public_url`

Set it in Home Assistant → Add-on configuration.

Examples:
- LAN:
  - `http://192.168.1.119:18789`
- Public HTTPS:
  - `https://example.duckdns.org:12345`

The button will open:

`<gateway_public_url>/?token=<your_token>`

If the UI says **Unauthorized**, you likely used the wrong token. Re-check it with:

```sh
openclaw config get gateway.auth.token
```

---

## 4) Important: “requires HTTPS or localhost (secure context)”

Modern browsers sometimes refuse to run the Control UI on **plain HTTP** unless it is **localhost**.
If you open the Gateway UI over LAN HTTP and see:

> control ui requires HTTPS or localhost (secure context)

You have 3 options:

### Option A — Use HTTPS (best)
Put the gateway behind HTTPS (recommended long-term).

### Option B — Use localhost via port-forward
Access it as `http://localhost:18789` using SSH port forwarding from your computer.

### Option C — Allow insecure auth (quick workaround; less secure)
In the terminal:

```sh
openclaw config set gateway.controlUi.allowInsecureAuth true
```

This allows using the Control UI over LAN HTTP.

---

## 5) Add-on options (custom / HA-specific)

This add-on intentionally keeps options minimal. See `openclaw_assistant/config.yaml`.

### Terminal
- `enable_terminal` (default **true**)

Security note: the terminal gives shell access inside the add-on container.

### Home Assistant token
- `homeassistant_token` (optional)

If set, it is written to:
- `/config/secrets/homeassistant.token`

### Router SSH (generic)
For custom automations that need SSH access to a router/firewall or other LAN device:
- `router_ssh_host`
- `router_ssh_user`
- `router_ssh_key_path` (default `/data/keys/router_ssh`)

How to provide the key:
- Put the private key file under the add-on config directory so it appears in-container at `/data/keys/...`
- Recommended permissions: `chmod 600`

---

## Troubleshooting

### I get ERR_CONNECTION_REFUSED
- The gateway is not reachable at that IP/port.
- Confirm bind/port in terminal:
  - `openclaw config get gateway.bind`
  - `openclaw config get gateway.port`

### The Gateway UI opens but shows Unauthorized
- Fetch the token:
  - `openclaw config get gateway.auth.token`

### Terminal isn’t visible
- Ensure `enable_terminal=true`
- Check logs for `Starting web terminal (ttyd)`
