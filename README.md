<div align="center">
  <img src="docs/nb-panel-logo.svg" alt="NB面板" height="80">
</div>

**Language:** English | [简体中文](docs/zh-CN/README.md)

![Version](https://img.shields.io/badge/version-3.4.1-blue.svg)
![GitHub license](https://img.shields.io/github/license/lima-droid/NB-Panel)

NB面板 is a modern web dashboard for managing **NB面板** endpoints, tunnels, and services. It ships as a single Go binary (Gin + GORM + SQLite) with an embedded React (Vite + TypeScript + HeroUI) frontend, and provides real-time telemetry via SSE/WebSocket.

## Highlights

- **Modern, clean dashboard**: responsive UI built with React + Vite + TypeScript + HeroUI.
- **Real-time monitoring**: SSE/WebSocket updates for tunnel status, traffic, and logs.
- **Multi-dimensional charts**: traffic trends (hour/day/week) with detailed drill-down views.
- **Powerful endpoint management**: endpoints, tunnels, and services in one place (including batch actions & sorting).
- **Scenario-based creation**: guided wizards/templates to create common setups faster and safer.
- **OAuth2 login support**: configure Cloudflare OAuth2 and optionally disable password login.
- **i18n**: built-in multilingual UI support.
- **Personalization**: privacy mode, theme/language onboarding, and configurable experience.
- **Operational tooling**: file-log viewer, network debugging utilities, and endpoint system stats charts.
- **Mobile-friendly workflows**: QR code output for importing into the mobile app.

[Full changelog →](https://github.com/lima-droid/NB-Panel/releases)

---

## Quick Start

- **Binary + systemd:** `docs/en/BINARY.md`
- **Docker:** `docs/en/DOCKER.md`
- **Development:** `docs/en/DEVELOPMENT.md`

## Documentation

- **Migration Guide:** [docs/en/MIGRATION.md](docs/en/MIGRATION.md)
- **Docker Guide:** [docs/en/DOCKER.md](docs/en/DOCKER.md)
- **Binary Guide:** [docs/en/BINARY.md](docs/en/BINARY.md)
- **Development Guide:** [docs/en/DEVELOPMENT.md](docs/en/DEVELOPMENT.md)

## CLI Flags

```bash
./nb-panel --help
./nb-panel --version
./nb-panel --port 8080
./nb-panel --log-level INFO
./nb-panel --cert /path/to/cert.pem --key /path/to/key.pem
./nb-panel --disable-login
./nb-panel --sse-debug-log
./nb-panel --resetpwd
```

## Default Password

Default admin password: `Np123456`

Can be overridden via environment variable `NODEPASS_ADMIN_PASSWORD`.

## License

BSD-3-Clause. See `LICENSE`.

## Disclaimer

This project is provided "as is", without any express or implied warranties. You are responsible for complying with local laws and regulations and using it only for lawful purposes. The authors are not liable for any direct, indirect, incidental, or consequential damages.

## Support

- Issues: https://github.com/lima-droid/NB-Panel/issues
- Telegram: https://t.me/CubeMihomo

## Stargazers

[![Star History Chart](https://api.star-history.com/svg?repos=lima-droid/NB-Panel&type=Date)](https://star-history.com/#lima-droid/NB-Panel&Date)
