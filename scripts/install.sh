#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -eE
trap 'echo "Installation aborted. See: script/line $LINENO"; exit 1' ERR

VERSION="3.4.4"
INSTALL_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"

# Colors
ESC=$(printf '\033')
R="${ESC}[31m"; G="${ESC}[32m"; Y="${ESC}[33m"; C="${ESC}[36m"; B="${ESC}[1m"; N="${ESC}[0m"

msg()   { echo -e " ${B}${C}::${N}${B} $*${N}"; }
ok()    { echo -e " ${G}✓${N} $*"; }
warn()  { echo -e " ${Y}⚠${N} $*"; }
err()   { echo -e " ${R}✗${N} $*" >&2; exit 1; }
sep()   { echo -e " ${C}────────────────────────────────────────────${N}"; }
readp() { read -p "$(echo -e " ${G}?${N} $1")" "$2"; }

check_root() {
  [[ $EUID -eq 0 ]] || err "请使用 root 账户运行"
}

# ---------- Binary Install ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "Linux_x86_64" ;;
    aarch64|arm64) echo "Linux_arm64" ;;
    armv7l) echo "Linux_armv7" ;;
    *) err "不支持的架构: $(uname -m)" ;;
  esac
}

download_binary() {
  local url="https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_$(detect_arch).tar.gz"
  local dest="/tmp/nbpanel.tar.gz"
  msg "Downloading NB-Panel v${VERSION}..."

  if command -v curl &>/dev/null; then
    curl -#L -o "$dest" "$url" || err "下载失败"
  else
    wget --show-progress -qO "$dest" "$url" || err "下载失败"
  fi
  echo "$dest"
}

install_binary() {
  local tarball dest_port ip_addr cert_path key_path tls_args

  tarball=$(download_binary)

  msg "Extracting..."
  rm -rf /tmp/nbpanel_install && mkdir /tmp/nbpanel_install
  tar -xzf "$tarball" -C /tmp/nbpanel_install || err "解压失败"

  local binary
  binary=$(find /tmp/nbpanel_install -name "$BINARY_NAME" -type f | head -1)
  [[ -n "$binary" ]] || err "未找到二进制文件"

  echo
  sep
  echo -e " ${B}Binary Installation${N}"
  sep

  readp "监听端口 [4000]: " dest_port
  dest_port="${dest_port:-4000}"

  readp "启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    readp "TLS 证书路径: " cert_path
    readp "TLS 私钥路径: " key_path
    [[ -f "$cert_path" ]] || err "Certificate not found: $cert_path"
    [[ -f "$key_path" ]] || err "Private key not found: $key_path"
    tls_args=" --cert $cert_path --key $key_path"
  fi

  echo
  readp "确认安装? [Y/n]: " confirm
  [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }

  ip_addr=$(curl -s --max-time 5 https://ipv4.ip.sb 2>/dev/null || echo "localhost")

  msg "Setting up system user..."
  id nodepass &>/dev/null || useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass

  msg "Creating directories..."
  mkdir -p "$INSTALL_DIR"/{bin,db,logs}

  msg "Installing binary..."
  cp "$binary" "$INSTALL_DIR/bin/$BINARY_NAME"
  chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
  chown root:root "$INSTALL_DIR/bin/$BINARY_NAME"
  ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" /usr/local/bin/$BINARY_NAME

  cat > "$INSTALL_DIR/config.env" <<-ENV
PORT=$dest_port
DB_PATH=$INSTALL_DIR/db/database.db
ENV

  if [[ "$https" =~ ^[Yy]$ ]]; then
    mkdir -p "$INSTALL_DIR/certs"
    cp "$cert_path" "$INSTALL_DIR/certs/server.crt"
    cp "$key_path" "$INSTALL_DIR/certs/server.key"
    chmod 600 "$INSTALL_DIR/certs/server.key"
    cat >> "$INSTALL_DIR/config.env" <<-ENV
CERT_PATH=$INSTALL_DIR/certs/server.crt
KEY_PATH=$INSTALL_DIR/certs/server.key
ENV
  fi

  chown -R nodepass:nodepass "$INSTALL_DIR"/{db,logs,certs} 2>/dev/null

  msg "Registering systemd service..."
  cat > /etc/systemd/system/$SERVICE_NAME.service <<-SVC
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
SVC

  systemctl daemon-reload
  systemctl enable --quiet $SERVICE_NAME
  systemctl start $SERVICE_NAME

  rm -rf /tmp/nbpanel_install /tmp/nbpanel.tar.gz

  local proto="http"
  [[ "$https" =~ ^[Yy]$ ]] && proto="https"

  echo
  sep
  echo -e " ${G}${B}安装完成${N}"
  sep
  echo -e "   ${B}URL:${N}     ${C}${proto}://${ip_addr}:${dest_port}${N}"
  echo -e "   ${B}Account:${N} nbpanel / Np123456"
  echo -e "   ${B}Binary:${N}  $INSTALL_DIR/bin/$BINARY_NAME"
  echo -e "   ${B}Config:${N}  $INSTALL_DIR/config.env"
  sep
  echo
}

# ---------- Docker Install ----------
install_docker() {
  command -v docker &>/dev/null || err "请先安装 Docker. Please install Docker first."

  local port_host data_dir ip_addr

  echo
  sep
  echo -e " ${B}Docker 安装${N}"
  sep

  readp "映射端口 [4000]: " port_host
  port_host="${port_host:-4000}"

  readp "数据目录 [$(pwd)/nbpanel-data]: " data_dir
  data_dir="${data_dir:-$(pwd)/nbpanel-data}"

  echo
  readp "确认安装? [Y/n]: " confirm
  [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }

  ip_addr=$(curl -s --max-time 5 https://ipv4.ip.sb 2>/dev/null || hostname -I | awk '{print $1}')
  ip_addr="${ip_addr:-localhost}"

  # Remove existing container
  docker inspect "$SERVICE_NAME" &>/dev/null && {
    msg "Removing existing container..."
    docker rm -f "$SERVICE_NAME" &>/dev/null
  }

  mkdir -p "$data_dir"/{logs,public,db}
  chmod 777 "$data_dir"/{logs,public,db}

  msg "拉取 Docker 镜像..."
  docker pull "$DOCKER_IMAGE"

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
  sep
  echo -e " ${G}${B}安装完成${N}"
  sep
  echo -e "   ${B}URL:${N}     ${C}http://${ip_addr}:${port_host}${N}"
  echo -e "   ${B}Account:${N} nbpanel / Np123456"
  echo -e "   ${B}Data:${N}    ${data_dir}"
  sep
  echo
}

# ---------- Install Menu ----------
install_menu() {
  echo
  sep
  echo -e " ${B}选择安装方式${N}"
  sep
  echo -e "   ${B}1${N}. 二进制"
  echo -e "   ${B}2${N}. Docker"
  sep
  readp "请选择 [1/2]: " method
  echo

  case "$method" in
    2) install_docker ;;
    *) install_binary ;;
  esac
}

# ---------- Main Entry ----------
main() {
  check_root

  case "${1:-}" in
    -b|--binary) install_binary ;;
    -d|--docker) install_docker ;;
    -h|--help)
      echo "Usage: bash install.sh [OPTION]"
      echo "  -b, --binary    二进制安装 (systemd)"
      echo "  -d, --docker    Docker installation"
      echo "  (no option)     Interactive menu"
      exit 0
      ;;
    *)
      echo
      echo -e " ${B}${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
      echo -e " ${B}${C}  NB-Panel Installer v${VERSION}${N}"
      echo -e " ${B}${C}  github.com/lima-droid/NB-Panel${N}"
      echo -e " ${B}${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
      install_menu
      ;;
  esac
}

main "$@"
