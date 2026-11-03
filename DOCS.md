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
| **nginx** (Ingress proxy) | 48099 (fixed, Ingress-only) | Serves the landing page inside Home Assistant; direct LAN access is denied |
| **ttyd** (Web terminal) | 7681 (configurable) | Provides a browser-based terminal for setup and management |

When you open the add-on page in Home Assistant, nginx serves a landing page with:
- An **Open Gateway Web UI** button (opens in a new tab — see [why](#4-accessing-the-gateway-web-ui))
- An embedded **terminal** for running commands

### Key directories

| Path | Persistent? | Contents |
|---|---|---|
| `/config/` | Yes | All user data — survives add-on updates and rebuilds |
| `/config/.openclaw/` | Yes | OpenClaw configuration (`openclaw.json`), skills, agent data |
| `/config/clawd/` | Yes | Agent workspace (ClawHub-installed skills, files) |
| `/config/.node_global/` | Optional | User-installed npm packages when `persist_node_global=true` |
| `/config/secrets/` | Yes | Tokens (e.g., `homeassistant.token`) |
| `/config/keys/` | Yes | SSH keys (e.g., router SSH key) |
| `/config/.linuxbrew/` | Optional | Homebrew install and brew-installed CLI tools when `persist_brew_tools=true` |
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
   oc-gateway status
   ```
   > In this add-on, the gateway is supervised by `run.sh` (not systemd), so `openclaw gateway status` can show misleading service-manager warnings.
2. Click the **Open Gateway Web UI** button on the landing page
3. If prompted for a token, paste the one from Step 2 or go to the Overview tab, paste the token in the 'Gateway Token' field and press Connect.

---

## 4. Accessing the Gateway Web UI

The Gateway Web UI (Control UI) is OpenClaw's main web interface. It opens in a **separate browser tab**, not inside the add-on page.

The reason is asset paths, not WebSockets — Ingress proxies WebSockets fine, which is how the embedded terminal works. Home Assistant serves add-on pages under a per-add-on prefix (`/api/hassio_ingress/<token>/`), while the Control UI emits its assets from the origin root unless `gateway.controlUi.basePath` matches that prefix exactly. Serving it under Ingress would therefore require pinning the gateway to that prefix, which would break direct LAN access at the same time.

> **Updated for OpenClaw 2026.8.2:** the Control UI **no longer requires a secure context**. Device identity is generated and signed with pure-JS Ed25519, so pairing works on any origin, including plain HTTP. HTTPS is still strongly recommended — over plaintext, both the page and your gateway token are readable by anyone on the path — but it is no longer a hard requirement.
>
> **Every browser must be paired once** before it can use the Control UI. See [Device pairing](#device-pairing-first-connection) below. `gateway.controlUi.dangerouslyDisableDeviceAuth` used to bypass this; upstream has **retired that flag and it is now inert**, so pairing applies to all browsers.

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

Then open `http://localhost:18789` in your browser.

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

### Device pairing (first connection)

The first time a browser opens the Gateway Web UI it shows **Device pairing required** with a request ID. This is normal and happens once per browser.

The "Gateway host" the message refers to is **the add-on container itself**, and the add-on's web terminal is a root shell on it — no SSH required.

1. Open the add-on page in Home Assistant and use the embedded terminal (or **Open Terminal (full page)**).
2. List the pending request:
   ```sh
   openclaw devices list
   ```
   ```
   Pending (1)
   Request                               Device                    Requested            Age
   5dd686b0-2a01-4f3e-b532-873914bfe829  1a6ad91d... 192.168.1.106 roles: operator; ... 2m ago
   ```
3. Approve it, using the ID shown in the browser (or in the table above):
   ```sh
   openclaw devices approve 5dd686b0-2a01-4f3e-b532-873914bfe829
   ```
4. Click **Connect** again in the browser.

**Useful variations**

```sh
openclaw devices approve --latest   # preview the newest request (exits 1), then rerun with the exact ID
openclaw devices list --json        # machine-readable
openclaw devices rename --device <id> --name "Living room tablet"
openclaw devices reject <requestId> # deny a request you do not recognise
openclaw devices remove <deviceId>  # un-pair a device later
```

> **Ignore the `ssh -N -L ...` hint.** Running `openclaw dashboard` in the add-on prints "No GUI detected" and suggests an SSH tunnel — that guidance is for headless servers. In this add-on you already have a shell on the gateway host, so `openclaw devices list` / `approve` is all you need.

> **Security note:** approve only requests you just triggered yourself. The table shows the requesting IP — check it matches the device you are pairing.

### Unauthorized error

If the Gateway UI shows **Unauthorized**, re-check your token:

```sh
jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json
```

> **Note**: `openclaw config get` redacts sensitive values (v2026.2.22+) — read the token from the config file with `jq`.

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
| `controlui_disable_device_auth` | bool | `true` | **Deprecated / no effect.** It set `gateway.controlUi.dangerouslyDisableDeviceAuth`, which OpenClaw retired in the `2026.8.x` line — the key is now inert and `openclaw doctor --fix` removes it. Every browser pairs once instead; see [Device pairing](#device-pairing-first-connection). The option is kept so existing configurations keep validating, and the add-on no longer writes the key. |
| `force_ipv4_dns` | bool | `true` | Force IPv4-first DNS ordering for Node network calls. **Recommended ON** — most HAOS VMs lack IPv6 egress, causing `web_fetch` and Telegram timeouts. Set to `false` only if your network has working IPv6. |
| `gateway_env_vars` | list of `{name, value}` | `[]` | Environment variables exported to the gateway process at startup. UI format: list entries with `name` and `value` (example: `name=OPENAI_API_KEY`, `value=sk-...`). Limits: max 50 vars, key length 255, value length 10000. Reserved runtime keys are blocked (for example `PATH`, `HOME`, `NODE_OPTIONS`, `NODE_PATH`, `OPENCLAW_*`, proxy vars). Legacy string/object formats are still accepted for backward compatibility. |
| `nginx_log_level` | `full` / `minimal` | `minimal` | Nginx access log verbosity. `minimal` suppresses repetitive Home Assistant health-check and polling requests (`GET /`, `GET /v1/models`). `full` logs everything. |

When `gateway_auth_mode: trusted-proxy` is used, the add-on sets `gateway.auth.trustedProxy.userHeader` to `x-forwarded-user` by default.

### Terminal

| Option | Type | Default | Description |
|---|---|---|---|
| `enable_terminal` | bool | `true` | Show the web terminal on the add-on page |
| `terminal_port` | int | `7681` | Port for the terminal (ttyd). Change if 7681 conflicts. Range: 1024-65535 |

The terminal remains available inside the authenticated Home Assistant Ingress
page. Port `48099` is intentionally not a direct LAN endpoint: opening
`http://<ha-host>:48099/` outside Home Assistant returns `403`. This prevents
bypassing Home Assistant authentication for the landing page and writable ttyd
shell. The internal ttyd listener remains bound to loopback only.

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
| `persist_node_global` | bool | `false` | Persist user-installed npm global skills/packages in `/config/.node_global/`. Turn on only if you want those installs to survive add-on rebuilds. |
| `persist_brew_tools` | bool | `false` | Persist Homebrew and brew-installed CLI tools in `/config/.linuxbrew/`. Turn on only if you want those installs to survive add-on rebuilds. |
| `auto_configure_mcp` | bool | `false` | Auto-register Home Assistant as an MCP server on startup (requires `homeassistant_token`) |
| `config_backup_keep` | int | `10` | How many `openclaw.json` snapshots to keep in `/config/.openclaw/backups`. See [Config snapshots & rollback](#7a-config-snapshots--rollback). `0` disables snapshots. Range: 0-100 |

### Performance

| Option | Type | Default | Description |
|---|---|---|---|
| `resource_profile` | `auto` / `low` / `balanced` / `high` | `auto` | Caps the Node.js heap used by the gateway so it cannot grow until the OOM killer intervenes. See [Resource profiles](#8a-resource-profiles) |

### Home Assistant Integration

| Option | Type | Default | Description |
|---|---|---|---|
| `ha_health_sensors` | bool | `false` | Publish `sensor.openclaw_*` health entities to Home Assistant. Requires `homeassistant_token`. See [Health sensors](#6g-home-assistant-health-sensors) |
| `ha_health_interval` | int | `60` | Seconds between health sensor updates. Range: 15-3600 |
| `ha_base_url` | string | _(empty)_ | Base URL of Home Assistant for the health sensors. Empty auto-detects (tries `https` and `http` on `127.0.0.1`, `localhost`, `homeassistant`, `homeassistant.local`, port 8123). Set it if Home Assistant uses a non-default port or host, e.g. `https://192.168.1.10:8123` |

---

## 6. Use Case Guides

### 6a. LAN Access Setup

This is the most common setup — accessing the Gateway Web UI from a browser on your local network (including phones and tablets).

> HTTPS is not strictly required by OpenClaw any more, but it is strongly recommended on a LAN: over plain HTTP your gateway token travels in the clear. The `access_mode` option sets it up for you.

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

The add-on bundles `mcporter` and automatically registers Home Assistant as an MCP server named `HA`. It auto-detects the HA API URL (supervisor proxy when available, otherwise `localhost:8123`). Check the logs for:
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
| `mcporter: command not found` | Upgrade to add-on `0.5.84` or newer. Older builds did not bundle `mcporter`; as a temporary workaround, install it manually in the add-on terminal and restart. |
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

### 6g. Home Assistant Health Sensors

The add-on can publish its own health as Home Assistant entities, so you can alert on problems instead of discovering them in the add-on log.

**Setup**

1. Create a long-lived access token: click your user profile in Home Assistant → **Security** tab → **Create Token**
2. Paste it into the add-on's `homeassistant_token` option
3. Set `ha_health_sensors`: **true** (optionally adjust `ha_health_interval`, default 60 s)
4. Restart the add-on

**Entities published**

| Entity | State | Attributes |
|---|---|---|
| `sensor.openclaw_gateway` | `running` / `stopped` | pid, bind_mode, access_mode, port, resource_profile |
| `sensor.openclaw_version` | OpenClaw runtime version | addon_version |
| `sensor.openclaw_gateway_memory` | Gateway RSS in MB | heap_limit_mb, resource_profile |
| `sensor.openclaw_disk_used` | `/config` usage in % | total, used, available |
| `sensor.openclaw_certificate_expiry` | Days until the TLS cert expires | — (only in `lan_https` mode) |

**Example automation**

```yaml
automation:
  - alias: OpenClaw gateway down
    trigger:
      - platform: state
        entity_id: sensor.openclaw_gateway
        to: "stopped"
        for: "00:05:00"
    action:
      - service: notify.persistent_notification
        data:
          message: "OpenClaw gateway has been down for 5 minutes."
```

**Notes**

- These entities are created through the REST API, so they are **not** backed by an integration. After a Home Assistant restart they reappear at the next update interval (up to `ha_health_interval` seconds).
- Preview the values without publishing anything — no token required:
  ```sh
  oc-health show
  ```
- Publish a single round manually:
  ```sh
  oc-health once
  ```
- Cost is one `curl` per interval; there is no resident process.

---

## 7. Data Persistence & Skills

### What persists across add-on updates

| Data | Location | Persists? |
|---|---|---|
| OpenClaw config | `/config/.openclaw/openclaw.json` | Yes |
| Built-in skills | `/config/.openclaw/skills/` | Yes |
| Agent sessions & data | `/config/.openclaw/agents/` | Yes |
| ClawHub workspace | `/config/clawd/` | Yes |
| User-installed npm skills | `/config/.node_global/` | Optional (`persist_node_global=true`) |
| SSH keys | `/config/keys/` | Yes |
| Tokens | `/config/secrets/` | Yes |
| Homebrew & brew-installed tools | `/config/.linuxbrew/` | Optional (`persist_brew_tools=true`) |
| gog OAuth credentials | `/config/gogcli/` | Yes |
| TLS certificates (lan_https) | `/config/certs/` | Yes (CA persists; server cert regenerated if IP changes) |
| Config snapshots | `/config/.openclaw/backups/` | Yes |
| OpenClaw binary | `/usr/lib/node_modules/openclaw/` | **No** — reinstalled from image |

### 7a. Config Snapshots & Rollback

The add-on rewrites `openclaw.json` on **every start** — gateway bind/port/auth from your add-on options, `controlUi.allowedOrigins`, and repair rules for settings that would stop the gateway from booting.

To make that safe, a snapshot of `openclaw.json` is taken **before the first write of each start**, so any unwanted change can be undone.

- **Location**: `/config/.openclaw/backups/openclaw.<UTC timestamp>.<label>.json`
- **Retention**: the newest `config_backup_keep` snapshots (default 10, `0` disables)
- **Deduplicated**: if the config has not changed since the last snapshot, no new file is written — restarting the add-on repeatedly will not fill the folder

**Commands** (run in the add-on terminal):

```sh
oc-config list             # show snapshots, newest first
oc-config diff             # diff the newest snapshot against the current config
oc-config diff 3           # diff snapshot #3
oc-config restore 3        # restore snapshot #3, then restart the add-on
oc-config snapshot before-experiment   # take a labelled snapshot right now
```

`oc-config restore` always snapshots the config it is about to replace (label `pre-restore`), so a restore is itself reversible.

> **Important**: Settings that the add-on manages from its own options — `gateway.bind`, `gateway.port`, `gateway.auth.mode`, `gateway.trustedProxies`, `gateway.controlUi.allowedOrigins`, `chatCompletions.enabled` — are re-applied on every start and will overwrite the restored values for those specific keys. Change those in the add-on Configuration, not by restoring a snapshot. Everything else (providers, agents, skills, channels, models) restores as-is.

### How built-in skills work

OpenClaw ships with premade skills (e.g., web search, file management). On each startup, the add-on:

1. Copies built-in skills from the image to `/config/.openclaw/skills/`
2. Creates a symlink from the image path back to persistent storage
3. On subsequent boots, only newer files are synced (existing files are preserved)

This means built-in skills survive image rebuilds, and any customizations you make to skill files are preserved.

### How user-installed skills work

By default, user-installed npm skills and global packages are **ephemeral** to keep Home Assistant backups small.

If you enable `persist_node_global`, the add-on redirects global npm installs to `/config/.node_global/` so dashboard-installed skills survive add-on rebuilds. The add-on also configures the pnpm global directory at `/config/.node_global/pnpm/` in that mode.

### Homebrew-installed tools

By default, Homebrew (Linuxbrew) and brew-installed CLI tools are **ephemeral** to keep Home Assistant backups small.

If you enable `persist_brew_tools`, the add-on:

1. Syncs the image's Homebrew install to `/config/.linuxbrew/`
2. Creates a symlink from `/home/linuxbrew/.linuxbrew/` to the persistent copy
3. On subsequent boots, only newer files are synced (user-installed packages are preserved)

This means `brew install` packages survive image rebuilds only when persistence is enabled.

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
| Node.js 24 | `node` | JavaScript runtime |
| npm | `npm` | Node package manager |
| pnpm | `pnpm` | Fast Node package manager |
| Homebrew | `brew` | Package manager (optional — may not be available on all CPUs) |
| Chromium | `chromium` | Headless browser for automation |
| SSH | `ssh` | Remote access |
| oc-cleanup | `oc-cleanup` | Interactive disk space monitor & cache cleanup helper |
| oc-gateway | `oc-gateway status` / `oc-gateway restart` | Add-on-native gateway status/restart helper (`run.sh` supervised, no systemd) |
| oc-config | `oc-config list` / `oc-config restore <n>` | Inspect and roll back `openclaw.json` snapshots |
| oc-health | `oc-health check` / `oc-health show` / `oc-health once` | Diagnose, preview or publish the Home Assistant health sensors |

### 8a. Resource Profiles

Home Assistant runs on everything from a Raspberry Pi 3 to a large NUC, and Node.js sizes its heap against **total host memory**. Left alone, the gateway can grow until the OOM killer takes it — or Home Assistant itself — down.

`resource_profile` gives the gateway an explicit, logged memory budget.

| Profile | Selected when (auto) | Node heap limit |
|---|---|---|
| `low` | armv6/armv7, or under 2 GB RAM | 35% of RAM, clamped to 256-768 MB |
| `balanced` | 2-6 GB RAM | 45% of RAM, clamped to 768-2048 MB |
| `high` | over 6 GB RAM | none — Node's own default applies |

The resolved profile and heap limit are printed at startup and shown on the add-on landing page:

```
INFO: Resource profile: low (auto-detected); host: 1024 MB RAM, 4 CPU, armv7l
INFO: Node heap limit for OpenClaw: 358 MB (--max-old-space-size)
```

**`auto` never modifies `openclaw.json`.** It only sets add-on process limits, so updating the add-on can never silently change how your agents behave.

Selecting **`low` explicitly** additionally applies conservative OpenClaw defaults — currently `browser.enabled: false`, since Chromium is by far the heaviest optional component. This is only written for keys you have **not** already set yourself, and it is never re-applied: set `browser.enabled: true` in `openclaw.json` and it stays true.

**Other things that matter on small hardware**

- **Chromium** (browser automation) — the largest single consumer. Disable with `openclaw config set browser.enabled false`.
- **node-llama-cpp** (local memory/embeddings) — CPU- and RAM-heavy on ARM. Consider a remote embeddings provider instead.
- **`persist_node_global` / `persist_brew_tools`** — leave off unless needed; they add disk and backup weight.

> If the gateway starts hitting the heap ceiling (frequent restarts, `JavaScript heap out of memory` in the log), move up a profile — or reduce the workload. `sensor.openclaw_gateway_memory` (see [Health sensors](#6g-home-assistant-health-sensors)) makes this easy to watch over time.

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
- Homebrew and npm global packages are preserved only if you explicitly enable `persist_brew_tools` / `persist_node_global`
- The OpenClaw binary is updated to the version in the new image

### Checking your version

The add-on version is shown on the add-on page in Home Assistant. To check the OpenClaw version:

```sh
openclaw --version
```

### Backup

Home Assistant's built-in backup system automatically includes add-on configuration data (`/config/`). By default this covers the important user state: OpenClaw config, skills, workspace, keys, and tokens — without large optional toolchains.

### What is excluded from backups (v0.5.90+)

The add-on tells the Supervisor to skip regenerable caches and tooling, so backups stay small no matter how your persistence options are set:

| Excluded | Why it is safe |
|---|---|
| `.linuxbrew/` | Homebrew install and cellar — reinstallable with `brew install` |
| `.node_global/` | npm/pnpm global installs — reinstallable |
| `.npm/` | npm download cache — rebuilt on demand |
| `.cache/` | tool caches (Chromium, build artifacts) — rebuilt on demand |
| `__pycache__/` | Python bytecode — regenerated automatically |
| `*.jsonl.lock` | stale session locks — never useful to restore |

Everything else is backed up: `openclaw.json`, config snapshots, skills, agent sessions, the `clawd` workspace, keys, secrets and TLS certificates.

> **Important**: restoring a backup replaces `/config` wholesale, so excluded directories are **removed** by a restore rather than left in place. After restoring, reinstall any brew or global npm tools you depend on. Caches rebuild themselves.

### Persistence vs. backups

These are two different things, and since v0.5.90 they no longer trade off against each other:

- **Persistence** (`persist_node_global`, `persist_brew_tools`) controls whether tooling survives an **add-on rebuild**. Both default to `false`.
- **Backup exclusion** (above) controls whether it lands in a **Home Assistant backup**. Always on.

So you can safely enable persistence to stop losing `brew`/npm tools on every add-on update, without inflating your backups. The cost is that those tools are not restored from a backup — you reinstall them.

### Migration note for older installs

If you used an older add-on version, you may already have legacy directories such as `/config/.node_global/` or `/config/.linuxbrew/` from previous persistent behavior. Since v0.5.90 these no longer count toward backup size, but they still occupy disk. The add-on warns about them at startup; remove them when you no longer need them:

```sh
rm -rf /config/.node_global /config/.linuxbrew
```

**To create a backup**: Go to **Settings → System → Backups → Create Backup**

**Manual backup** (from the terminal):
```sh
# Key paths to back up:
# /config/.openclaw/     - OpenClaw config, skills, agent data
# /config/clawd/         - ClawHub workspace
# (.node_global / .linuxbrew are intentionally excluded from HA backups —
#  reinstall those tools instead of restoring them)
# /config/keys/          - SSH keys
# /config/secrets/       - Tokens
```

### Factory reset

To reset the add-on to a clean state, remove the persistent data:

```sh
rm -rf /config/.openclaw /config/clawd /config/.node_global /config/.linuxbrew
```

Then restart the add-on. It will re-bootstrap a fresh configuration.

> **Warning**: This deletes all your OpenClaw configuration, skills, workspace data, and any optionally persisted tool installations. Back up first if needed.

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

### Direct access to port 48099 returns `403`

This is expected. Port `48099` is the internal backend for authenticated Home
Assistant Ingress and rejects direct LAN clients. Open the add-on page from the
Home Assistant UI instead; the landing page and terminal continue to work there.

### ERR_CONNECTION_REFUSED

**Symptom**: Browser shows connection refused when opening the Gateway Web UI.

**Checks**:
1. Is the gateway running? In the terminal: `oc-gateway status`
2. Is the bind mode correct? `openclaw config get gateway.bind` — must be `lan` for direct LAN access, or `loopback` if using `lan_https` mode
3. Is the port correct? `openclaw config get gateway.port`
4. Is the firewall blocking the port? Check your HA host firewall rules

### Gateway restart loop: `web_search provider is not available: brave`

**Symptom**: Logs repeat `Invalid config at /config/.openclaw/openclaw.json` and `tools.web.search.provider: web_search provider is not available: brave`.

**Cause**: The persisted OpenClaw config selects the Brave web search provider, but that provider plugin is not currently installed or enabled in the add-on runtime.

**Fix**: In v0.5.72+ the add-on clears that unavailable provider automatically during startup. On older versions, run this in the add-on terminal, then restart:

```sh
jq 'del(.tools.web.search.provider)' /config/.openclaw/openclaw.json > /tmp/openclaw.json && mv /tmp/openclaw.json /config/.openclaw/openclaw.json
```

### "disconnected (1008): control ui requires device identity"

**Symptom**: the Control UI connects, then drops with error 1008 mentioning device identity.

**Cause**: the browser has not been paired yet. Since the `2026.8.x` line every Control UI browser pairs once, on any origin — the old `dangerouslyDisableDeviceAuth` bypass is retired and inert.

**Fix**: approve the browser from the add-on terminal — see [Device pairing](#device-pairing-first-connection):

```sh
openclaw devices list
openclaw devices approve <requestId>
```

> Older versions of this documentation said the Control UI "requires HTTPS or localhost". That restriction was removed upstream: device identity is signed with pure-JS Ed25519 and no longer depends on a secure context. HTTPS remains recommended so your token is not sent in clear text.

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

### "Device pairing required" when opening the Gateway Web UI

**Symptom**: the Gateway Dashboard shows **Device pairing required** with a request ID and will not connect.

**Cause**: expected on a browser's first connection. OpenClaw pairs each Control UI browser once.

**Fix**: in the add-on terminal (the gateway host *is* this container):

```sh
openclaw devices list
openclaw devices approve <requestId>
```

Then click **Connect** again. Full walkthrough: [Device pairing](#device-pairing-first-connection).

> **Do not** try to disable pairing with `gateway.controlUi.dangerouslyDisableDeviceAuth`. OpenClaw retired that flag in the `2026.8.x` line; it is inert, `openclaw doctor --fix` removes it, and the add-on no longer writes it. Approving the device is the supported path.

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

### Ask OpenClaw: `cannot attest NODE_OPTIONS option --require`

Verified Codex inference rejects Node.js code-preloading options such as
`--require`. Earlier add-on images always injected the outbound proxy shim,
even with an empty `http_proxy` option. The shim did nothing without a proxy,
but its presence in `NODE_OPTIONS` still prevented runtime verification.

Starting with add-on `0.5.97`, the add-on only injects that shim when one of
`HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`, or `https_proxy` is non-empty.
Existing Node.js heap/DNS options are preserved; an operator-supplied preload
is not removed. No OpenClaw verification or permission checks are disabled.

If a proxy is actually enabled, the Gateway still uses the shim and Codex's
verified-runtime restriction still applies. OpenClaw supports a scoped
alternative in `/config/.openclaw/openclaw.json`: merge `NODE_OPTIONS` into
`plugins.entries.codex.config.appServer.clearEnv`, preserving any existing
entries and other configuration. For example, the resulting subtree may be:

```json
{
  "plugins": {
    "entries": {
      "codex": {
        "config": {
          "appServer": {
            "clearEnv": ["NODE_OPTIONS"]
          }
        }
      }
    }
  }
}
```

This is a configuration fragment, not a replacement for your complete config.
It prevents only spawned Codex processes and their descendants from inheriting
`NODE_OPTIONS`; the Gateway retains its proxy shim. It also removes any heap,
DNS, or other options carried in that variable from those child processes.
Confirm that Codex and its Node.js tools can access the network without the
shim before adopting this alternative. Generic HTTP(S) proxy environment
variables are not cleared by this setting, but that alone does not guarantee
proxy support for every child tool. The add-on does not set this policy
automatically or change existing Codex settings.

The config file is in persistent `/config/` storage and the add-on's current
startup helper preserves this subtree during normal updates/restarts. In
contrast, edits to `/run.sh` or installed packages inside the container are
replaced by image updates. Restoring an older config or a future incompatible
OpenClaw migration may require reapplying/reviewing the setting. Verify it after
an update and retry the function through your supported configuration-apply
path; do not disable runtime verification to bypass the error.

### Skills disappearing after update

Built-in skills are synced to persistent storage on each startup. If skills are missing:

1. Check logs for `INFO: Synced built-in skills to persistent storage` — this confirms the sync ran
2. If you see `WARN: Built-in skills directory not found`, the OpenClaw installation may be corrupted. Try reinstalling the add-on.
3. User-installed skills (via dashboard) survive updates only when `persist_node_global` is enabled. With the default backup-friendly setting (`false`), they are ephemeral and may need to be reinstalled after an add-on rebuild.

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

**Fix**: First try rolling back to the last known-good config instead of starting over:

```sh
oc-config list
oc-config diff 1        # see what changed
oc-config restore 1     # then restart the add-on
```

If the config is genuinely corrupted beyond repair, reset it:

```sh
rm /config/.openclaw/openclaw.json
```

Restart the add-on — it will generate a fresh config. You'll need to run `openclaw onboard` again.

### A setting I configured keeps getting changed back

**Symptom**: A value in `openclaw.json` reverts every time the add-on restarts.

**Cause**: Settings the add-on manages from its own options are re-applied on every start — `gateway.bind`, `gateway.port`, `gateway.auth.mode`, `gateway.trustedProxies`, `gateway.controlUi.allowedOrigins` and `chatCompletions.enabled`.

**Fix**: Change those in **Settings → Add-ons → OpenClaw Assistant → Configuration**, not in `openclaw.json`. To see exactly what the add-on changed on the last start:

```sh
oc-config diff 1
```

### `proxy_attribution_required` / "Proxy client attribution is required"

**Symptom**: the gateway is running, but every request returns:

```json
{"error":{"message":"Proxy client attribution is required. Configure gateway.trustedProxies narrowly and make the proxy overwrite or safely rebuild forwarded client headers.","type":"proxy_attribution_required"}}
```

**Cause**: OpenClaw `2026.8.2+` rejects requests that carry forwarded identity headers (`X-Forwarded-For`, `X-Real-IP`, `Forwarded`) from a source that is not listed in `gateway.trustedProxies`. It fails closed rather than trusting a client-supplied IP.

**In `lan_https` mode** the add-on handles this automatically. Its HTTPS proxy
runs on loopback, so only the actual nginx hop (`127.0.0.1` / `::1`) needs to
be trusted. For LAN clients nginx overwrites the forwarded identity with the
address of its direct peer. For same-host clients (for example a Home Assistant
integration calling the add-on through the host address), it omits forwarded
identity headers so token authentication is not misclassified as proxy auth.

**In `lan_reverse_proxy` mode** (or `custom` with your own proxy), set `gateway_trusted_proxies` to the address your proxy connects *from* — not the address clients use:

```
gateway_trusted_proxies: "172.30.0.0/16"
```

Your proxy must also send a trustworthy `X-Forwarded-For`. In Nginx Proxy
Manager this is the default. In a hand-written single-hop nginx configuration,
overwrite any client-supplied chain with the address of nginx's direct peer:

```nginx
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
```

Do not append an untrusted incoming chain with `$proxy_add_x_forwarded_for`
unless every preceding proxy is known and validates or rebuilds that chain.

### Gateway restart loop after an OpenClaw upgrade (`requires migration`)

**Symptom**: after an add-on update the gateway never comes up, and the log repeats:

```
Gateway failed to start: Legacy workspace setup state requires migration for
/config/.openclaw/workspace; run openclaw doctor --fix.
WARN: OpenClaw runtime exited with code 1. Restarting in 2s...
```

**Cause**: some OpenClaw releases gate startup behind a one-time data migration and refuse to boot until it has run. This is an upstream requirement, not an add-on misconfiguration.

**Fix**: since v0.5.90 the add-on detects a repeated failed start and runs `openclaw doctor --fix` automatically (once per start, after snapshotting `openclaw.json` first). If it has not recovered on its own, the web terminal stays available during the loop — open it and run:

```sh
openclaw doctor --fix
```

Then restart the add-on. If the gateway still refuses to start:

```sh
openclaw doctor          # full report
oc-gateway status        # add-on-native status
ls /config/.openclaw/logs/stability/   # per-failure diagnostic bundles
```

> The add-on backs off between restart attempts (2s doubling to a 60s cap) so a gateway that cannot start does not spin the CPU or fill the disk with stability bundles. The terminal, landing page and Ingress remain usable throughout.

### Safe rollback after an OpenClaw database upgrade

Before the add-on starts a new OpenClaw version, it saves one compressed state
archive under `/config/.openclaw/upgrade-backups/`. This includes `openclaw.json`,
agent/session databases (including SQLite WAL files), pairing records and channel
delivery state. It excludes regenerable or bulky content such as built-in skills,
media, npm projects and logs. The add-on keeps the three newest upgrade archives.

If the archive cannot be created, the new gateway does **not** start. This avoids
an irreversible schema migration when disk space or permissions are unhealthy.

OpenClaw database schema upgrades are not downgrade-compatible. To roll back to
an older add-on release, first stop the add-on and move the current
`/config/.openclaw` directory aside. Create a new `/config/.openclaw` directory,
extract the desired archive into it, then start the older release. Do not extract
over the upgraded directory: its newer database files would remain in place.
Work created after that archive will not be present after the rollback.

### `JavaScript heap out of memory` / gateway restart loop on a Raspberry Pi

**Symptom**: The gateway restarts repeatedly; the log shows heap allocation failures, or the whole add-on is killed.

**Cause**: The workload exceeds the Node heap budget for the active [resource profile](#8a-resource-profiles), or the device is genuinely out of RAM.

**Fix**:
1. Check what profile is active — it is printed at startup and shown on the landing page.
2. If the device has headroom, move `resource_profile` up one step (`low` → `balanced`).
3. If it does not, reduce the load: `openclaw config set browser.enabled false`, and switch local embeddings to a remote provider.
4. Watch `sensor.openclaw_gateway_memory` over time (see [Health sensors](#6g-home-assistant-health-sensors)) to see whether you are near the ceiling.

### Health sensors do not appear in Home Assistant

**Symptom**: `ha_health_sensors` is on, but no `sensor.openclaw_*` entities exist.

**Checks**:
0. If your Home Assistant serves **HTTPS**, plain-HTTP probes fail with `HTTP 000` (curl reports *Empty reply from server*). Auto-detection tries `https` first from v0.5.90; if Home Assistant is on a non-default port or host, set `ha_base_url` explicitly.
1. Confirm `homeassistant_token` is set — the log says so at startup if it is missing.
2. Verify the data collection works at all (this needs no token):
   ```sh
   oc-health show
   ```
3. Diagnose credentials and connectivity in one step:
   ```sh
   oc-health check
   ```
   It reports which endpoint was chosen, whether the token is present, and the result of a live probe.
4. Try one real publish and read the error:
   ```sh
   oc-health once
   ```
   `HTTP 401` means the token is invalid or expired — create a new long-lived token in your Home Assistant profile → **Security**. `HTTP 000` means Home Assistant could not be reached at all.
5. Remember these entities are created via the REST API, so they disappear on a Home Assistant restart and come back at the next update interval (up to `ha_health_interval` seconds).

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
