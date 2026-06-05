#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -eEuo pipefail

trap 'error_handler $LINENO $?' ERR
trap 'cleanup_temp' EXIT

readonly SCRIPT_VERSION="3.4.4"
readonly INSTALL_DIR="/opt/nodepassdash"
readonly BINARY_NAME="nodepassdash"
readonly SERVICE_NAME="nodepassdash"
readonly DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"
readonly TEMP_DIR="/tmp/nbpanel_$$"
readonly LOG_FILE="/tmp/nbpanel_install.log"

if [[ -t 1 ]]; then
 readonly ESC=$(printf '\033')
 readonly R="${ESC}[31m" G="${ESC}[32m" Y="${ESC}[33m" C="${ESC}[36m" B="${ESC}[1m" N="${ESC}[0m"
else
 readonly R="" G="" Y="" C="" B="" N=""
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

error_handler() {
 local line=$1 code=$2
 echo -e " ${R}x${N} 安装中断 (行号: $line, 错误码: $code)" >&2
 log "ERROR at line $line, exit code $code"
 exit 1
}

cleanup_temp() { [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"; }

msg()   { echo -e " ${B}${C}::${N}${B} $*${N}"; log "INFO: $*"; }
ok()    { echo -e " ${G}v${N} $*"; log "OK: $*"; }
warn()  { echo -e " ${Y}w${N} $*" >&2; log "WARN: $*"; }
err()   { echo -e " ${R}x${N} $*" >&2; log "ERROR: $*"; exit 1; }
sep()   { echo -e " ${C}---------------------------------------------${N}"; }

readp() {
 local prompt="$1" var_name="$2" default="${3:-}" input
 while true; do
 if [[ -n "$default" ]]; then
 read -p "$(echo -e " $prompt [$default]: ")" input
 input="${input:-$default}"
 else
 read -p "$(echo -e " $prompt: ")" input
 fi
 if [[ -z "$input" && -z "$default" && "$3" != "allow_empty" ]]; then
 warn "输入不能为空"
 continue
 fi
 break
 done
 printf -v "$var_name" '%s' "$input"
}

check_root() {
 if [[ $EUID -ne 0 ]]; then
 if command -v sudo &>/dev/null; then
 warn "需要 root 权限，正在尝试使用 sudo..."
 exec sudo "$0" "$@"
 else
 err "请使用 root 账户运行"
 fi
 fi
}

detect_pkg_manager() {
 command -v apt-get &>/dev/null && echo "apt" && return
 command -v yum &>/dev/null && echo "yum" && return
 command -v dnf &>/dev/null && echo "dnf" && return
 command -v pacman &>/dev/null && echo "pacman" && return
 command -v zypper &>/dev/null && echo "zypper" || echo "unknown"
}

install_dependencies() {
 local missing_deps=() cmd pkg_manager
 for cmd in curl wget tar systemctl; do
 command -v "$cmd" &>/dev/null || missing_deps+=("$cmd")
 done
 [[ ${#missing_deps[@]} -eq 0 ]] && return
 warn "缺少依赖: ${missing_deps[*]}"
 pkg_manager=$(detect_pkg_manager)
 case $pkg_manager in
 apt)
 msg "使用 apt 安装依赖..."
 apt-get update -qq && apt-get install -y -qq curl wget tar systemd || warn "依赖安装失败" ;;
 yum|dnf)
 msg "使用 $pkg_manager 安装依赖..."
 $pkg_manager install -y curl wget tar systemd || warn "依赖安装失败" ;;
 pacman)
 msg "使用 pacman 安装依赖..."
 pacman -S --noconfirm curl wget tar systemd || warn "依赖安装失败" ;;
 zypper)
 msg "使用 zypper 安装依赖..."
 zypper install -y curl wget tar systemd || warn "依赖安装失败" ;;
 *)
 warn "无法自动安装依赖，请手动安装: curl, wget, tar, systemd" ;;
 esac
}

detect_system() {
 local os_id os_version
 if [[ -f /etc/os-release ]]; then
 # 使用子 shell 避免 readonly 冲突（/etc/os-release 定义 VERSION 变量）
 os_id=$(. /etc/os-release && echo "${ID:-unknown}") || true
 os_version=$(. /etc/os-release && echo "${VERSION_ID:-unknown}") || true
 OS="${os_id:-unknown}"
 VERSION_ID="${os_version:-unknown}"
 else
 OS=$(uname -s)
 VERSION_ID="unknown"
 fi
 case "$(uname -m)" in
 x86_64|amd64) ARCH="Linux_x86_64" ;;
 aarch64|arm64) ARCH="Linux_arm64" ;;
 armv7l|armhf) ARCH="Linux_armv7" ;;
 i386|i686) ARCH="Linux_i386" ;;
 *) err "不支持的架构: $(uname -m)" ;;
 esac
 if [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]] 2>/dev/null; then
 INIT_SYSTEM="systemd"
 elif [[ -f /sbin/openrc ]]; then
 INIT_SYSTEM="openrc"
 else
 INIT_SYSTEM="other"
 warn "非 systemd 系统，服务管理可能受限"
 fi
 log "System: $OS $VERSION_ID, Arch: $ARCH, Init: $INIT_SYSTEM"
}

download_file() {
 local url="$1" dest="$2" retries=3 timeout=30 i
 msg "下载: $(basename "$url")"
 for ((i=1; i<=retries; i++)); do
 if command -v curl &>/dev/null; then
 curl -fSL --connect-timeout "$timeout" --max-time "$timeout" --retry 2 -o "$dest" "$url" 2>/dev/null && return 0
 elif command -v wget &>/dev/null; then
 wget --timeout="$timeout" --tries=2 -q -O "$dest" "$url" && return 0
 else
 err "需要 curl 或 wget 来下载文件"
 fi
 [[ $i -lt $retries ]] && { warn "下载失败，重试 $((retries - i)) 次..."; sleep 2; }
 done
 err "下载失败: $url"
}

get_public_ip() {
 local ip=""
 for service in "https://ipv4.ip.sb" "https://api.ipify.org" "https://icanhazip.com" "https://ifconfig.me/ip"; do
 ip=$(curl -s --max-time 5 --connect-timeout 3 "$service" 2>/dev/null) || continue
 [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return 0; }
 done
 ip=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
 echo "${ip:-localhost}"
}

check_port() {
 local port=$1
 command -v ss &>/dev/null && ss -tuln 2>/dev/null | grep -E ":$port(\s|$)" >/dev/null 2>&1 && return 1
 command -v netstat &>/dev/null && netstat -tuln 2>/dev/null | grep -E ":$port(\s|$)" >/dev/null 2>&1 && return 1
 command -v lsof &>/dev/null && lsof -i ":$port" &>/dev/null && return 1
 return 0
}

setup_docker_dirs() {
 local data_dir="$1"
 mkdir -p "$data_dir"/{logs,public,db}
 chmod 777 "$data_dir"/{logs,public,db} 2>/dev/null || true
}

get_docker_port() {
 local port_info
 port_info=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' "$1" 2>/dev/null)
 echo "${port_info:-4000}"
}

get_docker_data_dir() {
 local mounts
 mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/db"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null)
 [[ -n "$mounts" ]] && echo "$(dirname "$mounts")" || echo "${PWD}/nbpanel-data"
}

# ---------- Binary ----------
download_binary() {
 local url="https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_${ARCH}.tar.gz"
 mkdir -p "$TEMP_DIR"
 download_file "$url" "$TEMP_DIR/nbpanel.tar.gz"
}

extract_binary() {
 local binary_path
 msg "解压安装包..."
 mkdir -p "$TEMP_DIR/extract"
 tar -xzf "$TEMP_DIR/nbpanel.tar.gz" -C "$TEMP_DIR/extract" || err "解压失败"
 binary_path=$(find "$TEMP_DIR/extract" -name "$BINARY_NAME" -type f | head -1)
 [[ -z "$binary_path" ]] && err "未找到二进制文件: $BINARY_NAME"
 cp "$binary_path" "$TEMP_DIR/$BINARY_NAME"
 chmod +x "$TEMP_DIR/$BINARY_NAME"
}

install_binary() {
 local dest_port ip_addr cert_path key_path tls_args=""
 [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && { warn "检测到已安装的二进制版本"; readp "是否覆盖安装? [y/N]: " confirm; [[ ! "$confirm" =~ ^[Yy]$ ]] && { warn "安装已取消"; return 1; }; systemctl stop "$SERVICE_NAME" 2>/dev/null || true; }
 install_dependencies
 download_binary
 extract_binary
 echo; sep; echo -e " ${B}二进制安装${N}"; sep
 while true; do
 readp "监听端口" dest_port "4000"
 [[ "$dest_port" =~ ^[0-9]+$ && "$dest_port" -ge 1 && "$dest_port" -le 65535 ]] || { warn "端口号必须在 1-65535 之间"; continue; }
 check_port "$dest_port" || { warn "端口 $dest_port 已被占用"; continue; }
 break
 done
 readp "启用 HTTPS? [y/N]: " https
 if [[ "$https" =~ ^[Yy]$ ]]; then
 while true; do
 readp "TLS 证书路径" cert_path "" allow_empty
 readp "TLS 私钥路径" key_path "" allow_empty
 [[ -n "$cert_path" && -n "$key_path" ]] || { warn "证书和私钥路径不能为空"; continue; }
 [[ -f "$cert_path" ]] || err "证书文件不存在: $cert_path"
 [[ -f "$key_path" ]] || err "私钥文件不存在: $key_path"
 tls_args=" --cert $cert_path --key $key_path"
 break
 done
 fi
 echo; readp "确认安装? [Y/n]: " confirm; [[ "$confirm" =~ ^[Nn]$ ]] && { warn "安装已取消"; return 1; }
 ip_addr=$(get_public_ip)
 msg "创建系统用户..."
 id nodepass &>/dev/null || useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass 2>/dev/null || useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin nodepass 2>/dev/null || err "无法创建系统用户"
 msg "创建目录..."; mkdir -p "$INSTALL_DIR"/{bin,db,logs,certs}
 msg "安装二进制文件..."
 cp "$TEMP_DIR/$BINARY_NAME" "$INSTALL_DIR/bin/$BINARY_NAME"; chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
 chown root:root "$INSTALL_DIR/bin/$BINARY_NAME"; ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" "/usr/local/bin/$BINARY_NAME"
 cat > "$INSTALL_DIR/config.env" <<-ENV
PORT=$dest_port
DB_PATH=$INSTALL_DIR/db/database.db
ENV
 [[ "$https" =~ ^[Yy]$ ]] && { mkdir -p "$INSTALL_DIR/certs"; cp "$cert_path" "$INSTALL_DIR/certs/server.crt"; cp "$key_path" "$INSTALL_DIR/certs/server.key"; chmod 600 "$INSTALL_DIR/certs/server.key"; cat >> "$INSTALL_DIR/config.env" <<-ENV
CERT_PATH=$INSTALL_DIR/certs/server.crt
KEY_PATH=$INSTALL_DIR/certs/server.key
ENV; }
 chown -R nodepass:nodepass "$INSTALL_DIR"/{db,logs,certs} 2>/dev/null || true
 msg "注册 systemd 服务..."
 if [[ "$INIT_SYSTEM" == "systemd" ]]; then
 cat > "/etc/systemd/system/$SERVICE_NAME.service" <<-SVC
[Unit]
Description=NB-Panel
After=network.target
Wants=network.target
[Service]
User=nodepass
Group=nodepass
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/$BINARY_NAME --port $dest_port$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$INSTALL_DIR/config.env
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
SVC
 systemctl daemon-reload; systemctl enable --quiet "$SERVICE_NAME" 2>/dev/null || warn "无法启用服务"; systemctl start "$SERVICE_NAME" || warn "服务启动失败"
 else
 warn "非 systemd 系统，请手动启动服务"
 fi
 local proto="http"; [[ "$https" =~ ^[Yy]$ ]] && proto="https"
 echo; sep; echo -e " ${G}${B}安装完成${N}"; sep
 echo -e " URL: ${C}${proto}://${ip_addr}:${dest_port}${N}"
 echo -e " 账号: nbpanel / Np123456"
 echo -e " 路径: $INSTALL_DIR/bin/$BINARY_NAME"
 echo -e " 配置: $INSTALL_DIR/config.env"
 [[ "$INIT_SYSTEM" == "systemd" ]] && echo -e " 服务: systemctl {start|stop|restart} $SERVICE_NAME"
 sep; echo
}

# ---------- Docker ----------
install_docker() {
 command -v docker &>/dev/null || { msg "Docker 未安装，尝试自动安装..."; curl -fsSL https://get.docker.com | bash || err "Docker 安装失败"; }
 local port_host data_dir ip_addr
 docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && { warn "检测到已存在的 Docker 容器"; readp "是否重新安装? [y/N]: " confirm; [[ ! "$confirm" =~ ^[Yy]$ ]] && { warn "安装已取消"; return 1; }; docker rm -f "$SERVICE_NAME" 2>/dev/null; }
 echo; sep; echo -e " ${B}Docker 安装${N}"; sep
 while true; do
 readp "映射端口" port_host "4000"
 [[ "$port_host" =~ ^[0-9]+$ && "$port_host" -ge 1 && "$port_host" -le 65535 ]] && break
 warn "端口号必须在 1-65535 之间"
 done
 local default_data_dir="${PWD}/nbpanel-data"; readp "数据目录" data_dir "$default_data_dir"; data_dir="${data_dir:-$default_data_dir}"
 echo; readp "确认安装? [Y/n]: " confirm; [[ "$confirm" =~ ^[Nn]$ ]] && { warn "安装已取消"; return 1; }
 ip_addr=$(get_public_ip); setup_docker_dirs "$data_dir"
 msg "拉取 Docker 镜像..."; docker pull "$DOCKER_IMAGE" || err "镜像拉取失败"
 msg "启动容器..."
 docker run -d --name "$SERVICE_NAME" --restart=always -p "${port_host}:4000" -e PORT=4000 \
 -v "$data_dir/logs:/app/logs" -v "$data_dir/db:/app/db" -v "$data_dir/public:/app/public" \
 "$DOCKER_IMAGE" || err "容器启动失败"
 echo; sep; echo -e " ${G}${B}安装完成${N}"; sep
 echo -e " URL: ${C}http://${ip_addr}:${port_host}${N}"
 echo -e " 账号: nbpanel / Np123456"
 echo -e " 数据: ${data_dir}"
 echo -e " 管理: docker {start|stop|restart} $SERVICE_NAME"
 sep; echo
}

# ---------- Uninstall ----------
uninstall_binary() {
 [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] || { warn "二进制版未安装"; return; }
 readp "确认卸载? [y/N]: " ok; [[ "$ok" =~ ^[Yy]$ ]] || return
 msg "停止服务..."; systemctl stop "$SERVICE_NAME" 2>/dev/null || true; systemctl disable "$SERVICE_NAME" 2>/dev/null || true
 rm -f "/etc/systemd/system/$SERVICE_NAME.service"; systemctl daemon-reload 2>/dev/null || true
 readp "是否删除数据目录? [y/N]: " del_data
 [[ "$del_data" =~ ^[Yy]$ ]] && { rm -rf "$INSTALL_DIR"; ok "数据目录已删除"; } || warn "保留数据目录: $INSTALL_DIR"
 rm -f "/usr/local/bin/$BINARY_NAME"; ok "二进制版已卸载"
}

uninstall_docker() {
 docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null || { warn "Docker 版未安装"; return; }
 readp "确认卸载? [y/N]: " ok; [[ "$ok" =~ ^[Yy]$ ]] || return
 msg "停止并删除容器..."; docker stop "$SERVICE_NAME" 2>/dev/null || true; docker rm "$SERVICE_NAME" 2>/dev/null || true
 readp "是否删除镜像? [y/N]: " del_img; [[ "$del_img" =~ ^[Yy]$ ]] && docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
 readp "是否删除数据目录? [y/N]: " del_data
 if [[ "$del_data" =~ ^[Yy]$ ]]; then
 local data_dir; data_dir=$(get_docker_data_dir "$SERVICE_NAME" 2>/dev/null || echo "${PWD}/nbpanel-data")
 [[ -d "$data_dir" ]] && { rm -rf "$data_dir"; ok "数据目录已删除"; }
 fi
 ok "Docker 版已卸载"
}

# ---------- Upgrade ----------
upgrade() {
 echo
 docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && upgrade_docker && return
 [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && upgrade_binary && return
 warn "未检测到已安装的 NB-Panel"
}

upgrade_docker() {
 msg "Docker 升级中..."
 local port_host data_dir; port_host=$(get_docker_port "$SERVICE_NAME"); data_dir=$(get_docker_data_dir "$SERVICE_NAME")
 msg "保留配置: 端口=$port_host, 数据目录=$data_dir"
 docker stop "$SERVICE_NAME" 2>/dev/null || true; docker rm "$SERVICE_NAME" 2>/dev/null || true
 docker pull "$DOCKER_IMAGE"; setup_docker_dirs "$data_dir"
 docker run -d --name "$SERVICE_NAME" --restart=always -p "${port_host}:4000" -e PORT=4000 \
 -v "$data_dir/logs:/app/logs" -v "$data_dir/db:/app/db" -v "$data_dir/public:/app/public" \
 "$DOCKER_IMAGE" && ok "Docker 升级完成" || err "升级失败"
}

upgrade_binary() {
 msg "二进制升级中..."; systemctl stop "$SERVICE_NAME" 2>/dev/null || true
 download_binary; extract_binary
 cp "$TEMP_DIR/$BINARY_NAME" "$INSTALL_DIR/bin/$BINARY_NAME"; chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
 systemctl start "$SERVICE_NAME" && ok "二进制升级完成" || warn "服务启动失败"
}

# ---------- Status / Logs ----------
show_status() {
 echo; echo -e " ${B}系统信息:${N}"; echo -e " OS: $OS ${VERSION_ID:-}"; echo -e " 架构: $ARCH"; echo -e " Init: $INIT_SYSTEM"; echo
 echo -e " ${B}二进制安装:${N}"
 if [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
 systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null \
 && echo -e " 状态: ${G}运行中${N}" \
 || echo -e " 状态: ${R}已停止${N}"
 else echo " 未安装"; fi
 echo; echo -e " ${B}Docker 安装:${N}"
 local running; running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep "^${SERVICE_NAME}$" || true)
 [[ -n "$running" ]] && echo -e " 状态: ${G}运行中${N} (端口: $(get_docker_port "$SERVICE_NAME"))" || echo " 未安装或已停止"
 echo
}

show_logs() {
 echo
 docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && { msg "Docker 日志 (最近50行):"; docker logs --tail 50 "$SERVICE_NAME"; return; }
 systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && { msg "Systemd 日志 (最近50行):"; journalctl -u "$SERVICE_NAME" -n 50 --no-pager; return; }
 echo "无运行实例"
 echo
}

# ---------- Menu ----------
install_menu() { echo; sep; echo -e " ${B}选择安装方式${N}"; sep; echo -e " 1. 二进制安装\n 2. Docker 安装\n 0. 返回"; sep; readp "请选择 [0-2]: " method; case "$method" in 2) install_docker;; 1) install_binary;; 0) return;; *) install_menu;; esac; }

uninstall_menu() {
 local has_bin=0 has_dkr=0; [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && has_bin=1
 docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && has_dkr=1
 [[ $has_bin -eq 0 && $has_dkr -eq 0 ]] && { warn "未检测到已安装的 NB-Panel"; return; }
 [[ $has_bin -eq 1 && $has_dkr -eq 1 ]] && { echo " 检测到两种安装方式:"; readp " 1)二进制 2)Docker 3)全部 0)返回 [0-3]: " u; case "$u" in 2) uninstall_docker;; 3) uninstall_binary; uninstall_docker;; 1) uninstall_binary;; *) return;; esac; return; }
 [[ $has_dkr -eq 1 ]] && uninstall_docker || uninstall_binary
}

main_menu() {
 while true; do echo; echo -e " ${B}${C}============================${N}"; echo -e " ${B}${C} NB-Panel v${SCRIPT_VERSION}${N}"; echo -e " ${B}${C} github.com/lima-droid/NB-Panel${N}"; echo -e " ${B}${C}============================${N}"; echo; echo " 1. 安装\n 2. 卸载\n 3. 升级\n 4. 状态\n 5. 日志\n 0. 退出"; echo; readp "请选择 [0-5]: " choice; case "$choice" in 1) install_menu;; 2) uninstall_menu;; 3) upgrade;; 4) show_status;; 5) show_logs;; 0) exit 0;; *) continue;; esac; readp "按回车键继续... " dummy; done
}

# ---------- Main ----------
main() {
 check_root "$@"; detect_system
 mkdir -p "$(dirname "$LOG_FILE")"; log "Starting NB-Panel installer v$SCRIPT_VERSION"
 case "${1:-}" in
 -b|--binary) install_binary;;
 -d|--docker) install_docker;;
 -r|--remove) uninstall_binary;;
 -R|--remove-docker) uninstall_docker;;
 -u|--upgrade) upgrade;;
 -s|--status) show_status;;
 -l|--logs) show_logs;;
 -h|--help) cat << EOF
用法: bash install.sh [选项]
  -b, --binary  二进制安装
  -d, --docker  Docker 安装
  -r, --remove  卸载二进制版
  -R, --remove-docker  卸载 Docker 版
  -u, --upgrade  升级到最新版本
  -s, --status  查看安装状态
  -l, --logs  查看日志
  -h, --help  显示帮助信息
  (无参数)  交互菜单
EOF
 exit 0;;
 *) main_menu;;
 esac
}

main "$@"
