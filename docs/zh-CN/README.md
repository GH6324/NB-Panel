<div align="center">
  <img src="https://raw.githubusercontent.com/lima-droid/NB-Panel/main/web/public/nodepass-logo-2.svg" alt="NB面板" height="80">
</div>

**语言：** 简体中文 | [English](../../README.md)

![Version](https://img.shields.io/badge/version-3.4.2-blue.svg)

NB面板 是一个现代化的隧道管理面板，用于集中管理端点、隧道与服务。项目采用 Go 后端并内置 React 前端，通过 SSE/WebSocket 提供实时监控。

## 功能亮点

- **隧道管理**：端点、隧道、服务一站式管理
- **实时监控**：SSE 实时流量数据和状态
- **单文件部署**：Go 后端内置 React 前端（Vite + TypeScript + HeroUI）
- **SQLite**：零外部依赖
- **Docker 支持**：一键部署

## 快速开始

```bash
# 下载二进制
wget https://github.com/lima-droid/NB-Panel/releases/download/v3.4.2/nb-panel-linux-amd64
chmod +x nb-panel-linux-amd64
./nb-panel-linux-amd64 --port 4000
```

或使用一键安装脚本：
```bash
bash <(wget -qO- https://raw.githubusercontent.com/lima-droid/NP-Master/main/scripts/np.sh) -i
```

## Docker

```bash
docker run -d --name nbpanel -p 4000:4000 ghcr.io/lima-droid/nb-panel:v3.4.2
```

## 链接

- Telegram: https://t.me/NBPanel
- Issues: https://github.com/lima-droid/NB-Panel/issues

