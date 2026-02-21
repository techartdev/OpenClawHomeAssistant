# Changelog

All notable changes to the OpenClaw Assistant Home Assistant Add-on will be documented in this file.

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
