# Changelog

All notable changes to the OpenClaw Assistant Home Assistant Add-on will be documented in this file.

## [0.5.66] - 2026-04-04

### Fixed
- **"Open Gateway Web UI" button missing token on first boot / post-onboard** (issue #102): the gateway token was read once at startup, before `openclaw onboard` had a chance to write `openclaw.json`. The landing page now re-renders automatically in the background (up to ~2 min after startup) once the token appears in `openclaw.json`, and nginx is reloaded with SIGHUP — no add-on restart required. Existing installs with a token already present are unaffected.

## [0.5.65] - 2026-04-04

### Changed
- Bump OpenClaw to 2026.4.2.

## [0.5.63] - 2026-03-14

### Changed
- Bump OpenClaw to 2026.3.13.

## [0.5.62] - 2026-03-10

### Fixed
- **Gateway restart loop** (issue #95): `openclaw gateway run` is a thin wrapper that spawns `openclaw-gateway` as a long-running daemon then exits immediately. On self-restart (SIGUSR1 / `openclaw gateway restart`), the old daemon forks a new one and exits — the new PID is not a child of run.sh. The supervisor now uses a 3-tier daemon detection function (`find_gateway_daemon_pid`): (1) port ownership via `ss -tlnp`, (2) process title via `pgrep -f "openclaw-gateway"`, (3) `/proc/*/cmdline` scan for "openclaw" (catches the daemon immediately after fork, even before process.title or port bind — critical on Pi/eMMC where initialization takes 20-30 s). Detection retries up to 10 times with a final port-occupancy guard before any supervisor-initiated restart. Non-child PIDs are monitored with `kill -0` polling instead of `wait`. The loopback relay (tailnet mode) is stopped/restarted around gateway restarts to prevent port conflicts.

## [0.5.60] - 2026-03-10

### Fixed
- **Session lock cleanup ignored non-default agents**: `cleanup_session_locks` was hardcoded to `agents/main/sessions`, skipping stale locks for any agent with a custom `forcedAgentId`. Stale locks could block the gateway from opening sessions for those agents, causing silent fallback to `main`. Cleanup now scans all `agents/*/sessions/` directories.

## [0.5.59] - 2026-03-10

- **Remote mode URL not propagated** (issue #93): `start_openclaw_runtime` was reading `gateway.remote.url` back via `openclaw config get`, which can time out (2 s limit at startup) or return an empty/redacted result. The function now uses `$GATEWAY_REMOTE_URL` directly from the already-parsed add-on options, which is the same value the config helper writes to `openclaw.json`.
- **Terminal CLI unreachable in tailnet mode** (issue #90): when `gateway_bind_mode=tailnet` (or `access_mode=tailnet_https`), the gateway binds only to the Tailscale IP. The local CLI always connects via `ws://127.0.0.1:PORT`, causing "Gateway not running" inside the add-on terminal. A lightweight loopback relay (Node.js) is now started automatically to forward `127.0.0.1:PORT → TAILSCALE_IP:PORT`, making all terminal CLI commands work normally. Token auth is still enforced end-to-end by the gateway.
- **Session lock cleanup ignored non-default agents**: `cleanup_session_locks` was hardcoded to `agents/main/sessions`, skipping stale locks for any agent with a custom `forcedAgentId`. Stale locks could block the gateway from opening sessions for those agents, causing silent fallback to `main`. Cleanup now scans all `agents/*/sessions/` directories.

### Added
- **MCP auto-configuration for Home Assistant**: new option `auto_configure_mcp` (default: `false`). When enabled and `homeassistant_token` is set, the add-on automatically registers Home Assistant as an MCP server (`mcporter config add HA ...`) on startup. Auto-detects the HA API URL (supervisor proxy or localhost:8123). Re-configures only when the token changes.
- Landing page: new collapsible **MCP setup** section with automatic and manual setup instructions, post-upgrade refresh command, and model tips.
- DOCS: new **MCP Integration** guide covering automatic/manual setup, verification, model requirements, and troubleshooting.

### Changed
- Bump OpenClaw to 2026.3.9.

## [0.5.58] - 2026-03-08

### Changed
- Bump OpenClaw to 2026.3.7.

## [0.5.57] - 2026-03-07

### Added
- New add-on option `controlui_disable_device_auth` (default: `true`) to control whether `gateway.controlUi.dangerouslyDisableDeviceAuth` is enabled in `lan_https` mode.

### Changed
- `set-control-ui-origins` helper now accepts an explicit device-auth toggle and applies `dangerouslyDisableDeviceAuth` accordingly instead of forcing it on.
- `run.sh` now forwards the add-on option to the config helper.
- Control UI guidance text and docs were updated to explain when device-pairing bypass should be ON vs OFF.

### Fixed
- Docker build stability: replaced NodeSource `setup_22.x | bash` installer with explicit keyring + apt source configuration for Node.js 22, avoiding intermittent `apt-get install nodejs` exit code 100 failures.

### Translations
- Added `controlui_disable_device_auth` labels/descriptions to: `en`, `bg`, `de`, `es`, `pl`, `pt-BR`.

## [0.5.55] - 2026-03-04

### Changed
- Bump OpenClaw to 2026.3.2.

## [0.5.54] - 2026-02-25

### Changed
- Added startup guidance when `gateway_auth_mode=trusted-proxy` is enabled to clarify why direct local CLI gateway calls can show `trusted_proxy_user_missing`/unauthorized.
- Bump OpenClaw to 2026.2.24.

### Added
- New add-on option `gateway_additional_allowed_origins` for extra Control UI origins in `lan_https` mode.
- **Custom SANs in TLS certificate** (`lan_https` mode): hostnames and IPs from `gateway_additional_allowed_origins` and `gateway_public_url` are now included in the server certificate's Subject Alternative Name. The certificate auto-regenerates when SANs change.

### Fixed
- **Gateway token on landing page**: read token directly from `openclaw.json` instead of via `openclaw config get` which redacts secrets since OpenClaw v2026.2.22+ (fixes "Open Gateway Web UI" button sending `openclaw_redacted` as the token).
- **Token retrieval instructions**: all "get your token" references in the landing page and DOCS now use `jq -r '.gateway.auth.token' /config/.openclaw/openclaw.json` with a note explaining why the old `openclaw config get` command no longer works.
- `lan_https` startup no longer overwrites `gateway.controlUi.allowedOrigins` with defaults only.
- Control UI origins are now merged as: built-in defaults + existing config values + `gateway_additional_allowed_origins` (deduplicated).
- In `lan_reverse_proxy` and other non-`lan_https` setups, Control UI origins now also include the origin derived from `gateway_public_url`.
- `gateway.controlUi.allowedOrigins` configuration is now consistently applied via merge logic (defaults + existing values + user extras), reducing manual `openclaw.json` edits after upgrades.
- Add-on no longer exits/restarts when OpenClaw runtime process is restarted during onboarding or config changes.
- `run.sh` now supervises the OpenClaw runtime (`openclaw gateway run` / `openclaw node run`) and auto-restarts it while keeping nginx + terminal alive.

## [0.5.53] - 2026-02-24
- Bump OpenClaw to 2026.2.23.

## [0.5.52] - 2026-02-23

### Added
- New add-on option `gateway_env_vars` that accepts a list of `{name, value}` objects from Home Assistant UI and safely injects values into the gateway process at startup (max 50 vars, key <=255 chars, value <=10000 chars).
- Guard `gateway_env_vars` from overriding reserved runtime/proxy/`OPENCLAW_*` keys.
- Keep legacy string/object input formats for backward compatibility.

## [0.5.51] - 2026-02-23

### Fixed
- **`web_fetch failed: fetch failed`**: changed `force_ipv4_dns` default to **true**. Node 22 tries IPv6 first; most HAOS VMs lack IPv6 egress, causing outbound `web_fetch` / HTTP tool calls to time out.

### Added
- **`nginx_log_level` option** (`minimal` / `full`, default `minimal`): suppresses repetitive Home Assistant health-check and polling requests (`GET /`, `GET /v1/models`, `POST /tools/invoke`) from the nginx access log.

## [0.5.50] - 2026-02-23

**[!WARNING!]**
This update contains lots of changes. It is adviced to backup before installing!

### Changed
- **Upgraded OpenClaw to v2026.2.22-2** — includes major gateway/auth/pairing fixes and security hardening.
- Precreate `$OPENCLAW_CONFIG_DIR/identity` on startup to prevent `EACCES` errors on CLI commands that need device identity.
- Gateway token is auto-constructed from detected LAN IP when `lan_https` is active and `gateway_public_url` is empty.
- Config helper now receives the effective internal port (gateway_port + 1 in lan_https mode).

### Notes — v2026.2.22 impact on this add-on
- **Pairing fixes (loopback)**: v2026.2.22 auto-approves loopback scope-upgrade pairing requests, includes `operator.read`/`operator.write` in default scope bundles, and treats `operator.admin` as satisfying other scopes. This greatly improves `local_only` mode reliability.
- **`dangerouslyDisableDeviceAuth` security warning**: v2026.2.22 now emits a startup warning when this flag is active. The warning is **expected and harmless** for `lan_https` mode — the flag is still required because LAN browser connections through the HTTPS proxy are not considered loopback by the gateway. Token auth remains enforced.
- **Gateway lock improvements**: stale-lock detection now uses port reachability, reducing false "already running" errors after unclean restarts.
- **Log file size cap**: new `logging.maxFileBytes` default (500 MB) prevents disk exhaustion from log storms.
- **`wss://` default for remote onboarding**: validates our HTTPS proxy approach as the correct direction.

### Added
- **Disk-space monitoring on the landing page** — shows total / used / available with colour-coded indicator (🟢 / 🟡 / 🔴).
- **Low-disk warning banner** appears automatically when usage exceeds 90 %.
- **`oc-cleanup` terminal command** — interactive helper that shows cache sizes (npm, pnpm, OpenClaw, Homebrew, pycache, tmp) and lets users reclaim space with a menu-driven cleanup.
- Startup disk-space check with log warnings when the overlay is above 75 % or 90 %.
- **`access_mode` preset option** — simplifies secure access configuration with one setting:
  - `custom` (default, backward-compatible): use individual gateway settings
  - `local_only`: loopback + token (Ingress/terminal only)
  - `lan_https`: **built-in HTTPS reverse proxy for LAN access** (recommended for phones/tablets)
  - `lan_reverse_proxy`: LAN bind + trusted-proxy for external reverse proxy (NPM, Caddy, Traefik)
  - `tailnet_https`: Tailscale interface bind + token auth
- **Built-in TLS certificate generation** (`lan_https` mode):
  - Auto-generates a local CA + server certificate on first startup
  - Server cert is regenerated automatically when LAN IP changes
  - CA certificate downloadable from the landing page for one-tap phone trust
  - nginx HTTPS server block terminates TLS and proxies to the loopback gateway
- **Overhauled landing page** with:
  - Real-time status cards (gateway health, secure context, access mode)
  - Access wizard with step-by-step guidance per mode
  - Error translation — maps raw errors like `1008: requires device identity` to friendly messages with fixes
  - CA certificate download button (lan_https mode)
  - Migration banner for users on `custom` mode recommending a preset
  - Collapsible reverse-proxy recipes (NPM / Caddy / Traefik / Tailscale)
- Added `openssl` to Docker image for TLS certificate generation.
- Translations for `access_mode` in all 6 languages (EN, BG, DE, ES, PL, PT-BR).

### Fixed
- **`lan_https` — error 1008 "pairing required"**: auto-set `gateway.controlUi.dangerouslyDisableDeviceAuth: true` to skip interactive device pairing (token auth remains enforced). Replaces the invalid `pairingMode` key that caused `Unrecognized key` config errors.
- Config helper now removes stale/invalid keys (e.g. `pairingMode`) from `controlUi` on startup.
- Landing page error translation now covers "pairing required" and "origin not allowed" errors with correct fix guidance.
- Dropdown translations for `access_mode`, `gateway_mode`, `gateway_bind_mode`, and `gateway_auth_mode` now show human-readable labels in all 6 languages.
- **`lan_https` — error 1008 "origin not allowed"**: auto-configure `gateway.controlUi.allowedOrigins` with the HTTPS proxy origins (LAN IP, `homeassistant.local`, `homeassistant`) so the Control UI WebSocket is accepted.

## [0.5.49] - 2026-02-22

### Added
- New add-on option `http_proxy` for configuring outbound HTTP/HTTPS proxy from Home Assistant settings.

### Changed
- Export `HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`, and `https_proxy` from add-on config at startup.
- Add translations for the new `http_proxy` option.
- Document proxy configuration in README and DOCS.

## [0.5.48] - 2026-02-22

### Changed
- Bump OpenClaw to 2026.2.21-2.
- Add Home Assistant `share` and `media` mounts to the add-on (`map: share:rw, media:rw`).
- Keep official OpenClaw npm release and add startup proxy shim for `HTTP_PROXY/HTTPS_PROXY` support in undici fetch.

## [0.5.47] - 2026-02-21

### Added
- Add new `gateway_bind_mode` values: `auto` and `tailnet`.

### Changed
- Update startup helper validation and CLI usage to support `auto|loopback|lan|tailnet` bind modes.
- Update add-on translations and docs for the expanded gateway bind mode options.

## [0.5.46] - 2026-02-18

### Added
- New add-on option `force_ipv4_dns` to enable IPv4-first DNS ordering for Node network calls (`NODE_OPTIONS=--dns-result-order=ipv4first`), helping Telegram connectivity on IPv6-broken networks.

### Changed
- Added translations for `force_ipv4_dns` option.
- Updated docs with `force_ipv4_dns` configuration and Telegram network troubleshooting note.
- Bump OpenClaw to 2026.2.17

## [0.5.45] - 2026-02-16

### Changed
- Bump OpenClaw to 2026.2.15

## [0.5.44] - 2026-02-14

### Changed
- Bump OpenClaw to 2026.2.13

## [0.5.43] - 2026-02-13

### Changed
- Bump OpenClaw to 2026.2.12

### Added
- Portuguese (Brazil) translation (`pt-BR.yaml`) by medeirosiago

## [0.5.42] - 2026-02-12

### Changed
- Change nginx ingress port from 8099 to 48099 to avoid conflicts with NextCloud and other services
- Persist Homebrew and brew-installed packages across container rebuilds (symlink to `/config/.linuxbrew/`)

### Added
- SECURITY.md with risk documentation and disclaimer

### Improved
- Comprehensive DOCS.md overhaul (architecture, use cases, persistence, troubleshooting, FAQ)
- README.md rewritten as concise landing page with quick start guide
- New branding assets (icon.png, logo.png)
- Added Discord server link to README

## [0.5.41] - 2026-02-11

### Changed
- Update Dockerfile, config.yaml, and run.sh for enhancements
- Update icon and logo images for improved quality

## [0.5.40] - 2026-02-11

### Added
- Additional tools in Dockerfile

### Changed
- Improved nginx process management in run.sh

## [0.5.39] - 2026-02-10

### Fixed
- Fix OpenClaw installation command in Dockerfile

## [0.5.38] - 2026-02-10

### Changed
- Bump OpenClaw to 2026.2.9

## [0.5.37] - 2026-02-09

### Added
- OpenAI API integration for Home Assistant Assist pipeline
- Updated translations

## [0.5.36] - 2026-02-08

### Changed
- Documentation updates

## [0.5.35] - 2026-02-08

### Changed
- Update Dockerfile for Homebrew installation improvements

## [0.5.34] - 2026-02-08

### Added
- Install pnpm globally

### Changed
- Upgrade OpenClaw version to 2026.2.6-3

## [0.5.33] - 2026-02-06

### Changed
- Enhanced README with images and updated setup instructions

---

For the full commit history, see [GitHub commits](https://github.com/techartdev/OpenClawHomeAssistant/commits/main).
