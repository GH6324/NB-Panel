#!/bin/bash

# NB面板 一键安装脚本
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BINARY_NAME="nb-panel"
INSTALL_DIR="/opt/nb-panel"
SERVICE_NAME="nb-panel"
GITHUB_REPO="lima-droid/NB-Panel"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
DEFAULT_PORT="4000"

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    [ "$EUID" -ne 0 ] && { err "需要 root 权限"; exit 1; }
}

detect_arch() {
    case $(uname -m) in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)       err "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
}

install() {
    echo "=================================="
    echo "  NB面板 v3.4.2 一键安装"
    echo "=================================="

    check_root
    detect_arch

    info "下载二进制文件..."
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v3.4.2/nb-panel-linux-${ARCH}"
    curl -L -o /tmp/${BINARY_NAME} "${DOWNLOAD_URL}"

    info "创建目录..."
    mkdir -p ${INSTALL_DIR}/{bin,db,logs}
    cp /tmp/${BINARY_NAME} ${INSTALL_DIR}/bin/${BINARY_NAME}
    chmod +x ${INSTALL_DIR}/bin/${BINARY_NAME}

    info "创建 systemd 服务..."
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=NB面板 - 隧道管理面板
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/${BINARY_NAME} --port ${DEFAULT_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}
    sleep 2

    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo ""
        echo "=================================="
        echo "  NB面板 安装完成!"
        echo "  访问地址: http://$(curl -s ip.sb):${DEFAULT_PORT}"
        echo "  GitHub: https://github.com/lima-droid/NB-Panel"
        echo "=================================="
    else
        err "服务启动失败"
        journalctl -u ${SERVICE_NAME} --no-pager -n 20
        exit 1
    fi
}

uninstall() {
    echo "卸载 NB面板..."
    check_root

    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    rm -rf ${INSTALL_DIR}

    echo "NB面板 已卸载"
}

usage() {
    echo "用法: $0 [install|uninstall]"
}

case "${1:-install}" in
    install)   install ;;
    uninstall) uninstall ;;
    *)         usage ;;
esac
