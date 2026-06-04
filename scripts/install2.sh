#!/usr/bin/env bash
# =================================================
# NB-Panel 安装管理脚本
# 支持 二进制部署 / Docker 部署
# =================================================

SCRIPT_VERSION='3.0.0'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GITHUB_REPO="lima-droid/NB-Panel"

# ========== 通用函数 ==========
info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" && exit 1; }
hint() { echo -e "${CYAN} →${NC} $*"; }
title() { echo -e "\n${BOLD}${BLUE}━ $* ━${NC}\n"; }
step() { echo -e "${CYAN} ▸${NC} $*"; }
reading() { echo -n "$(echo -e "${GREEN} ▸${NC} $1")"; read "$2"; }

check_root() { [[ $(id -u) -ne 0 ]] && error "必须以 root 运行"; }

# ========== 架构检测 ==========
detect_arch() {
  local arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) echo "Linux_x86_64" ;;
    aarch64|arm64) echo "Linux_arm64" ;;
    armv7l|armv6l)  echo "Linux_armv7" ;;
    *) error "不支持的架构: $arch" ;;
  esac
}

# =================================================
# 二进制部署
# =================================================
BINARY_INSTALL_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DEFAULT_PORT="4000"

binary_check_install() {
  systemctl is-active --quiet $SERVICE_NAME 2>/dev/null && return 0
  [[ -f "$BINARY_INSTALL_DIR/bin/$BINARY_NAME" ]] && return 1
  return 2
}

binary_status() {
  binary_check_install
  case $? in
    0) echo -e "${GREEN}● 运行中${NC}" ;;
    1) echo -e "${YELLOW}○ 已停止${NC}" ;;
    2) echo -e "${RED}✕ 未安装${NC}" ;;
  esac
}

binary_download() {
  local arch=$(detect_arch)
  local url="https://github.com/${GITHUB_REPO}/releases/latest/download/NB-Panel_${arch}.tar.gz"
  local tmp="/tmp/nbpanel_binary.tar.gz"

  step "下载 NB-Panel (二进制)..."
  echo " ${CYAN}${url}${NC}"

  if command -v curl &>/dev/null; then
    curl -#L -o "$tmp" "$url"
  elif command -v wget &>/dev/null; then
    wget --show-progress -qO "$tmp" "$url"
  else
    error "未找到 curl 或 wget"
  fi

  [[ -f "$tmp" ]] || error "下载失败"
  echo "$tmp"
}

binary_do_install() {
  binary_check_install
  [[ $? -ne 2 ]] && { warn "NB-Panel 已安装 (二进制)"; return; }

  local tarball=$(binary_download)
  [[ ! -f "$tarball" ]] && error "未找到安装包"

  title "NB-Panel 安装配置"

  read -p " 监听端口 (默认 $DEFAULT_PORT): " USER_PORT
  USER_PORT="${USER_PORT:-$DEFAULT_PORT}"
  [[ ! "$USER_PORT" =~ ^[0-9]+$ || "$USER_PORT" -lt 1 || "$USER_PORT" -gt 65535 ]] && error "端口无效"

  local DASH_IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || echo "localhost")

  read -p " 启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    ENABLE_HTTPS="true"
    read -p " TLS 证书路径: " CERT_PATH
    read -p " TLS 私钥路径: " KEY_PATH
    [[ ! -f "$CERT_PATH" ]] && error "证书不存在: $CERT_PATH"
    [[ ! -f "$KEY_PATH" ]] && error "私钥不存在: $KEY_PATH"
  else
    ENABLE_HTTPS="false"
    CERT_PATH=""; KEY_PATH=""
  fi

  read -p " 确认安装? [Y/n]: " ok
  [[ "$ok" =~ ^[Nn]$ ]] && { echo "已取消"; return; }

  title "正在安装 (二进制)"

  local tmp="/tmp/npdash_tmp"
  rm -rf "$tmp" && mkdir "$tmp"
  tar -xzf "$tarball" -C "$tmp" >/dev/null 2>&1 || error "解压失败"

  local binary=$(find "$tmp" -name "$BINARY_NAME" -type f | head -1)
  [[ -z "$binary" ]] && error "未找到二进制文件"

  # 目录
  mkdir -p "$BINARY_INSTALL_DIR"/{bin,db,logs,certs}
  local NPD_USER_NAME="nodepass"
  id "$NPD_USER_NAME" &>/dev/null || useradd --system --home "$BINARY_INSTALL_DIR" --shell /bin/false "$NPD_USER_NAME"

  cp "$binary" "$BINARY_INSTALL_DIR/bin/$BINARY_NAME"
  chmod 755 "$BINARY_INSTALL_DIR/bin/$BINARY_NAME"
  chown root:root "$BINARY_INSTALL_DIR/bin/$BINARY_NAME"
  ln -sf "$BINARY_INSTALL_DIR/bin/$BINARY_NAME" /usr/local/bin/$BINARY_NAME

  chown -R "$NPD_USER_NAME:$NPD_USER_NAME" "$BINARY_INSTALL_DIR"/{db,logs,certs} 2>/dev/null
  chown "$NPD_USER_NAME:$NPD_USER_NAME" "$BINARY_INSTALL_DIR" 2>/dev/null

  # 配置
  cat > "$BINARY_INSTALL_DIR/config.env" << EOF
PORT=$USER_PORT
ENABLE_HTTPS=$ENABLE_HTTPS
DB_PATH=$BINARY_INSTALL_DIR/db/database.db
EOF

  local tls_args=""
  if [[ "$ENABLE_HTTPS" == "true" ]]; then
    cp "$CERT_PATH" "$BINARY_INSTALL_DIR/certs/server.crt"
    cp "$KEY_PATH" "$BINARY_INSTALL_DIR/certs/server.key"
    chown "$NPD_USER_NAME:$NPD_USER_NAME" "$BINARY_INSTALL_DIR/certs/"*
    chmod 600 "$BINARY_INSTALL_DIR/certs/server.key"
    cat >> "$BINARY_INSTALL_DIR/config.env" << EOF
CERT_PATH=$BINARY_INSTALL_DIR/certs/server.crt
KEY_PATH=$BINARY_INSTALL_DIR/certs/server.key
EOF
    tls_args=" --cert $BINARY_INSTALL_DIR/certs/server.crt --key $BINARY_INSTALL_DIR/certs/server.key"
  fi

  # systemd
  cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=NB-Panel - NodePass 隧道管理面板
After=network.target

[Service]
User=$NPD_USER_NAME
Group=$NPD_USER_NAME
WorkingDirectory=$BINARY_INSTALL_DIR
ExecStart=$BINARY_INSTALL_DIR/bin/$BINARY_NAME --port $USER_PORT$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$BINARY_INSTALL_DIR/config.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable $SERVICE_NAME >/dev/null 2>&1
  systemctl start $SERVICE_NAME

  rm -rf "$tmp" "$tarball"

  sleep 2
  local proto="http"
  [[ "$ENABLE_HTTPS" == "true" ]] && proto="https"

  echo
  echo -e "${BOLD}${GREEN}+──────────────────────────+${NC}"
  echo -e "${BOLD}${GREEN}|  NB-Panel 安装完成 (二进制) |${NC}"
  echo -e "${BOLD}${GREEN}+──────────────────────────+${NC}"
  echo
  echo -e " 地址: ${CYAN}${proto}://${DASH_IP}:${USER_PORT}${NC}"
  echo -e " 账号: ${YELLOW}nbpanel / Np123456${NC}"
  echo

  if systemctl is-active --quiet $SERVICE_NAME; then
    info "服务已启动"
  else
    warn "服务可能未启动: journalctl -u $SERVICE_NAME -n 20"
  fi
}

binary_do_uninstall() {
  binary_check_install
  [[ $? -eq 2 ]] && { warn "未安装 (二进制)"; return; }

  read -p " 确认卸载? [y/N]: " ok
  [[ ! "$ok" =~ ^[Yy]$ ]] && return

  systemctl stop $SERVICE_NAME 2>/dev/null
  systemctl disable $SERVICE_NAME 2>/dev/null
  rm -f /etc/systemd/system/$SERVICE_NAME.service
  systemctl daemon-reload

  rm -rf "$BINARY_INSTALL_DIR"
  rm -f /usr/local/bin/$BINARY_NAME
  info "NB-Panel 二进制版已卸载"
}

binary_do_upgrade() {
  binary_check_install
  [[ $? -eq 2 ]] && { warn "未安装，先安装"; binary_do_install; return; }

  local tarball=$(binary_download)
  local tmp="/tmp/npdash_upgrade"
  rm -rf "$tmp" && mkdir "$tmp"
  tar -xzf "$tarball" -C "$tmp" >/dev/null 2>&1 || error "解压失败"
  local binary=$(find "$tmp" -name "$BINARY_NAME" -type f | head -1)
  [[ -z "$binary" ]] && error "未找到二进制文件"

  systemctl stop $SERVICE_NAME 2>/dev/null
  cp "$binary" "$BINARY_INSTALL_DIR/bin/$BINARY_NAME"
  chmod 755 "$BINARY_INSTALL_DIR/bin/$BINARY_NAME"
  systemctl start $SERVICE_NAME

  rm -rf "$tmp" "$tarball"
  info "升级完成"
}

binary_show_info() {
  binary_check_install
  local s=$?
  [[ $s -eq 2 ]] && { echo -e " ${RED}✕ 未安装${NC}"; return; }

  local port="$DEFAULT_PORT"
  [[ -f "$BINARY_INSTALL_DIR/config.env" ]] && source "$BINARY_INSTALL_DIR/config.env" 2>/dev/null

  local proto="http"
  [[ "$ENABLE_HTTPS" == "true" ]] && proto="https"

  echo -e " 类型: ${GREEN}二进制${NC}"
  [[ $s -eq 0 ]] && echo -e " 状态: ${GREEN}● 运行中${NC}" || echo -e " 状态: ${YELLOW}○ 已停止${NC}"
  echo -e " 目录: ${BINARY_INSTALL_DIR}"
  [[ -n "$port" ]] && echo -e " 端口: ${port}"
  echo -e " 地址: ${CYAN}${proto}://localhost:${port}${NC}"
}

# =================================================
# Docker 部署
# =================================================
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"
DOCKER_NAME="nb-panel"

docker_exists() {
  docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"
}

docker_running() {
  docker ps --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"
}

docker_status() {
  if docker_running; then
    echo -e "${GREEN}● 运行中${NC}"
  elif docker_exists; then
    echo -e "${YELLOW}○ 已停止${NC}"
  else
    echo -e "${RED}✕ 未安装${NC}"
  fi
}

docker_do_install() {
  docker_running && { warn "Docker 版已在运行"; return; }

  if ! command -v docker &>/dev/null; then
    error "Docker 未安装，请先安装 Docker"
  fi

  title "Docker 部署配置"

  read -p " 映射端口 (默认 4000): " PORT_HOST
  PORT_HOST="${PORT_HOST:-4000}"
  [[ ! "$PORT_HOST" =~ ^[0-9]+$ ]] && error "端口无效"

  read -p " 数据目录 (默认 $(pwd)): " DATA_DIR
  DATA_DIR="${DATA_DIR:-$(pwd)}"

  read -p " 确认安装? [Y/n]: " ok
  [[ "$ok" =~ ^[Nn]$ ]] && { echo "已取消"; return; }

  title "正在安装 (Docker)"

  if docker_exists; then
    docker stop "$DOCKER_NAME" 2>/dev/null || true
    docker rm "$DOCKER_NAME" 2>/dev/null || true
  fi

  mkdir -p "$DATA_DIR"/{logs,public,db}
  chmod 777 "$DATA_DIR"/{logs,public,db}

  step "拉取镜像..."
  docker pull "$DOCKER_IMAGE"

  step "启动容器..."
  docker run -d \
    --name "$DOCKER_NAME" \
    --restart=always \
    -p "${PORT_HOST}:4000" \
    -e PORT="4000" \
    -v "$DATA_DIR/logs:/app/logs" \
    -v "$DATA_DIR/db:/app/db" \
    -v "$DATA_DIR/public:/app/public" \
    "$DOCKER_IMAGE"

  sleep 2

  if docker_running; then
    local IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || hostname -I | awk '{print $1}')
    IP="${IP:-localhost}"
    echo
    echo -e "${BOLD}${GREEN}+──────────────────────────+${NC}"
    echo -e "${BOLD}${GREEN}|  NB-Panel 安装完成 (Docker) |${NC}"
    echo -e "${BOLD}${GREEN}+──────────────────────────+${NC}"
    echo
    echo -e " 地址: ${CYAN}http://${IP}:${PORT_HOST}${NC}"
    echo -e " 账号: ${YELLOW}nbpanel / Np123456${NC}"
    echo
    info "容器已启动"
  else
    error "启动失败: docker logs $DOCKER_NAME"
  fi
}

docker_do_uninstall() {
  docker_exists || { warn "Docker 版未安装"; return; }

  read -p " 确认卸载? [y/N]: " ok
  [[ ! "$ok" =~ ^[Yy]$ ]] && return

  docker stop "$DOCKER_NAME" 2>/dev/null || true
  docker rm "$DOCKER_NAME" 2>/dev/null || true
  docker rmi "$DOCKER_IMAGE" 2>/dev/null || true

  read -p " 删除数据目录? [y/N]: " del
  if [[ "$del" =~ ^[Yy]$ ]]; then
    local DATA_DIR="${DATA_DIR:-$(pwd)}"
    rm -rf "$DATA_DIR"/logs "$DATA_DIR"/db "$DATA_DIR"/public
    info "数据已删除"
  fi

  info "Docker 版已卸载"
}

docker_do_upgrade() {
  docker_exists || { warn "Docker 版未安装"; docker_do_install; return; }

  docker stop "$DOCKER_NAME" 2>/dev/null || true
  docker rm "$DOCKER_NAME" 2>/dev/null || true

  docker pull "$DOCKER_IMAGE"

  local DATA_DIR="${DATA_DIR:-$(pwd)}"
  docker run -d \
    --name "$DOCKER_NAME" \
    --restart=always \
    -p "${PORT_HOST:-4000}:4000" \
    -e PORT="4000" \
    -v "$DATA_DIR/logs:/app/logs" \
    -v "$DATA_DIR/db:/app/db" \
    -v "$DATA_DIR/public:/app/public" \
    "$DOCKER_IMAGE"

  sleep 2
  docker_running && info "升级完成" || error "升级失败"
}

docker_show_info() {
  local IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  IP="${IP:-localhost}"

  echo -e " 类型: ${GREEN}Docker${NC}"
  if docker_running; then
    echo -e " 状态: ${GREEN}● 运行中${NC}"
    local port=$(docker port "$DOCKER_NAME" 2>/dev/null | head -1 | grep -oP '0.0.0.0:\K\d+')
    echo -e " 地址: ${CYAN}http://${IP}:${port:-4000}${NC}"
  elif docker_exists; then
    echo -e " 状态: ${YELLOW}○ 已停止${NC}"
  else
    echo -e " 状态: ${RED}✕ 未安装${NC}"
  fi
  echo -e " 容器: ${DOCKER_NAME}"
}

# =================================================
# 主菜单
# =================================================
get_overall_status() {
  local bs=""
  binary_check_install 2>/dev/null
  case $? in
    0) bs="${GREEN}二进制●${NC}" ;;
    1) bs="${YELLOW}二进制○${NC}" ;;
    2) bs="${RED}二进制✕${NC}" ;;
  esac

  local ds=""
  if docker_running 2>/dev/null; then
    ds="${GREEN}Docker●${NC}"
  elif docker_exists 2>/dev/null; then
    ds="${YELLOW}Docker○${NC}"
  else
    ds="${RED}Docker✕${NC}"
  fi

  echo -e " ${BOLD}状态:${NC} $bs | $ds"
}

install_menu() {
  clear
  echo
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo -e " ${BOLD}${BLUE}|${NC}       安装 NB-Panel         ${BOLD}${BLUE}|${NC}"
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo
  echo " 选择部署方式:"
  echo "   1) 二进制部署 (systemd 服务)"
  echo "   2) Docker 部署"
  echo "   0) 返回上级"
  echo
  reading "请选择 [1/2/0]: " ch
  case "$ch" in
    1) binary_do_install ;;
    2) docker_do_install ;;
    0) return ;;
    *) install_menu ;;
  esac
}

uninstall_menu() {
  clear
  echo
  echo -e " ${BOLD}${RED}+──────────────────────────────+${NC}"
  echo -e " ${BOLD}${RED}|${NC}       卸载 NB-Panel         ${BOLD}${RED}|${NC}"
  echo -e " ${BOLD}${RED}+──────────────────────────────+${NC}"
  echo
  echo " 选择卸载目标:"
  echo "   1) 二进制部署"
  echo "   2) Docker 部署"
  echo "   3) 全部卸载"
  echo "   0) 返回上级"
  echo
  reading "请选择 [1/2/3/0]: " ch
  case "$ch" in
    1) binary_do_uninstall ;;
    2) docker_do_uninstall ;;
    3) binary_do_uninstall; docker_do_uninstall ;;
    0) return ;;
    *) uninstall_menu ;;
  esac
}

update_menu() {
  clear
  echo
  echo -e " ${BOLD}${YELLOW}+──────────────────────────────+${NC}"
  echo -e " ${BOLD}${YELLOW}|${NC}       更新 NB-Panel         ${BOLD}${YELLOW}|${NC}"
  echo -e " ${BOLD}${YELLOW}+──────────────────────────────+${NC}"
  echo
  echo " 选择更新目标:"
  echo "   1) 二进制部署"
  echo "   2) Docker 部署"
  echo "   0) 返回上级"
  echo
  reading "请选择 [1/2/0]: " ch
  case "$ch" in
    1) binary_do_upgrade ;;
    2) docker_do_upgrade ;;
    0) return ;;
    *) update_menu ;;
  esac
}

show_status() {
  clear
  echo
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo -e " ${BOLD}${BLUE}|${NC}       NB-Panel 状态         ${BOLD}${BLUE}|${NC}"
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo
  echo -e " ${BOLD}二进制版${NC}"
  echo -e " ──────────────────────"
  binary_show_info
  echo
  echo -e " ${BOLD}Docker 版${NC}"
  echo -e " ──────────────────────"
  docker_show_info
  echo
}

main_menu() {
  local last_choice="$1"

  clear
  echo
  echo -e " ${BOLD}${BLUE}+─────────────────────────────────────+${NC}"
  echo -e " ${BOLD}${BLUE}|   NB-Panel ${SCRIPT_VERSION} 管理脚本         ${BOLD}${BLUE}|${NC}"
  echo -e " ${BOLD}${BLUE}|${NC}  ${CYAN}https://github.com/lima-droid/NB-Panel${NC}  ${BOLD}${BLUE}|${NC}"
  echo -e " ${BOLD}${BLUE}+─────────────────────────────────────+${NC}"
  echo
  get_overall_status
  echo
  echo -e " ${BOLD}操作菜单${NC}"
  echo -e " ────────────────────────────────"
  echo -e "  ${GREEN}1${NC}. 安装"
  echo -e "  ${RED}2${NC}. 卸载"
  echo -e "  ${YELLOW}3${NC}. 更新"
  echo -e "  ${CYAN}4${NC}. 查看状态"
  echo -e "  ${CYAN}5${NC}. 查看日志"
  echo -e "  ${CYAN}6${NC}. 重启 (二进制)"
  echo -e "  ${CYAN}0${NC}. 退出"
  echo

  local prompt="${last_choice:-请选择 [1/2/3/4/5/6/0]} "
  reading "$prompt" ch
  ch="${ch:-$last_choice}"

  case "$ch" in
    1) install_menu; main_menu ;;
    2) uninstall_menu; main_menu ;;
    3) update_menu; main_menu ;;
    4) show_status; echo; reading "按回车键返回... " _; main_menu ;;
    5)
      echo
      if docker_running 2>/dev/null; then
        docker logs --tail 50 "$DOCKER_NAME" 2>/dev/null
      elif binary_check_install 2>/dev/null; [ $? -ne 2 ]; then
        journalctl -u $SERVICE_NAME -n 50 --no-pager
      else
        warn "无运行的实例"
      fi
      echo; reading "按回车键返回... " _; main_menu
      ;;
    6)
      systemctl restart $SERVICE_NAME 2>/dev/null && info "已重启" || warn "重启失败或未安装"
      sleep 1; main_menu
      ;;
    0) echo; exit 0 ;;
    *) main_menu "$ch" ;;
  esac
}

# ========== 入口 ==========
main() {
  check_root

  case "$1" in
    -i|--install) binary_do_install ;;
    -I|--docker-install) docker_do_install ;;
    -U|--upgrade) binary_do_upgrade ;;
    -u|--uninstall) binary_do_uninstall ;;
    -s|--status) show_status ;;
    -h|--help)
      echo
      echo -e "${BOLD}NB-Panel 管理脚本 v${SCRIPT_VERSION}${NC}"
      echo
      echo " bash $0                    交互式菜单"
      echo " bash $0 -i                 二进制安装"
      echo " bash $0 -I                 Docker 安装"
      echo " bash $0 -U                 升级"
      echo " bash $0 -u                 卸载"
      echo " bash $0 -s                 查看状态"
      echo
      ;;
    *) main_menu ;;
  esac
}

main "$@"
