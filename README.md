<div align="center">
  <img src="https://raw.githubusercontent.com/lima-droid/NB-Panel/main/web/public/nodepass-logo-2.svg" alt="NB面板" height="80">
</div>

**Language:** English | [简体中文](docs/zh-CN/README.md)

![Version](https://img.shields.io/badge/version-3.4.2-blue.svg)

NB Panel is a modern web dashboard for managing tunnels, endpoints, and services. It ships as a single Go binary with an embedded React frontend, and provides real-time telemetry via SSE/WebSocket.

## Highlights

- **Tunnel management**: endpoints, tunnels, and services in one place
- **Real-time SSE**: live stats and traffic data
- **Single binary**: Go backend + embedded React (Vite + TypeScript + HeroUI)
- **SQLite**: zero external dependencies
- **Docker support**: ready to deploy

## Quick Start

```bash
# Download binary
wget https://github.com/lima-droid/NB-Panel/releases/download/v3.4.2/nb-panel-linux-amd64
chmod +x nb-panel-linux-amd64
./nb-panel-linux-amd64 --port 4000
```

Or via one-click installer:
```bash
bash <(wget -qO- https://raw.githubusercontent.com/lima-droid/NP-Master/main/scripts/np.sh) -i
```

## Docker

```bash
docker run -d --name nbpanel -p 4000:4000 ghcr.io/lima-droid/nb-panel:v3.4.2
```

## Links

- Issues: https://github.com/lima-droid/NB-Panel/issues
- Telegram: https://t.me/NBPanel
