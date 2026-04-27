# OpenClaw Assistant — Home Assistant Add-on Documentation

This add-on runs [OpenClaw](https://github.com/openclaw/openclaw) inside Home Assistant OS (HAOS). It provides a fully self-contained environment with a web terminal, gateway server, and all the tools OpenClaw needs — no manual Docker setup required.

**Table of Contents**

1. [Architecture Overview](#1-architecture-overview)
2. [Installation](#2-installation)
3. [First-Time Setup](#3-first-time-setup)
4. [Accessing the Gateway Web UI](#4-accessing-the-gateway-web-ui)
5. [Configuration Reference](#5-configuration-reference)
6. [Use Case Guides](#6-use-case-guides)
7. [Data Persistence & Skills](#7-data-persistence--skills)
8. [Bundled Tools](#8-bundled-tools)
9. [Updating & Backup](#9-updating--backup)
10. [Troubleshooting](#10-troubleshooting)
11. [FAQ](#11-faq)

> **Important**: Before using this add-on, please read the [Security Risks & Disclaimer](SECURITY.md).

---

## 1. Architecture Overview

### What runs inside the add-on

The add-on container runs three services:

| Service | Port | Purpose |
|---|---|---|
| **OpenClaw Gateway** | 18789 (configurable) | The AI agent server — handles skills, chat, automations |
| **nginx** (Ingress proxy) | 48099 (fixed) | Serves the landing page inside Home Assistant |
| **ttyd** (Web terminal) | 7681 (configurable) | Provides a browser-based terminal for setup and management |

When you open the add-on page in Home Assistant, nginx serves a landing page with:
- An **Open Gateway Web UI** button (opens in a new tab to avoid WebSocket issues with Ingress)
- An embedded **terminal** for running commands

### Key directories

| Path | Persistent? | Contents |
|---|---|---|
| `/config/` | Yes | All user data — survives add-on updates and rebuilds |
| `/config/.openclaw/` | Yes | OpenClaw configuration (`openclaw.json`), skills, agent data |
| `/config/clawd/` | Yes | Agent workspace (ClawHub-installed skills, files) |
| `/config/.node_global/` | Yes | User-installed npm packages (skills installed via dashboard) |
| `/config/secrets/` | Yes | Tokens (e.g., `homeassistant.token`) |
| `/config/keys/` | Yes | SSH keys (e.g., router SSH key) |
| `/config/.linuxbrew/` | Yes | Homebrew install and brew-installed CLI tools |
| `/config/gogcli/` | Yes | gog OAuth credentials for Google APIs |
| `/usr/lib/node_modules/openclaw/` | No | OpenClaw installation (rebuilt with each image update) |

> **Important**: Everything under `/config/` persists across add-on updates. The container filesystem (`/usr/`, `/opt/`, etc.) is rebuilt each time the image changes.

---

## 2. Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on store**
2. Click ⋮ (top-right) → **Repositories** → paste one of:
   - **Stable**: `https://github.com/techartdev/OpenClawHomeAssistant`
   - **Dev/Experimental**: `https://github.com/techartdev/OpenClawHomeAssistant-dev`
3. Find and install **OpenClaw Assistant**
4. Click **Start**

**Supported architectures**: amd64, aarch64 (Raspberry Pi 4/5), armv7

---

## 3. First-Time Setup

### What happens on first boot

When the add-on starts for the first time, it automatically:
1. Creates persistent directories under `/config/`
2. Generates a minimal `openclaw.json` with a random gateway auth token
3. Syncs built-in skills to persistent storage
4. Starts the gateway, terminal, and nginx

### Step 1 — Run onboarding

Open the add-on page in Home Assistant. You'll see a landing page with an embedded terminal.

In the terminal, run:

```sh
openclaw onboard
```

This interactive wizard walks you through connecting your AI providers (OpenAI, Google, Anthropic, etc.) and basic configuration.

> **Note (v0.5.54+)**: If onboarding triggers a gateway runtime restart, the add-on now keeps nginx/terminal alive and auto-recovers the runtime instead of restarting the whole container.

Alternatively, for more granular control:

```sh
openclaw configure
```

### Step 2 — Get your Gateway token

The gateway requires a token for authentication. To retrieve it:

```sh
jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json
```

> **Note**: Since OpenClaw v2026.2.22+ `openclaw config get` redacts sensitive values (returns `openclaw_redacted`). Read the token directly from the config file with `jq` as shown above.

Save this token — you'll need it to access the Gateway Web UI and for API integrations.

### Step 3 — Verify everything works

1. In the terminal, confirm the gateway is running:
   ```sh
   openclaw gateway status
   ```
2. Click the **Open Gateway Web UI** button on the landing page
3. If prompted for a token, paste the one from Step 2 or go to the Overview tab, paste the token in the 'Gateway Token' field and press Connect.

---

## 4. Accessing the Gateway Web UI

The Gateway Web UI (Control UI) is OpenClaw's main web interface. It opens in a **separate browser tab** because Home Assistant's Ingress proxy has WebSocket limitations.

> **Important (v2026.2.21+):** OpenClaw now requires a **secure context** (HTTPS or localhost) for the Control UI. Plain HTTP over LAN is no longer accepted. The add-on's `access_mode` option makes this easy — see below.
>
> **v2026.2.22 note:** The gateway now emits a startup security warning when `dangerouslyDisableDeviceAuth` is active (used by `lan_https` mode). This warning is **expected and safe to ignore** — token authentication is still enforced.

### Choosing an access mode

Set `access_mode` in **Settings → Add-ons → OpenClaw Assistant → Configuration**:

| Mode | Best for | What it does |
|---|---|---|
| **`lan_https`** | Phones, tablets, LAN browsers | Adds a built-in HTTPS proxy inside the add-on. No external setup needed. |
| **`lan_reverse_proxy`** | Users with NPM / Caddy / Traefik | Binds gateway to LAN; your proxy terminates TLS. |
| **`tailnet_https`** | Tailscale users | Binds to Tailscale interface; use Tailscale HTTPS certs. |
| **`local_only`** | Terminal/Ingress only | Loopback — gateway not reachable from other devices. |
| **`custom`** | Advanced / backward compat | Uses the individual `gateway_bind_mode` / `gateway_auth_mode` settings. |

### Method A — Built-in HTTPS proxy (`lan_https` — recommended)

This is the simplest way to get secure LAN access, especially for phones and tablets.

1. Go to **Settings → Add-ons → OpenClaw Assistant → Configuration**
2. Set `access_mode`: **lan_https**
3. Restart the add-on

**What happens automatically:**
- The add-on generates a local CA certificate and a TLS server certificate
- nginx listens on the gateway port (default 18789) with HTTPS on all interfaces
- The gateway process itself binds to loopback on an internal port (gateway_port + 1)
- The landing page shows a **Download CA Certificate** button

**Phone/tablet setup (one-time):**
1. Open the add-on page in HA and click **Download CA Certificate**
2. Install the certificate on your device:
   - **Android**: Settings → Security → Install certificate → CA certificate → select file
   - **iOS**: Open the `.crt` file → Install Profile → Settings → General → About → Certificate Trust Settings → enable the OpenClaw CA
3. After installing the CA, your browser will trust the gateway without warnings

> **Note**: If you skip CA installation, you can still access the gateway — just accept the browser's certificate warning once.

### Method B — HTTPS via external reverse proxy (tested recipe: NPM)

Use this when you already run Nginx Proxy Manager (or Caddy/Traefik).

**OpenClaw add-on settings**
1. Set `access_mode`: **lan_reverse_proxy**
2. Set `gateway_trusted_proxies` to your proxy source CIDR/IP.
   - Example for NPM add-on network: `172.30.0.0/16`
   - Or strict single IP: `172.30.x.y/32`
3. Set `gateway_public_url` to your final HTTPS URL (example: `https://openclaw.example.com`)
4. Restart OpenClaw add-on

**NPM host config (known-good pattern)**
1. Create Proxy Host: `openclaw.example.com`
2. Forward to: `http://<HA-LAN-IP>:18789`
3. Enable **Websockets Support**
4. SSL tab: request/attach certificate, enable **Force SSL**
5. Add custom header for trusted-proxy auth:
   - `X-Forwarded-User: openclaw`

Then open `https://openclaw.example.com`.

> **Important**: Nabu Casa remote access only proxies port 8123. It does not expose custom add-on ports directly.

### Method C — SSH port forwarding (secure, no config changes)

Forward the gateway port from your HA host to your local machine:

```sh
ssh -L 18789:127.0.0.1:18789 your-user@your-ha-ip
```

Then open `http://localhost:18789` in your browser. `localhost` counts as a secure context.

> **Limitation**: SSH forwarding doesn't work on phones/tablets. Use `lan_https` for mobile access.

### Method D — Tailnet flow (tested with HA Tailscale add-on + NPM)

This is the practical flow users report as stable in HAOS.

1. In **Tailscale add-on**:
   - Disable `userspace_networking` (must be `false` so other add-ons can reach tailnet interface)
2. In **OpenClaw add-on**:
   - Preferred: set `access_mode` to **tailnet_https**
   - Alternative (equivalent): `gateway_bind_mode: tailnet`, token auth
3. In **NPM**:
   - Forward target to `http://<HA-TAILNET-IP>:18789`
   - Enable websockets
   - Configure TLS cert on the public host
4. Set `gateway_public_url` to the final HTTPS URL and restart OpenClaw

> **Why this flow**: `tailnet_https` in this add-on is a bind/auth preset. It does not automatically run `tailscale serve` inside OpenClaw.

### Setting up the "Open Gateway Web UI" button

Set `gateway_public_url` in the add-on configuration to the URL where the gateway is reachable from your browser.

**Examples**:
- LAN HTTPS (built-in): `https://192.168.1.119:18789`
- External HTTPS: `https://openclaw.example.com`
- Tailscale: `https://ha-machine.ts.net:18789`

> **Tip**: In `lan_https` mode, if you leave `gateway_public_url` empty, the add-on auto-constructs it from the detected LAN IP.

### Browser security: "requires HTTPS or localhost"

If you see:

> control ui requires HTTPS or localhost (secure context)
> disconnected (1008): control ui requires device identity

This means the browser is connecting over plain HTTP. **Solutions**:
- Set `access_mode` to **lan_https** (easiest — no external setup)
- Set `access_mode` to **lan_reverse_proxy** and use an HTTPS reverse proxy
- Use SSH port forwarding to `localhost` (desktop only)

### Unauthorized error

If the Gateway UI shows **Unauthorized**, re-check your token:

```sh
jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json
```

> **Note**: Since OpenClaw v2026.2.22+ `openclaw config get` redacts sensitive values — use `jq` to read directly from the config file.

---

## 5. Configuration Reference

All options are set via **Settings → Apps/Add-ons → OpenClaw Assistant → Configuration** in Home Assistant. They are applied automatically on each add-on restart.

### General

| Option | Type | Default | Description |
|---|---|---|---|
| `timezone` | string | `Europe/Sofia` | Timezone for the add-on (e.g., `America/New_York`, `Europe/London`) |

### Gateway

| Option | Type | Default | Description |
|---|---|---|---|
| `gateway_mode` | `local` / `remote` | `local` | **local**: run gateway in this add-on. **remote**: connect to an external gateway |
| `gateway_remote_url` | string | _(empty)_ | Remote gateway WebSocket URL used when `gateway_mode: remote` (example: `ws://192.168.1.20:18789` or `wss://gateway.example.com:443`) |
| `gateway_bind_mode` | `loopback` / `lan` / `tailnet` | `loopback` | **loopback**: 127.0.0.1 only (secure). **lan**: all interfaces (LAN-accessible). **tailnet**: Tailscale interface only. Only applies when `gateway_mode` is `local` |
| `gateway_port` | int | `18789` | Port for the gateway. Only applies when `gateway_mode` is `local` |
| `access_mode` | `custom` / `local_only` / `lan_https` / `lan_reverse_proxy` / `tailnet_https` | `custom` | **Simplifies secure access setup.** `custom`: use individual settings (backward-compatible). `lan_https`: built-in HTTPS proxy for LAN (recommended for phones). `lan_reverse_proxy`: external reverse proxy. `tailnet_https`: Tailscale. `local_only`: Ingress only. See [Accessing the Gateway Web UI](#4-accessing-the-gateway-web-ui) |
| `gateway_public_url` | string | _(empty)_ | Public URL for the "Open Gateway Web UI" button. Auto-constructed in `lan_https` mode if empty. Example: `https://192.168.1.119:18789`. In newer versions this origin is also merged into `gateway.controlUi.allowedOrigins` to reduce reverse-proxy origin errors. |
| `enable_openai_api` | bool | `false` | Enable the OpenAI-compatible `/v1/chat/completions` endpoint. Required for [Assist pipeline integration](#6c-assist-pipeline-integration-openai-api) |
| `gateway_auth_mode` | `token` / `trusted-proxy` | `token` | Gateway auth mode. Use `trusted-proxy` when terminating HTTPS in a reverse proxy and forwarding trusted auth headers. |
| `gateway_trusted_proxies` | string | _(empty)_ | Comma-separated trusted proxy IP/CIDR list used with `gateway_auth_mode: trusted-proxy`. |
| `gateway_additional_allowed_origins` | string | _(empty)_ | Comma-separated additional origins merged into `gateway.controlUi.allowedOrigins` in `lan_https` mode (example: `https://ha.example.com:8443,capacitor://localhost`). |
| `controlui_disable_device_auth` | bool | `true` | Controls `gateway.controlUi.dangerouslyDisableDeviceAuth` in `lan_https` mode. **ON (recommended):** skip per-device pairing approval, avoid error 1008 on LAN HTTPS, token auth still required. **OFF:** enforce per-device pairing prompts (stricter, but more friction). |
| `force_ipv4_dns` | bool | `true` | Force IPv4-first DNS ordering for Node network calls. **Recommended ON** — most HAOS VMs lack IPv6 egress, causing `web_fetch` and Telegram timeouts. Set to `false` only if your network has working IPv6. |
| `gateway_env_vars` | list of `{name, value}` | `[]` | Environment variables exported to the gateway process at startup. UI format: list entries with `name` and `value` (example: `name=OPENAI_API_KEY`, `value=sk-...`). Limits: max 50 vars, key length 255, value length 10000. Reserved runtime keys are blocked (for example `PATH`, `HOME`, `NODE_OPTIONS`, `NODE_PATH`, `OPENCLAW_*`, proxy vars). Legacy string/object formats are still accepted for backward compatibility. |
| `nginx_log_level` | `full` / `minimal` | `minimal` | Nginx access log verbosity. `minimal` suppresses repetitive Home Assistant health-check and polling requests (`GET /`, `GET /v1/models`). `full` logs everything. |

When `gateway_auth_mode: trusted-proxy` is used, the add-on sets `gateway.auth.trustedProxy.userHeader` to `x-forwarded-user` by default.

### Terminal

| Option | Type | Default | Description |
|---|---|---|---|
| `enable_terminal` | bool | `true` | Show the web terminal on the add-on page |
| `terminal_port` | int | `7681` | Port for the terminal (ttyd). Change if 7681 conflicts. Range: 1024-65535 |

### Security & Tokens

| Option | Type | Default | Description |
|---|---|---|---|
| `homeassistant_token` | string | _(empty)_ | Optional HA long-lived access token (use at own risk, can be very unsecure but very powerful). Saved to `/config/secrets/homeassistant.token` for use by scripts/skills |
| `http_proxy` | string | _(empty)_ | Optional outbound proxy URL for HTTP/HTTPS requests from OpenClaw and Node tools. Example: `http://192.168.2.1:3128` |

### Router SSH

For skills or scripts that need SSH access to a router, firewall, or other network device:

| Option | Type | Default | Description |
|---|---|---|---|
| `router_ssh_host` | string | _(empty)_ | Hostname or IP of the SSH target |
| `router_ssh_user` | string | _(empty)_ | SSH username |
| `router_ssh_key_path` | string | `/data/keys/router_ssh` | Path to the private key inside the container |

To provide the SSH key: place the private key file in the add-on config directory so it appears at the configured path inside the container. Set permissions: `chmod 600`. (use at own risk, can be very unsecure but very powerful)

### Maintenance

| Option | Type | Default | Description |
|---|---|---|---|
| `clean_session_locks_on_start` | bool | `true` | Remove stale session lock files on startup (safe — only removes locks when gateway isn't running) |
| `clean_session_locks_on_exit` | bool | `true` | Remove session lock files on clean shutdown |
| `auto_configure_mcp` | bool | `false` | Auto-register Home Assistant as an MCP server on startup (requires `homeassistant_token`) |
| `auto_update` | bool | `false` | Check npm for the latest OpenClaw version on add-on startup and install it when newer. Disabled by default; image rebuild updates remain the recommended path. |
---

## 6. Use Case Guides

### 6a. LAN Access Setup

This is the most common setup — accessing the Gateway Web UI from a browser on your local network (including phones and tablets).

> **Since OpenClaw v2026.2.21**, the Control UI requires a secure context (HTTPS or localhost). Use the `access_mode` option for easy setup.

#### Option 1 — Built-in HTTPS proxy (recommended)

1. Go to **Settings → Add-ons → OpenClaw Assistant → Configuration**
2. Set `access_mode`: **lan_https**
3. Restart the add-on
4. Click the **Open Gateway Web UI** button — it uses HTTPS automatically

**Phone/tablet (one-time):** Click **Download CA Certificate** on the landing page, then install it on your device for trusted access without browser warnings.

#### Option 2 — External reverse proxy

1. Go to **Settings → Add-ons → OpenClaw Assistant → Configuration**
2. Set these options:

| Option | Value |
|---|---|
| `access_mode` | **lan_reverse_proxy** |
| `gateway_trusted_proxies` | **127.0.0.1,192.168.88.0/24** |
| `gateway_public_url` | `https://<your-domain>` |

3. Configure your reverse proxy to forward HTTPS to `<HA-IP>:18789`
4. Restart the add-on

**Security note**: Always use HTTPS for Control UI access. The `lan_https` mode handles this automatically; for reverse proxy setups, ensure your proxy terminates TLS.

### 6b. Remote Gateway Mode

If you have an OpenClaw gateway running on a different machine (e.g., a more powerful server), you can configure this add-on to connect to it instead of running its own.

1. Set `gateway_mode`: **remote**
2. Set `gateway_remote_url` in add-on configuration (example: `wss://gateway.example.com:443`)
3. Restart the add-on

When `gateway_mode` is `remote`:
- The add-on does **not** start a local gateway process
- The add-on writes `gateway.remote.url` from `gateway_remote_url` on startup
- `gateway_bind_mode` and `gateway_port` are ignored
- The terminal and landing page still work normally
- You still need the remote gateway's auth token

### 6c. Assist Pipeline Integration (OpenAI API)

OpenClaw's Gateway exposes an **OpenAI-compatible Chat Completions endpoint** (`POST /v1/chat/completions`). This lets you use OpenClaw as a **conversation agent** in Home Assistant's Assist pipeline — enabling voice control, automations, and smart home commands.

There are two ways to connect it to Home Assistant:

---

#### Option 1 — OpenClaw Integration (recommended)

The **native OpenClaw integration** provides auto-discovery, a Lovelace chat card, voice mode, tool invocation services, and status sensors — all in one package.

**Step 1 — Enable the endpoint**

In the add-on configuration, set `enable_openai_api`: **true**, then restart.

Or via terminal:
```sh
openclaw config set gateway.http.endpoints.chatCompletions.enabled true
```

**Step 2 — Install the OpenClaw integration**

Via HACS:
1. In HACS, add as a custom repository:
   - Repository: `https://github.com/techartdev/OpenClawHomeAssistantIntegration`
   - Category: **Integration**
2. Install and restart Home Assistant

Or manually: copy `custom_components/openclaw` from the repo into your HA config directory.

**Step 3 — Add the integration**

1. Go to **Settings → Devices & Services → Add Integration**
2. Search for **OpenClaw**
3. If the addon is running locally, it will be **auto-discovered** — just click Submit
4. If connecting to a remote instance, fill in host, port, token, and SSL settings manually

> **`lan_https` mode**: The integration auto-detects this and connects to the internal gateway port on loopback — no certificate setup needed for local addons.

**Step 4 — Set as conversation agent**

1. Go to **Settings → Voice Assistants**
2. Edit your assistant (or create a new one)
3. Under **Conversation agent**, select **OpenClaw**

**Step 5 — Expose entities**

Go to **Settings → Voice Assistants → Expose** and toggle on the entities you want OpenClaw to control.

**Step 6 — Add the chat card (optional)**

The integration auto-registers a Lovelace card. Add it to any dashboard:
```yaml
type: custom:openclaw-chat-card
```

The card includes message history, typing indicator, voice input, wake-word support, and TTS responses.

> **Works with standalone OpenClaw too.** The integration doesn't require the HA addon — it connects to any reachable OpenClaw gateway over HTTP/HTTPS. See the [integration README](https://github.com/techartdev/OpenClawHomeAssistantIntegration) for remote connection details.

---

#### Option 2 — Extended OpenAI Conversation (alternative)

If you prefer to use the [Extended OpenAI Conversation](https://github.com/jekalmin/extended_openai_conversation) integration instead:

**Prerequisites:**
- [HACS](https://hacs.xyz/) installed on your Home Assistant

**Step 1 — Enable the endpoint**

In the add-on configuration, set `enable_openai_api`: **true**, then restart.

Or via terminal:
```sh
openclaw config set gateway.http.endpoints.chatCompletions.enabled true
```

**Step 2 — Install Extended OpenAI Conversation**

1. In HACS, add as a custom repository:
   - Repository: `https://github.com/jekalmin/extended_openai_conversation`
   - Category: **Integration**
2. Install and restart Home Assistant

**Step 3 — Configure the integration**

1. Go to **Settings → Devices & Services → Add Integration**
2. Search for **Extended OpenAI Conversation**
3. Configure:
   - **API Key**: your gateway token — run `jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json` in the terminal
   - **Base URL**: `http://127.0.0.1:18789/v1`
   - **API Version**: leave empty
   - **Organization**: leave empty
   - **Skip Authentication**: **true**

> If using `gateway_bind_mode: lan`, you can also use `http://<your-ha-ip>:18789/v1` — this allows other HA instances on your network to connect too.

**Step 4 — Set as conversation agent**

1. Go to **Settings → Voice Assistants**
2. Edit your assistant (or create a new one)
3. Under **Conversation agent**, select **Extended OpenAI Conversation**

**Step 5 — Expose entities**

Go to **Settings → Voice Assistants → Expose** and toggle on the entities you want OpenClaw to control.

You can now use Assist (voice or text) and OpenClaw will handle conversations, control devices, answer questions, and create automations.

### 6d. Browser Automation (Chromium)

The add-on includes **Chromium** for browser-based automation tasks. OpenClaw can use it for web scraping, form filling, website testing, and other browser automation skills.

### 6d-mcp. MCP Integration (Home Assistant Control)

The **Model Context Protocol (MCP)** lets OpenClaw communicate directly with Home Assistant — reading entity states, calling services, creating automations, and more. This is the recommended way to give OpenClaw full control over your smart home.

#### Automatic setup (recommended)

1. Create a **long-lived access token** in Home Assistant:
   - Go to your HA profile page (click your user avatar at the bottom of the sidebar)
   - Scroll to **Long-Lived Access Tokens** → **Create Token**
   - Give it a name (e.g. "OpenClaw") and copy the token
2. Paste the token into the add-on option **Home Assistant Token** (`homeassistant_token`) in **Settings → Add-ons → OpenClaw Assistant → Configuration**
3. Set **Auto-Configure MCP for Home Assistant** (`auto_configure_mcp`) to **ON**
4. Restart the add-on

The add-on will automatically register Home Assistant as an MCP server named `HA` using `mcporter`. It auto-detects the HA API URL (supervisor proxy when available, otherwise `localhost:8123`). Check the logs for:
```
INFO: MCP server 'HA' registered — OpenClaw can now control Home Assistant
```

On subsequent restarts, the configuration is skipped if the token hasn’t changed.

#### Manual setup

If you prefer to configure MCP manually (or `auto_configure_mcp` is off), run this in the add-on terminal:

```sh
mcporter config add HA "http://localhost:8123/api/mcp" \
  --header "Authorization=Bearer YOUR_LONG_LIVED_TOKEN" \
  --scope home
```

Replace `YOUR_LONG_LIVED_TOKEN` with your HA long-lived access token.

#### Verifying MCP works

After setup, ask OpenClaw something like:
- _"Turn off the living room lights"_
- _"What’s the temperature of the bedroom sensor?"_
- _"List all entities in the kitchen"_

If OpenClaw can execute HA actions, MCP is working.

#### Refreshing HA context after upgrades

If OpenClaw has stale or missing Home Assistant data after an upgrade, run:

```sh
mcporter call home-assistant.GetLiveContext
```

This refreshes the entity/service metadata that OpenClaw uses.

#### Model requirements

MCP setup requires an AI model that understands tool/skill invocation. Budget models (e.g. Gemini 2.5 Flash) may struggle with the initial MCP discovery. For the **first-time setup**, use a capable model (e.g. Gemini 3.1 Pro, Claude Sonnet 4, GPT-4.1). After MCP is configured, you can switch back to a cheaper model for daily use.

#### Troubleshooting MCP

| Symptom | Fix |
|---|---|
| `mcporter: command not found` | Run `openclaw onboard` first, then restart the add-on |
| MCP add fails with auth error | Verify your long-lived token is valid and not expired |
| OpenClaw doesn’t see HA entities | Run `mcporter call home-assistant.GetLiveContext` to refresh |
| Model says “what’s MCP?” | Switch to a more capable model for the initial session (see above) |

To enable it, add to `/config/.openclaw/openclaw.json`:

```json
{
  "browser": {
    "enabled": true,
    "headless": true,
    "noSandbox": true
  }
}
```

> **Note**: `noSandbox` is required inside Docker containers due to security namespace restrictions.

### 6e. Router / Network Device SSH

If you have skills or scripts that need SSH access to a router, firewall, or other network device:

1. Generate an SSH key pair (if you don't have one):
   ```sh
   ssh-keygen -t ed25519 -f /config/keys/router_ssh -N ""
   ```
2. Copy the public key to your router:
   ```sh
   cat /config/keys/router_ssh.pub
   ```
   Add it to the router's authorized keys.
3. Configure the add-on options:
   - `router_ssh_host`: your router's IP (e.g., `192.168.1.1`)
   - `router_ssh_user`: SSH username (e.g., `admin`)
   - `router_ssh_key_path`: `/config/keys/router_ssh` (or wherever you saved it)
4. Test from the terminal:
   ```sh
   ssh -i /config/keys/router_ssh admin@192.168.1.1
   ```

The connection details are also saved to `/config/CONNECTION_NOTES.txt` for reference by scripts.

### 6f. Google Sheets / Google APIs (gog OAuth)

Some OpenClaw skills use [gog](https://github.com/deftdawg/gog) to interact with Google APIs (Sheets, Drive, etc.). Because the add-on runs inside a container, the standard browser-based OAuth flow won't work — the localhost redirect can't reach your PC. Use the **manual** flow instead.

#### Step 1 — Prepare OAuth credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services → Credentials**
2. Create an **OAuth 2.0 Client ID** (type: **Web application**) or use an existing one
3. In the client's **Authorized redirect URIs**, add: `http://localhost:1`
4. Download the client JSON file and copy it into the add-on:
   ```sh
   # From your PC, copy the file to the HA config directory
   # Then in the add-on terminal:
   mkdir -p /config/secrets
   # Place the downloaded JSON as:
   /config/secrets/gmail_oauth_client.json
   ```

#### Step 2 — Register credentials with gog

```sh
gog auth credentials /config/secrets/gmail_oauth_client.json
```

This tells gog where to find your OAuth client configuration.

#### Step 3 — Authorize with `--manual`

```sh
gog auth add your-email@gmail.com --services sheets --manual
```

The `--manual` flag avoids the localhost redirect problem. gog will:

1. Print an authorization URL — **open it in your PC's browser**
2. Sign in with your Google account and grant access
3. You'll be redirected to a URL starting with `http://localhost:1?...` — the page will fail to load, **that's expected**
4. **Copy the full URL** from your browser's address bar
5. Paste it back into the add-on terminal when prompted
6. If prompted for a **passphrase**, enter one to encrypt the stored token (remember it — you'll need it if gog asks again)

#### Step 4 — Verify

```sh
gog auth list
```

You should see your account listed with the `sheets` service.

> **Why `--manual`?** The default OAuth flow starts a temporary HTTP server on localhost to receive the callback. Since the add-on runs on your HA device (not your PC), the browser redirect to `localhost` can't reach the add-on's server. The `--manual` flag skips the local server and lets you paste the redirect URL directly.

> **Persistence**: gog stores credentials under `/config/gogcli/` which is persistent storage — your auth survives add-on updates.

---

## 7. Data Persistence & Skills

### What persists across add-on updates

| Data | Location | Persists? |
|---|---|---|
| OpenClaw config | `/config/.openclaw/openclaw.json` | Yes |
| Built-in skills | `/config/.openclaw/skills/` | Yes |
| Agent sessions & data | `/config/.openclaw/agents/` | Yes |
| ClawHub workspace | `/config/clawd/` | Yes |
| User-installed npm skills | `/config/.node_global/` | Yes |
| SSH keys | `/config/keys/` | Yes |
| Tokens | `/config/secrets/` | Yes |
| Homebrew & brew-installed tools | `/config/.linuxbrew/` | Yes (synced on startup) |
| gog OAuth credentials | `/config/gogcli/` | Yes |
| TLS certificates (lan_https) | `/config/certs/` | Yes (CA persists; server cert regenerated if IP changes) |
| OpenClaw binary | `/usr/lib/node_modules/openclaw/` | **No** — reinstalled from image |

### How built-in skills work

OpenClaw ships with premade skills (e.g., web search, file management). On each startup, the add-on:

1. Copies built-in skills from the image to `/config/.openclaw/skills/`
2. Creates a symlink from the image path back to persistent storage
3. On subsequent boots, only newer files are synced (existing files are preserved)

This means built-in skills survive image rebuilds, and any customizations you make to skill files are preserved.

### How user-installed skills work

When you install a skill via the OpenClaw dashboard or `npm install -g`, the add-on redirects global npm installs to `/config/.node_global/`. This directory persists across updates.

The add-on also configures `pnpm` global directory to persistent storage at `/config/.node_global/pnpm/`.

### Homebrew-installed tools

Homebrew (Linuxbrew) and all brew-installed CLI tools (e.g., `gemini`, `aider`, `gh`, `bw`) are now **persisted** across add-on updates. On each startup, the add-on:

1. Syncs the image's Homebrew install to `/config/.linuxbrew/`
2. Creates a symlink from `/home/linuxbrew/.linuxbrew/` to the persistent copy
3. On subsequent boots, only newer files are synced (user-installed packages are preserved)

This means `brew install` packages survive image rebuilds.

---

## 8. Bundled Tools

The add-on image includes these tools, available in the terminal:

| Tool | Command | Notes |
|---|---|---|
| Git | `git` | Version control |
| Vim | `vim` | Text editor |
| Nano | `nano` | Text editor (beginner-friendly) |
| bat | `bat` (alias for `batcat`) | Syntax-highlighted `cat` |
| fd | `fd` (alias for `fdfind`) | Fast file finder |
| ripgrep | `rg` | Fast text search |
| curl | `curl` | HTTP client |
| jq | `jq` | JSON processor |
| Python 3 | `python3` | Scripting |
| Node.js 22 | `node` | JavaScript runtime |
| npm | `npm` | Node package manager |
| pnpm | `pnpm` | Fast Node package manager |
| Homebrew | `brew` | Package manager (optional — may not be available on all CPUs) |
| Chromium | `chromium` | Headless browser for automation |
| SSH | `ssh` | Remote access |
| oc-cleanup | `oc-cleanup` | Interactive disk space monitor & cache cleanup helper |

### oc-cleanup

Run `oc-cleanup` from the add-on terminal to see an overview of disk usage and
selectively clear caches that accumulate over time:

```
$ oc-cleanup
```

The tool displays:

- **Disk usage** — total, used, available, and percentage for the overlay filesystem.
- **Cache sizes** — npm global cache, pnpm content store, OpenClaw data, Homebrew cellar, workspace, Python `__pycache__`, and `/tmp`.
- **Cleanup menu** — choose which caches to purge (npm, pnpm, pycache, tmp, all at once).

> **Note:** The add-on cannot prune Docker images directly. If disk space is
> critically low due to old Docker layers, SSH into the host and run
> `docker image prune -a` or `docker system prune`.

---

## 9. Updating & Backup

### Updating the add-on

Home Assistant checks for add-on updates automatically. When an update is available:

1. Go to **Settings → Add-ons → OpenClaw Assistant**
2. Click **Update**
3. The add-on will rebuild with the new image

**What happens during an update**:
- The container is destroyed and recreated from the new image
- Everything under `/config/` is preserved (config, skills, workspace, keys)
- Homebrew and brew-installed packages are preserved (synced to `/config/.linuxbrew/`)
- The OpenClaw binary is updated to the version in the new image

Optional: set `auto_update` to `true` to let the add-on check npm on startup and install a newer OpenClaw package when available. Leave it `false` for deterministic image-based updates.

### Checking your version

The add-on version is shown on the add-on page in Home Assistant. To check the OpenClaw version:

```sh
openclaw --version
```

### Backup

Home Assistant's built-in backup system automatically includes add-on configuration data (`/config/`). This covers all persistent data: OpenClaw config, skills, workspace, keys, and tokens.

**To create a backup**: Go to **Settings → System → Backups → Create Backup**

**Manual backup** (from the terminal):
```sh
# Key paths to back up:
# /config/.openclaw/     - OpenClaw config, skills, agent data
# /config/clawd/         - ClawHub workspace
# /config/.node_global/  - User-installed npm skills
# /config/keys/          - SSH keys
# /config/secrets/       - Tokens
```

### Factory reset

To reset the add-on to a clean state, remove the persistent data:

```sh
rm -rf /config/.openclaw /config/clawd /config/.node_global
```

Then restart the add-on. It will re-bootstrap a fresh configuration.

> **Warning**: This deletes all your OpenClaw configuration, skills, and workspace data. Back up first if needed.

---

## 10. Troubleshooting

### How to read add-on logs

Go to **Settings → Add-ons → OpenClaw Assistant → Log** tab. Logs show startup messages, errors, and service status.

### Port 48099 conflict (add-on page won't load)

**Symptom**: `bind() to 0.0.0.0:48099 failed (98: Address already in use)` in logs.

**Cause**: A stale nginx process from a previous run is still holding the port. This can happen after a crash or unclean restart.

**Fix**: Restart the add-on. The startup script automatically cleans up stale processes. If the problem persists, stop the add-on, wait 10 seconds, then start it again.

### Port 7681 conflict (terminal won't load)

**Symptom**: `lws_socket_bind: ERROR on binding fd to port 7681` in logs.

**Fix**: Either restart the add-on (stale process cleanup), or change `terminal_port` to a different value (e.g., `7682`).

### ERR_CONNECTION_REFUSED

**Symptom**: Browser shows connection refused when opening the Gateway Web UI.

**Checks**:
1. Is the gateway running? In the terminal: `openclaw gateway status`
2. Is the bind mode correct? `openclaw config get gateway.bind` — must be `lan` for direct LAN access, or `loopback` if using `lan_https` mode
3. Is the port correct? `openclaw config get gateway.port`
4. Is the firewall blocking the port? Check your HA host firewall rules

### "disconnected (1008): control ui requires device identity" / "requires HTTPS or localhost"

**Symptom**: Gateway UI shows error 1008 or "requires secure context / device identity".

**Cause**: OpenClaw v2026.2.21+ requires HTTPS or localhost. Plain HTTP over LAN is blocked. (v2026.2.22 further hardens this by defaulting remote onboarding to `wss://` and rejecting insecure non-loopback targets.)

**Fix** (pick one):
1. **Easiest**: Set `access_mode` to **lan_https** in add-on Configuration → restart. This adds a built-in HTTPS proxy with zero external setup.
2. **External proxy**: Set `access_mode` to **lan_reverse_proxy** and configure NPM/Caddy/Traefik with TLS.
3. **SSH tunnel** (desktop only): `ssh -L 18789:127.0.0.1:18789 user@ha-ip` then open `http://localhost:18789`.

### "disconnected (1008): origin not allowed"

**Symptom**: Gateway UI shows `origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)`.

**Cause**: OpenClaw v2026.2.21+ checks the browser's `Origin` header against an allow-list. When using the built-in HTTPS proxy (`lan_https`), the origin (`https://<ip>:<port>`) must be registered in `gateway.controlUi.allowedOrigins`.

**Fix**: In **v0.5.50+** defaults are configured automatically on startup. In **v0.5.54+**, the add-on now merges defaults with existing values and user extras.
1. Restart the add-on (the startup script detects LAN IP and updates origins).
2. If needed, set `gateway_additional_allowed_origins` in add-on configuration (comma-separated), then restart.
3. If the IP has changed since you last started, restart again — the cert and defaults are refreshed.
4. **Manual override** (advanced, from the add-on terminal):
   ```sh
   openclaw config set gateway.controlUi.allowedOrigins '["https://192.168.1.10:18789"]'
   ```
   Then restart the add-on to re-merge defaults + extras.

### "disconnected (1008): pairing required"

**Symptom**: Gateway UI loads over HTTPS but shows `pairing required` and the status is Offline.

**Cause**: OpenClaw v2026.2.21+ requires new devices to complete a pairing handshake before the Control UI WebSocket is accepted. Loopback connections are auto-approved (v2026.2.22 further improves this with loopback scope-upgrade auto-approval), but LAN connections (including those through the HTTPS proxy) require explicit approval.

**Fix**: In **v0.5.50+** the add-on configures `gateway.controlUi.dangerouslyDisableDeviceAuth` in `lan_https` mode. By default it is enabled (`controlui_disable_device_auth: true`) to bypass per-device pairing while still enforcing token auth. If you prefer stricter behavior, set `controlui_disable_device_auth: false` and approve new devices manually.

> **v2026.2.22 note:** The gateway now logs a security warning on startup when this flag is active. The warning is expected and harmless — run `openclaw security audit` for details.

1. **Restart the add-on** — the startup script writes the config before launching the gateway.
2. If the error persists, set it manually:
   ```sh
   nano /config/.openclaw/openclaw.json
   ```
   Ensure `gateway.controlUi` contains:
   ```json
   "controlUi": {
     "dangerouslyDisableDeviceAuth": true,
     "allowedOrigins": ["https://YOUR_IP:18789"]
   }
   ```
   Then restart the gateway: `openclaw gateway restart`
3. Alternatively, approve devices individually without disabling auth:
   ```sh
   openclaw devices list       # show pending pairing requests
   openclaw devices approve <requestId>
   ```

### Gateway UI shows "Unauthorized"

**Fix**: Get the correct token and use it:

```sh
jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json
```

> **Note**: Since OpenClaw v2026.2.22+ `openclaw config get` redacts sensitive values (returns `openclaw_redacted`). Use `jq` to read the token directly from the config file.

Paste this token when the UI prompts for authentication, or append it to the URL: `http://<ip>:18789/?token=<your-token>`

### CLI shows unauthorized with `trusted_proxy_user_missing`

**Symptom**: In add-on terminal, commands that open direct gateway WebSocket (for example some `openclaw status`/gateway probes) fail with unauthorized and logs mention `trusted_proxy_user_missing`.

**Cause**: `gateway_auth_mode: trusted-proxy` expects identity headers from your reverse proxy. Direct local CLI connections are not proxied, so they may be rejected.

**What to do**:
- Keep `trusted-proxy` for browser traffic via your reverse proxy.
- For local terminal workflows that require direct gateway auth, temporarily switch to `gateway_auth_mode: token` (or run via proxy path that injects trusted headers), then switch back if needed.

### Terminal not visible

1. Check that `enable_terminal` is **true** in the add-on configuration
2. Check logs for `Starting web terminal (ttyd)` — if missing, the terminal is disabled
3. If you see a port conflict error, change `terminal_port` to a different value

### `web_fetch failed: fetch failed` / HTTP tool calls time out

**Symptom**: OpenClaw's `web_fetch` tool (or any outbound HTTP call from a skill) fails with `fetch failed`.

**Cause**: Node 22 uses `autoSelectFamily` which tries IPv6 first. Most HAOS VMs have IPv6 DNS resolution but no IPv6 egress, so connections time out before falling back to IPv4.

**Fix**: Ensure `force_ipv4_dns` is **true** (default since v0.5.51). If you upgraded from an older version, the option may still be set to `false` — change it to `true` in **Settings → Add-ons → OpenClaw Assistant → Configuration** and restart.

### Telegram network errors (`TypeError: fetch failed` / `getUpdates` fails)

If Telegram is configured but polling fails with network fetch errors:

1. In add-on terminal, test IPv4 vs IPv6 explicitly:
   ```sh
   curl -4 https://api.telegram.org/bot<token>/getMe
   curl -6 https://api.telegram.org/bot<token>/getMe
   ```
2. If IPv4 works but default/IPv6 fails, ensure add-on option `force_ipv4_dns` is `true` (default) and restart.
3. Keep `channels.telegram.network.autoSelectFamily: false` (default on Node 22).
4. If still failing, check host/VM IPv6 routing and DNS configuration.

### Outbound proxy not applied

**Symptom**: External API/network calls still fail in restricted networks even after setting proxy.

**Checks**:
1. Set add-on option `http_proxy` with full URL format: `http://host:port` (example: `http://192.168.2.1:3128`).
2. Restart the add-on after changing configuration.
3. Check logs for `INFO: Outbound HTTP/HTTPS proxy enabled from add-on configuration.`
4. If you see `WARN: Invalid http_proxy value`, fix the URL format and restart.

When proxy is enabled, add-on startup also applies default bypass ranges via `NO_PROXY`/`no_proxy` for localhost and private network ranges.

### Skills disappearing after update

Built-in skills are synced to persistent storage on each startup. If skills are missing:

1. Check logs for `INFO: Synced built-in skills to persistent storage` — this confirms the sync ran
2. If you see `WARN: Built-in skills directory not found`, the OpenClaw installation may be corrupted. Try reinstalling the add-on.
3. User-installed skills (via dashboard) are stored in `/config/.node_global/` and should survive updates

### Homebrew errors / CPU compatibility

**Symptom**: `Homebrew's x86_64 support on Linux requires a CPU with SSSE3 support!`

**Cause**: Your CPU doesn't support SSSE3 instructions (required by Homebrew). Affects older Intel Atom, Celeron, or pre-2006 processors.

**Impact**: Skills that depend on Homebrew-installed CLI tools (e.g., `gemini`, `aider`) won't work. Core OpenClaw functionality is unaffected.

**Workarounds**:
- Use a machine with a newer CPU (Intel Core 2 or newer, ~2006+)
- Install the required CLI tools manually if possible
- Use alternative skills that don't require Homebrew dependencies

### "openclaw: command not found"

The OpenClaw binary should be installed at `/usr/lib/node_modules/openclaw/`. If this error appears:

1. Check the add-on logs for npm installation errors during build
2. Try restarting the add-on
3. If the problem persists, uninstall and reinstall the add-on

### Gateway won't start / config errors

**Symptom**: `ERROR: Failed to apply gateway settings` in logs.

**Fix**: The `openclaw.json` config file may be corrupted. To reset it:

```sh
rm /config/.openclaw/openclaw.json
```

Restart the add-on — it will generate a fresh config. You'll need to run `openclaw onboard` again.

### Disk space running low / "no space left on device"

**Symptom**: Build or startup fails, or the landing page shows a red disk-usage indicator.

**Cause**: Old Docker images and container layers accumulate on the host. Each add-on rebuild (~1–2 GB) keeps the previous image until pruned.

**Fix (from inside the add-on)**:
1. Open the terminal and run `oc-cleanup` to clear npm/pnpm caches, pycache, and temp files.

**Fix (from the host)** — you need a **root shell on the HAOS host**, not the `ha` CLI
(the `ha docker` command does **not** support `prune`):

*Option A — Advanced SSH & Web Terminal add-on (easiest):*
1. Install the **Advanced SSH & Web Terminal** add-on from the HA store.
2. In its Configuration, **disable Protection Mode** (required for host-level access).
3. Open the terminal and run:
   ```sh
   docker image prune -a       # remove all unused images
   docker builder prune -a      # remove build cache
   ```

*Option B — HAOS debug console (VirtualBox / physical):*
1. On the HAOS console (keyboard/VirtualBox window), type `login` to get a root shell.
2. Run the same `docker image prune -a` and `docker builder prune -a` commands.

> **Note:** The `ha docker` CLI (shown by `ha docker --help`) only exposes `info`,
> `options`, and `registries` — it cannot prune images. You must use the raw `docker`
> command from a host root shell.

**Prevention**: If running HAOS in VirtualBox, resize the VDI to at least 64 GB:
```
VBoxManage modifymedium disk haos.vdi --resize 64000
```

---

## 11. FAQ

**Does this work on Raspberry Pi?**
Yes. The add-on supports aarch64 (Raspberry Pi 4/5) and armv7 (Raspberry Pi 3). Note that Homebrew may not work on all ARM devices, but core functionality is unaffected.

**Can I run multiple agents?**
OpenClaw supports multiple agent profiles. Configure them via `openclaw configure` or by editing `/config/.openclaw/openclaw.json`. The gateway serves all configured agents.

**Can I use a remote gateway?**
Yes. Set `gateway_mode` to `remote` and set `gateway_remote_url` in add-on configuration. The add-on syncs it into OpenClaw config automatically. See [Remote Gateway Mode](#6b-remote-gateway-mode).

**How do I change the AI model or provider?**
Run `openclaw configure` in the terminal to reconfigure your AI providers, or edit `/config/.openclaw/openclaw.json` directly. You can use OpenAI, Google (Gemini), Anthropic (Claude), local models, and more.

**Can other devices on my network use the OpenClaw API?**
Yes. Set `access_mode` to `lan_https` (recommended) or `lan_reverse_proxy`. Any device on your network can connect to `https://<ha-ip>:18789`. Use the gateway token for authentication. This also enables the [Assist pipeline integration](#6c-assist-pipeline-integration-openai-api) from other HA instances or standalone OpenClaw integrations.

**Where is my data stored on the host?**
The add-on's `/config/` directory maps to `/addon_configs/<slug>/` on the Home Assistant host. This is included in HA backups automatically.

The add-on also mounts Home Assistant `/share` and `/media` as writable paths inside the container (`/share`, `/media`) for file access workflows. These are separate from OpenClaw's default persistent workspace under `/config`.
