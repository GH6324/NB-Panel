#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -eE
trap 'echo -e "\n\033[41m 安装失败 \033[0m 行号: $LINENO"; exit 1' ERR

VERSION="3.4.4"
INSTALL_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"

# ==================== 颜色系统 ====================
ESC=$(printf '\033')
# 基础颜色
readonly R="${ESC}[31m" G="${ESC}[32m" Y="${ESC}[33m" B="${ESC}[34m" M="${ESC}[35m" C="${ESC}[36m"
# 样式
readonly BOLD="${ESC}[1m" DIM="${ESC}[2m" ITALIC="${ESC}[3m" RESET="${ESC}[0m"
# 背景色
readonly BG_RED="${ESC}[41m" BG_GREEN="${ESC}[42m" BG_BLUE="${ESC}[44m"

# ==================== 纯文本图标 ====================
readonly ICON_INFO="[i]"
readonly ICON_SUCCESS="[OK]"
readonly ICON_WARN="[!]"
readonly ICON_ERROR="[X]"
readonly ICON_INSTALL=">>"
readonly ICON_DOCKER="<>"
readonly ICON_SETTING="[*]"
readonly ICON_TRASH="[-]"
readonly ICON_UPGRADE="^^"
readonly ICON_STATS="[*]"
readonly ICON_LOGS="[+]"
readonly ICON_EXIT="[x]"
readonly ICON_ARROW="->"
readonly ICON_STAR="*"

# ==================== 界面函数 ====================
msg()   { echo -e " ${BOLD}${C}${ICON_INFO}${RESET}${BOLD} $*${RESET}"; }
ok()    { echo -e " ${G}${ICON_SUCCESS}${RESET} $*"; }
warn()  { echo -e " ${Y}${ICON_WARN}${RESET} $*" >&2; }
err()   { echo -e " ${R}${ICON_ERROR}${RESET} $*" >&2; exit 1; }
sep()   { echo -e " ${DIM}────────────────────────────────────────────${RESET}"; }
hr()    { echo -e " ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

title() {
  echo
  echo -e " ${BOLD}${C}╔══════════════════════════════════════════════╗${RESET}"
  echo -e " ${BOLD}${C}║${RESET}${BOLD}     NB-Panel 安装管理脚本 v${VERSION}${RESET}${BOLD}${C}              ║${RESET}"
  echo -e " ${BOLD}${C}║${RESET}${DIM}     https://github.com/lima-droid/NB-Panel${RESET}${BOLD}${C}    ║${RESET}"
  echo -e " ${BOLD}${C}╚══════════════════════════════════════════════╝${RESET}"
}

menu_item() {
  local num="$1"
  local name="$2"
  local icon="$3"
  printf "  ${BOLD}${C}[${num}]${RESET}  %s  ${BOLD}%-15s${RESET}\n" "$icon" "$name"
}

readp() {
  echo -ne " ${ICON_ARROW} ${BOLD}${C}${1}${RESET} "
  read "$2"
}

readp_default() {
  local prompt="$1"
  local var_name="$2"
  local default="$3"
  echo -ne " ${ICON_ARROW} ${BOLD}${C}${prompt}${RESET} ${DIM}[${default}]${RESET} "
  read input
  printf -v "$var_name" '%s' "${input:-$default}"
}

confirm() {
  local prompt="${1:-确认继续?}"
  echo -ne " ${ICON_WARN} ${BOLD}${Y}${prompt}${RESET} ${DIM}[y/N]${RESET} "
  read confirm
  [[ "$confirm" =~ ^[Yy]$ ]]
}

check_root() {
  [[ $EUID -eq 0 ]] || err "请使用 root 账户运行"
}

# ==================== 检测函数 ====================
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "Linux_x86_64" ;;
    aarch64|arm64) echo "Linux_arm64" ;;
    armv7l) echo "Linux_armv7" ;;
    *) err "不支持的架构: $(uname -m)" ;;
  esac
}

get_public_ip() {
  curl -s --max-time 5 https://ipv4.ip.sb 2>/dev/null || \
  curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
  echo "localhost"
}

# ==================== 二进制安装 ====================
download_binary() {
  local url="https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_$(detect_arch).tar.gz"
  dest="/tmp/nbpanel.tar.gz"
  msg "下载 NB-Panel 二进制文件..."
  echo

  if command -v curl &>/dev/null; then
    curl -#L -o "$dest" "$url" || err "下载失败"
  else
    wget --show-progress -qO "$dest" "$url" || err "下载失败"
  fi
  echo
}

install_binary() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_INSTALL} 二进制安装向导${RESET}"
  sep

  download_binary

  msg "解压安装包..."
  rm -rf /tmp/nbpanel_install && mkdir /tmp/nbpanel_install
  tar -xzf "$dest" -C /tmp/nbpanel_install || err "解压失败"

  local binary
  binary=$(find /tmp/nbpanel_install -name "$BINARY_NAME" -type f | head -1)
  [[ -n "$binary" ]] || err "未找到二进制文件"

  echo
  sep
  echo -e " ${BOLD}${C}[*] 配置选项${RESET}"
  sep

  readp_default "监听端口" dest_port "4000"

  echo
  if confirm "启用 HTTPS 加密?"; then
    echo
    readp "TLS 证书路径: " cert_path
    readp "TLS 私钥路径: " key_path
    [[ -f "$cert_path" ]] || err "证书文件不存在: $cert_path"
    [[ -f "$key_path" ]] || err "私钥文件不存在: $key_path"
    tls_args=" --cert $cert_path --key $key_path"
    https="y"
  else
    https="n"
  fi

  echo
  if ! confirm "确认安装?"; then
    echo
    warn "安装已取消"
    return
  fi

  ip_addr=$(get_public_ip)

  echo
  msg "创建系统用户..."
  id nodepass &>/dev/null || useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass

  msg "创建目录..."
  mkdir -p "$INSTALL_DIR"/{bin,db,logs,certs}

  msg "安装二进制文件..."
  cp "$binary" "$INSTALL_DIR/bin/$BINARY_NAME"
  chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
  chown root:root "$INSTALL_DIR/bin/$BINARY_NAME"
  ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" /usr/local/bin/$BINARY_NAME

  # 生成配置文件
  printf "PORT=%s\n" "$dest_port" > "$INSTALL_DIR/config.env"
  printf "DB_PATH=%s/db/database.db\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"

  if [[ "$https" =~ ^[Yy]$ ]]; then
    mkdir -p "$INSTALL_DIR/certs"
    cp "$cert_path" "$INSTALL_DIR/certs/server.crt"
    cp "$key_path" "$INSTALL_DIR/certs/server.key"
    chmod 600 "$INSTALL_DIR/certs/server.key"
    printf "CERT_PATH=%s/certs/server.crt\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
    printf "KEY_PATH=%s/certs/server.key\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
  fi

  chown -R nodepass:nodepass "$INSTALL_DIR/db" "$INSTALL_DIR/logs" "$INSTALL_DIR/certs" 2>/dev/null 

  msg "注册 systemd 服务..."
  cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=NB-Panel
After=network.target

[Service]
User=nodepass
Group=nodepass
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/$BINARY_NAME --port $dest_port$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$INSTALL_DIR/config.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --quiet $SERVICE_NAME
  systemctl start $SERVICE_NAME

  rm -rf /tmp/nbpanel_install /tmp/nbpanel.tar.gz

  local proto="http"
  [[ "$https" =~ ^[Yy]$ ]] && proto="https"

  echo
  hr
  echo -e " ${BG_GREEN}${BOLD} 安装完成！ ${RESET}"
  hr
  echo
  echo -e "   ${BOLD}${C}访问地址:${RESET}    ${proto}://${ip_addr}:${dest_port}"
  echo -e "   ${BOLD}${C}默认账号:${RESET}    nbpanel"
  echo -e "   ${BOLD}${C}默认密码:${RESET}    Np123456"
  echo -e "   ${BOLD}${C}安装路径:${RESET}    $INSTALL_DIR/bin/$BINARY_NAME"
  echo -e "   ${BOLD}${C}配置文件:${RESET}    $INSTALL_DIR/config.env"
  echo
  hr
  echo
}

# ==================== Docker 安装 ====================
install_docker() {
  command -v docker &>/dev/null || err "请先安装 Docker"

  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_DOCKER} Docker 安装向导${RESET}"
  sep

  readp_default "映射端口" port_host "4000"
  local default_data_dir="${PWD}/nbpanel-data"
  echo
  readp "数据目录 [${default_data_dir}]: " data_dir
  data_dir="${data_dir:-$default_data_dir}"

  echo
  if ! confirm "确认安装?"; then
    echo
    warn "安装已取消"
    return
  fi

  ip_addr=$(get_public_ip)

  # 删除旧容器
  docker inspect "$SERVICE_NAME" &>/dev/null && {
    msg "删除旧容器..."
    docker rm -f "$SERVICE_NAME" &>/dev/null
  }

  msg "创建数据目录..."
  mkdir -p "$data_dir"/{logs,public,db}
  chmod 777 "$data_dir"/{logs,public,db}

  msg "拉取 Docker 镜像..."
  echo
  docker pull "$DOCKER_IMAGE" || err "镜像拉取失败"
  echo

  msg "启动容器..."
  docker run -d \
    --name "$SERVICE_NAME" \
    --restart=always \
    -p "${port_host}:4000" \
    -e PORT=4000 \
    -v "$data_dir/logs:/app/logs" \
    -v "$data_dir/db:/app/db" \
    -v "$data_dir/public:/app/public" \
    "$DOCKER_IMAGE" || err "容器启动失败"

  echo
  hr
  echo -e " ${BG_GREEN}${BOLD} 安装完成！ ${RESET}"
  hr
  echo
  echo -e "   ${BOLD}${C}默认账号:${RESET}    nbpanel"
  echo -e "   ${BOLD}${C}默认密码:${RESET}    Np123456"
  echo -e "   ${BOLD}${C}数据目录:${RESET}    ${data_dir}"
  echo -e "   ${BOLD}${C}访问地址:${RESET}    http://${ip_addr}:${port_host}"
  echo
  hr
  echo
}

# ==================== 卸载 ====================
uninstall_binary() {
  [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] || { warn "二进制版未安装"; return; }
  echo
  if confirm "确认卸载二进制版?"; then
    msg "停止服务..."
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/$BINARY_NAME
    echo
    ok "二进制版已卸载"
  else
    warn "已取消"
  fi
}

uninstall_docker() {
  docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" || { warn "Docker 版未安装"; return; }
  echo
  if confirm "确认卸载 Docker 版?"; then
    msg "停止并删除容器..."
    docker stop "$SERVICE_NAME" 2>/dev/null || true
    docker rm "$SERVICE_NAME" 2>/dev/null || true
    docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
    if confirm "删除数据目录?"; then
      local data_dir="${DATA_DIR:-$(pwd)/nbpanel-data}"
      rm -rf "$data_dir"
      ok "数据目录已删除"
    fi
    ok "Docker 版已卸载"
  else
    warn "已取消"
  fi
}

# ==================== 升级 ====================
upgrade() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_UPGRADE} 升级向导${RESET}"
  sep

  if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
    msg "Docker 升级中..."
    local pd dd
    pd=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
    dd=$(docker inspect "$SERVICE_NAME" 2>/dev/null | grep '"Source"' | sed 's/.*"Source": "//;s/".*//' | grep nbpanel-data | head -1)
    pd="${pd:-4000}"; dd="${dd:-$(pwd)/nbpanel-data}"
    docker stop "$SERVICE_NAME" 2>/dev/null; docker rm "$SERVICE_NAME" 2>/dev/null
    docker pull "$DOCKER_IMAGE"
    mkdir -p "$dd"/{logs,public,db} && chmod 777 "$dd"/{logs,public,db}
    docker run -d --name "$SERVICE_NAME" --restart=always -p "${pd}:4000" -e PORT=4000 -v "$dd/logs:/app/logs" -v "$dd/db:/app/db" -v "$dd/public:/app/public" "$DOCKER_IMAGE" && ok "Docker 升级完成"
  elif [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
    msg "二进制升级中..."
    systemctl stop $SERVICE_NAME 2>/dev/null
    download_binary
    rm -rf /tmp/nbpanel_install && mkdir /tmp/nbpanel_install
    tar -xzf "$dest" -C /tmp/nbpanel_install || err "解压失败"
    local binary=$(find /tmp/nbpanel_install -name "$BINARY_NAME" -type f | head -1)
    cp "$binary" "$INSTALL_DIR/bin/$BINARY_NAME" && chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
    systemctl start $SERVICE_NAME && ok "二进制升级完成"
    rm -rf /tmp/nbpanel_install
  else
    warn "未检测到已安装的 NB-Panel"
  fi
}

# ==================== 状态 ====================
show_status() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_STATS} 运行状态${RESET}"
  sep
  echo

  # 二进制状态
  echo -e " ${BOLD}${C}[二进制]${RESET}"
  if [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
      echo -e "   状态: ${G}运行中${RESET}"
      local port=$(grep ^PORT= "$INSTALL_DIR/config.env" 2>/dev/null | cut -d= -f2)
      echo -e "   端口: ${port:-4000}"
    else
      echo -e "   状态: ${R}已停止${RESET}"
    fi
  else
    echo -e "   状态: ${DIM}未安装${RESET}"
  fi

  echo
  echo -e " ${BOLD}${C}[Docker]${RESET}"
  if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
    if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
      echo -e "   状态: ${G}运行中${RESET}"
      local port=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
      echo -e "   端口: ${port:-4000}"
    else
      echo -e "   状态: ${R}已停止${RESET}"
    fi
  else
    echo -e "   状态: ${DIM}未安装${RESET}"
  fi

  echo
  readp "按回车键返回..." dummy
}

# ==================== 日志 ====================
show_logs() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_LOGS} 查看日志${RESET}"
  sep
  echo

  if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
    msg "Docker 日志 (最近30行):"
    echo
    docker logs --tail 30 "$SERVICE_NAME"
  elif systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
    msg "Systemd 日志 (最近30行):"
    echo
    journalctl -u $SERVICE_NAME -n 30 --no-pager
  else
    echo -e "   ${DIM}无运行实例${RESET}"
  fi

  echo
  readp "按回车键返回..." dummy
}

# ==================== 菜单 ====================
show_menu() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${C}[*] 请选择操作${RESET}"
  sep
  echo
  menu_item "1" "安装" "${ICON_INSTALL}"
  menu_item "2" "卸载" "${ICON_TRASH}"
  menu_item "3" "升级" "${ICON_UPGRADE}"
  menu_item "4" "状态" "${ICON_STATS}"
  menu_item "5" "日志" "${ICON_LOGS}"
  echo
  menu_item "0" "退出" "${ICON_EXIT}"
  echo
  sep
  echo
  readp "请输入选项 [0-5]: " choice
}

install_menu() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_INSTALL} 选择安装方式${RESET}"
  sep
  echo
  menu_item "1" "二进制安装" "${ICON_INSTALL}"
  menu_item "2" "Docker 安装" "${ICON_DOCKER}"
  echo
  menu_item "0" "返回主菜单" "${ICON_EXIT}"
  echo
  sep
  echo
  readp "请选择 [0-2]: " method

  case "$method" in
    2) install_docker ;;
    1) install_binary ;;
    0) return ;;
    *) install_menu ;;
  esac

  echo
  readp "按回车键返回..." dummy
}

uninstall_menu() {
  clear
  title
  echo
  sep
  echo -e " ${BOLD}${ICON_TRASH} 选择卸载方式${RESET}"
  sep
  echo

  local has_bin=0 has_dkr=0
  [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && has_bin=1
  docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && has_dkr=1

  if [[ $has_bin -eq 1 && $has_dkr -eq 1 ]]; then
    menu_item "1" "二进制版" "${ICON_INSTALL}"
    menu_item "2" "Docker 版" "${ICON_DOCKER}"
    menu_item "3" "全部卸载" "${ICON_TRASH}"
    echo
    menu_item "0" "返回主菜单" "${ICON_EXIT}"
    echo
    sep
    readp "请选择 [0-3]: " u
    case "$u" in
      2) uninstall_docker ;;
      3) uninstall_binary; uninstall_docker ;;
      1) uninstall_binary ;;
      *) return ;;
    esac
  elif [[ $has_dkr -eq 1 ]]; then
    uninstall_docker
  elif [[ $has_bin -eq 1 ]]; then
    uninstall_binary
  else
    warn "未检测到已安装的 NB-Panel"
  fi
}

# ==================== 主入口 ====================
main() {
  check_root

  if [[ $# -eq 0 ]]; then
    while true; do
      show_menu
      case "$choice" in
        1) install_menu ;;
        2) uninstall_menu ;;
        3) upgrade ;;
        4) show_status ;;
        5) show_logs ;;
        0) 
          echo
          echo -e " ${BOLD}${C}${ICON_EXIT} 感谢使用 NB-Panel！${RESET}"
          echo
          exit 0
          ;;
        *) ;;
      esac
    done
  else
    case "${1:-}" in
      -b|--binary) install_binary ;;
      -d|--docker) install_docker ;;
      -r|--remove) uninstall_binary ;;
      -R|--remove-docker) uninstall_docker ;;
      -u|--upgrade) upgrade ;;
      -s|--status) show_status ;;
      -l|--logs) show_logs ;;
      -h|--help)
        echo "用法: bash install.sh [选项]"
        echo
        echo "选项:"
        echo "  -b, --binary          二进制安装"
        echo "  -d, --docker          Docker 安装"
        echo "  -r, --remove          卸载二进制"
        echo "  -R, --remove-docker   卸载 Docker"
        echo "  -u, --upgrade         升级到最新版本"
        echo "  -s, --status          查看运行状态"
        echo "  -l, --logs            查看日志"
        echo "  -h, --help            显示帮助信息"
        echo
        echo "示例:"
        echo "  sudo bash install.sh           # 交互菜单"
        echo "  sudo bash install.sh -b        # 二进制安装"
        echo "  sudo bash install.sh -d        # Docker 安装"
        exit 0
        ;;
      *) main ;;
    esac
  fi
}

main "$@"
