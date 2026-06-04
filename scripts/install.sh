#!/usr/bin/env bash
set -e

SCRIPT_VERSION='3.0.0'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GITHUB_REPO="lima-droid/NB-Panel"

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[-]${NC} $*" && exit 1; }

check_root() {
  [[ $(id -u) -ne 0 ]] && error "必须以 root 运行"
}

# 二进制部署
BINARY_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DEFAULT_PORT="4000"

binary_installed() {
  systemctl is-active --quiet $SERVICE_NAME 2>/dev/null && return 0
  [[ -f "$BINARY_DIR/bin/$BINARY_NAME" ]] && return 1
  return 2
}

install_binary() {
  local arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch="Linux_x86_64" ;;
    aarch64|arm64) arch="Linux_arm64" ;;
    armv7l|armv6l)  arch="Linux_armv7" ;;
    *) error "不支持的架构: $arch" ;;
  esac

  local url="https://github.com/${GITHUB_REPO}/releases/latest/download/NB-Panel_${arch}.tar.gz"
  local tmp_tar="/tmp/nbpanel.tar.gz"
  local tmp_dir="/tmp/nbpanel_install"

  info "下载 NB-Panel..."
  if command -v curl &>/dev/null; then
    curl -#L -o "$tmp_tar" "$url"
  else
    wget --show-progress -qO "$tmp_tar" "$url"
  fi

  [[ -f "$tmp_tar" ]] || error "下载失败"

  rm -rf "$tmp_dir" && mkdir "$tmp_dir"
  tar -xzf "$tmp_tar" -C "$tmp_dir" >/dev/null 2>&1 || error "解压失败"

  local binary=$(find "$tmp_dir" -name "$BINARY_NAME" -type f | head -1)
  [[ -z "$binary" ]] && error "未找到二进制文件"

  read -p "监听端口 [${DEFAULT_PORT}]: " USER_PORT
  USER_PORT="${USER_PORT:-$DEFAULT_PORT}"

  local DASH_IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || echo "localhost")
  local tls_args=""

  read -p "启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    read -p "TLS 证书路径: " CERT_PATH
    read -p "TLS 私钥路径: " KEY_PATH
    [[ -f "$CERT_PATH" ]] || error "证书不存在: $CERT_PATH"
    [[ -f "$KEY_PATH" ]] || error "私钥不存在: $KEY_PATH"
  fi

  # 创建用户和目录
  id nodepass &>/dev/null || useradd --system --home "$BINARY_DIR" --shell /bin/false nodepass
  mkdir -p "$BINARY_DIR"/{bin,db,logs,certs}

  cp "$binary" "$BINARY_DIR/bin/$BINARY_NAME"
  chmod 755 "$BINARY_DIR/bin/$BINARY_NAME"
  ln -sf "$BINARY_DIR/bin/$BINARY_NAME" /usr/local/bin/$BINARY_NAME

  cat > "$BINARY_DIR/config.env" << EOF
PORT=$USER_PORT
ENABLE_HTTPS=${https:-false}
DB_PATH=$BINARY_DIR/db/database.db
EOF

  if [[ "$https" =~ ^[Yy]$ ]]; then
    cp "$CERT_PATH" "$BINARY_DIR/certs/server.crt"
    cp "$KEY_PATH" "$BINARY_DIR/certs/server.key"
    chmod 600 "$BINARY_DIR/certs/server.key"
    tls_args=" --cert $BINARY_DIR/certs/server.crt --key $BINARY_DIR/certs/server.key"
    cat >> "$BINARY_DIR/config.env" << EOF
CERT_PATH=$BINARY_DIR/certs/server.crt
KEY_PATH=$BINARY_DIR/certs/server.key
EOF
  fi

  chown -R nodepass:nodepass "$BINARY_DIR"/{db,logs,certs} 2>/dev/null
  chown nodepass:nodepass "$BINARY_DIR" 2>/dev/null

  cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=NB-Panel
After=network.target

[Service]
User=nodepass
Group=nodepass
WorkingDirectory=$BINARY_DIR
ExecStart=$BINARY_DIR/bin/$BINARY_NAME --port $USER_PORT$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$BINARY_DIR/config.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --quiet $SERVICE_NAME
  systemctl start $SERVICE_NAME

  rm -rf "$tmp_dir" "$tmp_tar"

  local proto="http"
  [[ "$https" =~ ^[Yy]$ ]] && proto="https"

  echo
  info "NB-Panel 安装完成"
  echo "  地址: ${proto}://${DASH_IP}:${USER_PORT}"
  echo "  账号: nbpanel / Np123456"
  echo
}

uninstall_binary() {
  binary_installed || true
  [[ -f "$BINARY_DIR/bin/$BINARY_NAME" ]] || { warn "二进制版未安装"; return; }

  read -p "确认卸载? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return

  systemctl stop $SERVICE_NAME 2>/dev/null
  systemctl disable $SERVICE_NAME 2>/dev/null
  rm -f /etc/systemd/system/$SERVICE_NAME.service
  systemctl daemon-reload
  rm -rf "$BINARY_DIR"
  rm -f /usr/local/bin/$BINARY_NAME
  info "二进制版已卸载"
}

# Docker 部署
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"
DOCKER_NAME="nb-panel"

docker_installed() {
  docker ps --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$" && return 0
  docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$" && return 1
  return 2
}

install_docker() {
  command -v docker &>/dev/null || error "Docker 未安装"

  read -p "映射端口 [4000]: " PORT_HOST
  PORT_HOST="${PORT_HOST:-4000}"

  read -p "数据目录 [$(pwd)]: " DATA_DIR
  DATA_DIR="${DATA_DIR:-$(pwd)}"

  docker_installed || true
  if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"; then
    docker stop "$DOCKER_NAME" 2>/dev/null || true
    docker rm "$DOCKER_NAME" 2>/dev/null || true
  fi

  mkdir -p "$DATA_DIR"/{logs,public,db}
  chmod 777 "$DATA_DIR"/{logs,public,db}

  info "拉取镜像..."
  docker pull "$DOCKER_IMAGE"

  info "启动容器..."
  docker run -d \
    --name "$DOCKER_NAME" \
    --restart=always \
    -p "${PORT_HOST}:4000" \
    -e PORT=4000 \
    -v "$DATA_DIR/logs:/app/logs" \
    -v "$DATA_DIR/db:/app/db" \
    -v "$DATA_DIR/public:/app/public" \
    "$DOCKER_IMAGE"

  local IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || hostname -I | awk '{print $1}')
  IP="${IP:-localhost}"

  echo
  info "NB-Panel 安装完成 (Docker)"
  echo "  地址: http://${IP}:${PORT_HOST}"
  echo "  账号: nbpanel / Np123456"
  echo
}

uninstall_docker() {
  docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$" || { warn "Docker 版未安装"; return; }

  read -p "确认卸载? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return

  docker stop "$DOCKER_NAME" 2>/dev/null || true
  docker rm "$DOCKER_NAME" 2>/dev/null || true
  docker rmi "$DOCKER_IMAGE" 2>/dev/null || true

  read -p "删除数据目录? [y/N]: " del
  if [[ "$del" =~ ^[Yy]$ ]]; then
    local data_dir="${DATA_DIR:-$(pwd)}"
    rm -rf "$data_dir"/logs "$data_dir"/db "$data_dir"/public
  fi

  info "Docker 版已卸载"
}

# 交互安装
interactive_install() {
  echo
  echo "选择部署方式:"
  echo "  1) 二进制部署 (systemd)"
  echo "  2) Docker 部署"
  read -p "请选择 [1/2]: " mode

  case "$mode" in
    2) install_docker ;;
    *) install_binary ;;
  esac
}

# 状态
show_status() {
  echo
  echo "--- 二进制 ---"
  binary_installed; local s=$?
  case $s in
    0) echo "  状态: 运行中" ;;
    1) echo "  状态: 已停止" ;;
    2) echo "  未安装" ;;
  esac

  echo
  echo "--- Docker ---"
  docker_installed; local s=$?
  case $s in
    0) echo "  状态: 运行中" ;;
    1) echo "  状态: 已停止" ;;
    2) echo "  未安装" ;;
  esac
  echo
}

# 主菜单
main_menu() {
  echo "===================================="
  echo "  NB-Panel 管理脚本 v${SCRIPT_VERSION}"
  echo "  https://github.com/${GITHUB_REPO}"
  echo "===================================="
  echo
  echo "  1) 安装"
  echo "  2) 卸载"
  echo "  3) 更新"
  echo "  4) 状态"
  echo "  5) 日志"
  echo "  0) 退出"
  echo
  read -p "请选择 [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
    1) interactive_install ;;
    2)
      echo
      echo "卸载目标:"
      echo "  1) 二进制"
      echo "  2) Docker"
      echo "  3) 全部"
      read -p "请选择 [1/2/3]: " u
      case "$u" in
        2) uninstall_docker ;;
        3) uninstall_binary; uninstall_docker ;;
        *) uninstall_binary ;;
      esac
      ;;
    3)
      echo
      echo "更新目标:"
      echo "  1) 二进制"
      echo "  2) Docker"
      read -p "请选择 [1/2]: " up
      if [[ "$up" == "2" ]]; then
        docker_installed || true
        if docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"; then
          docker stop "$DOCKER_NAME" 2>/dev/null || true
          docker rm "$DOCKER_NAME" 2>/dev/null || true
        fi
        local PD="${PORT_HOST:-4000}"
        local DD="${DATA_DIR:-$(pwd)}"
        docker pull "$DOCKER_IMAGE"
        docker run -d --name "$DOCKER_NAME" --restart=always -p "${PD}:4000" -e PORT=4000 -v "$DD/logs:/app/logs" -v "$DD/db:/app/db" -v "$DD/public:/app/public" "$DOCKER_IMAGE"
        info "Docker 更新完成"
      else
        binary_installed || true
        install_binary
      fi
      ;;
    4) show_status ;;
    5)
      if docker ps --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"; then
        docker logs --tail 50 "$DOCKER_NAME"
      elif systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        journalctl -u $SERVICE_NAME -n 50 --no-pager
      else
        warn "无运行实例"
      fi
      ;;
    0) exit 0 ;;
  esac

  echo
  read -p "按回车键返回..."
  main_menu
}

# 入口
main() {
  check_root

  case "$1" in
    -b|--binary) install_binary ;;
    -d|--docker) install_docker ;;
    -u|--uninstall) uninstall_binary ;;
    -U|--uninstall-docker) uninstall_docker ;;
    -s|--status) show_status ;;
    *)
      main_menu
      ;;
  esac
}

main "$@"
