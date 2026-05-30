<div align="center">
  <img src="docs/nb-panel-logo.png" alt="NB面板" height="120">
</div>

**Language:** English | [简体中文](docs/zh-CN/README.md)

![Version](https://img.shields.io/badge/version-3.4.2-blue.svg)
![GitHub license](https://img.shields.io/github/license/lima-droid/NB-Panel)

NB面板 是一个轻量级隧道管理面板，单二进制文件部署，Go 后端 + React 前端，SQLite 存储，开箱即用。

## 功能

- **端点管理**：统一管理所有 NP主控端，支持批量操作、排序、搜索
- **隧道管理**：可视化创建和编辑隧道，支持多种协议和场景模板
- **实时监控**：SSE/WebSocket 推送隧道状态、流量、日志
- **流量图表**：小时/日/周多维度流量趋势
- **OAuth2 登录**：支持 Cloudflare OAuth2，可关闭密码登录
- **多语言**：内置中英文界面
- **移动端友好**：响应式布局，支持二维码导入移动端 App
- **运维工具**：日志查看器、网络调试、系统状态图表

[Full changelog →](https://github.com/lima-droid/NB-Panel/releases)

---

## Quick Start

```bash
bash <(wget -qO- https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh)
```

- **One-liner install:** `scripts/install.sh`

## Documentation

See [scripts/install.sh](scripts/install.sh) for one-click install, or use the Docker image:

```bash
docker run -d --name nbpanel -p 4000:4000 ghcr.io/lima-droid/nb-panel:latest
```

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

## Default Login

| | |
|---|---|
| **Username** | `nbpanel` |
| **Password** | `Np123456` |

> Password can be overridden via environment variable `NB_PANEL_ADMIN_PASSWORD`.

## License

BSD-3-Clause. See `LICENSE`.

## Disclaimer

This project is provided "as is", without any express or implied warranties. You are responsible for complying with local laws and regulations and using it only for lawful purposes. The authors are not liable for any direct, indirect, incidental, or consequential damages.

## Support

- Issues: https://github.com/lima-droid/NB-Panel/issues
- TG group: https://t.me/NBPanel
- Telegram: https://t.me/CubeMihomo

## Stargazers

[![Star History Chart](https://api.star-history.com/svg?repos=lima-droid/NB-Panel&type=Date)](https://star-history.com/#lima-droid/NB-Panel&Date)
