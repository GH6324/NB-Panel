#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -eEuo pipefail

# 错误处理
trap 'error_handler $LINENO $?' ERR
trap 'cleanup_temp' EXIT

# 全局变量
readonly VERSION="3.4.4"
readonly INSTALL_DIR="/opt/nodepassdash"
readonly BINARY_NAME="nodepassdash"
readonly SERVICE_NAME="nodepassdash"
readonly DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"
readonly TEMP_DIR="/tmp/nbpanel_$$"
readonly LOG_FILE="/tmp/nbpanel_install.log"

# 颜色定义（兼容性改进）
if [[ -t 1 ]]; then
    readonly ESC=$(printf '\033')
    readonly R="${ESC}[31m"
    readonly G="${ESC}[32m"
    readonly Y="${ESC}[33m"
    readonly C="${ESC}[36m"
    readonly B="${ESC}[1m"
    readonly N="${ESC}[0m"
else
    readonly R="" G="" Y="" C="" B="" N=""
fi

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

error_handler() {
    local line=$1
    local code=$2
    echo -e " ${R}✗${N} 安装中断 (行号: $line, 错误码: $code)" >&2
    log "ERROR at line $line, exit code $code"
    exit 1
}

cleanup_temp() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# 增强版消息函数
msg()   { echo -e " ${B}${C}::${N}${B} $*${N}"; log "INFO: $*"; }
ok()    { echo -e " ${G}✓${N} $*"; log "OK: $*"; }
warn()  { echo -e " ${Y}⚠${N} $*" >&2; log "WARN: $*"; }
err()   { echo -e " ${R}✗${N} $*" >&2; log "ERROR: $*"; exit 1; }
sep()   { echo -e " ${C}────────────────────────────────────────────${N}"; }

# 安全读取输入
readp() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local input
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$(echo -e " $prompt [$default]: ")" input
            input="${input:-$default}"
        else
            read -p "$(echo -e " $prompt: ")" input
        fi
        
        # 验证非空输入（除非允许空）
        if [[ -z "$input" && -z "$default" && "$3" != "allow_empty" ]]; then
            warn "输入不能为空"
            continue
        fi
        break
    done
    
    eval "$var_name=\"\$input\""
}

# 增强版 root 检查
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

# 检测包管理器
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 安装依赖
install_dependencies() {
    local missing_deps=()
    local pkg_manager
    
    for cmd in curl wget tar systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    [[ ${#missing_deps[@]} -eq 0 ]] && return
    
    warn "缺少依赖: ${missing_deps[*]}"
    pkg_manager=$(detect_pkg_manager)
    
    case $pkg_manager in
        apt)
            msg "使用 apt 安装依赖..."
            apt-get update -qq
            apt-get install -y -qq curl wget tar systemd || warn "依赖安装失败"
            ;;
        yum|dnf)
            msg "使用 $pkg_manager 安装依赖..."
            $pkg_manager install -y curl wget tar systemd || warn "依赖安装失败"
            ;;
        pacman)
            msg "使用 pacman 安装依赖..."
            pacman -S --noconfirm curl wget tar systemd || warn "依赖安装失败"
            ;;
        zypper)
            msg "使用 zypper 安装依赖..."
            zypper install -y curl wget tar systemd || warn "依赖安装失败"
            ;;
        *)
            warn "无法自动安装依赖，请手动安装: curl, wget, tar, systemd"
            ;;
    esac
}

# 检测系统信息
detect_system() {
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        OS=$(uname -s)
    fi
    
    # 检测架构
    case "$(uname -m)" in
        x86_64|amd64) ARCH="Linux_x86_64" ;;
        aarch64|arm64) ARCH="Linux_arm64" ;;
        armv7l|armhf) ARCH="Linux_armv7" ;;
        i386|i686) ARCH="Linux_i386" ;;
        *) err "不支持的架构: $(uname -m)" ;;
    esac
    
    # 检测 init 系统
    if [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then
        INIT_SYSTEM="systemd"
    elif [[ -f /sbin/openrc ]]; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="other"
        warn "非 systemd 系统，服务管理可能受限"
    fi
    
    log "System: $OS $VERSION_ID, Arch: $ARCH, Init: $INIT_SYSTEM"
}

# 增强版下载函数
download_file() {
    local url="$1"
    local dest="$2"
    local retries=3
    local timeout=30
    
    msg "下载: $(basename "$url")"
    
    for ((i=1; i<=retries; i++)); do
        if command -v curl &>/dev/null; then
            if curl -fSL --connect-timeout "$timeout" --max-time "$timeout" --retry 2 -o "$dest" "$url" 2>/dev/null; then
                return 0
            fi
        elif command -v wget &>/dev/null; then
            if wget --timeout="$timeout" --tries=2 -q -O "$dest" "$url"; then
                return 0
            fi
        else
            err "需要 curl 或 wget 来下载文件"
        fi
        
        if [[ $i -lt $retries ]]; then
            warn "下载失败，重试 $((retries - i)) 次..."
            sleep 2
        fi
    done
    
    err "下载失败: $url"
}

# 获取公网 IP
get_public_ip() {
    local ip=""
    local ip_services=(
        "https://ipv4.ip.sb"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me/ip"
    )
    
    for service in "${ip_services[@]}"; do
        if ip=$(curl -s --max-time 5 --connect-timeout 3 "$service" 2>/dev/null); then
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    # 尝试获取本地 IP
    ip=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    echo "${ip:-localhost}"
}

# 验证端口是否可用
check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tuln | grep -q ":$port " && return 1
    elif command -v netstat &>/dev/null; then
        netstat -tuln | grep -q ":$port " && return 1
    elif command -v lsof &>/dev/null; then
        lsof -i ":$port" &>/dev/null && return 1
    fi
    return 0
}

# ---------- Binary Install ----------
download_binary() {
    local url="https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_${ARCH}.tar.gz"
    dest="$TEMP_DIR/nbpanel.tar.gz"
    
    mkdir -p "$TEMP_DIR"
    download_file "$url" "$dest"
}

install_binary() {
    local dest_port ip_addr cert_path key_path tls_args=""
    
    # 检查已存在的安装
    if [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
        warn "检测到已安装的二进制版本"
        readp "是否覆盖安装? [y/N]: " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    install_dependencies
    download_binary
    
    echo
    sep
    echo -e " ${B}二进制安装${N}"
    sep
    
    # 端口配置
    while true; do
        readp "监听端口" dest_port "4000"
        if ! [[ "$dest_port" =~ ^[0-9]+$ ]] || [[ "$dest_port" -lt 1 ]] || [[ "$dest_port" -gt 65535 ]]; then
            warn "端口号必须在 1-65535 之间"
        elif ! check_port "$dest_port"; then
            warn "端口 $dest_port 已被占用"
        else
            break
        fi
    done
    
    # HTTPS 配置
    readp "启用 HTTPS? [y/N]: " https
    if [[ "$https" =~ ^[Yy]$ ]]; then
        while true; do
            readp "TLS 证书路径" cert_path "" allow_empty
            readp "TLS 私钥路径" key_path "" allow_empty
            if [[ -n "$cert_path" && -n "$key_path" ]]; then
                [[ -f "$cert_path" ]] || err "证书文件不存在: $cert_path"
                [[ -f "$key_path" ]] || err "私钥文件不存在: $key_path"
                tls_args=" --cert $cert_path --key $key_path"
                break
            else
                warn "证书和私钥路径不能为空"
            fi
        done
    fi
    
    echo
    readp "确认安装? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }
    
    ip_addr=$(get_public_ip)
    
    # 创建用户
    msg "创建系统用户..."
    if ! id nodepass &>/dev/null; then
        useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass 2>/dev/null || \
        useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin nodepass 2>/dev/null || \
        err "无法创建系统用户"
    fi
    
    # 创建目录
    msg "创建目录..."
    mkdir -p "$INSTALL_DIR"/{bin,db,logs,certs}
    
    # 安装二进制
    msg "安装二进制文件..."
    cp "$TEMP_DIR/$BINARY_NAME" "$INSTALL_DIR/bin/$BINARY_NAME"
    chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
    chown root:root "$INSTALL_DIR/bin/$BINARY_NAME"
    ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" "/usr/local/bin/$BINARY_NAME"
    
    # 配置文件
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
    
    chown -R nodepass:nodepass "$INSTALL_DIR"/{db,logs,certs} 2>/dev/null || true
    
    # 注册服务
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
        
        systemctl daemon-reload
        systemctl enable --quiet "$SERVICE_NAME" 2>/dev/null || warn "无法启用服务"
        systemctl start "$SERVICE_NAME" || warn "服务启动失败"
    else
        warn "非 systemd 系统，请手动启动服务"
    fi
    
    local proto="http"
    [[ "$https" =~ ^[Yy]$ ]] && proto="https"
    
    echo
    sep
    echo -e " ${G}${B}安装完成${N}"
    sep
    echo -e "   ${B}URL:${N}     ${C}${proto}://${ip_addr}:${dest_port}${N}"
    echo -e "   ${B}账号:${N}    nbpanel / Np123456"
    echo -e "   ${B}路径:${N}    $INSTALL_DIR/bin/$BINARY_NAME"
    echo -e "   ${B}配置:${N}    $INSTALL_DIR/config.env"
    
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo -e "   ${B}服务:${N}    systemctl {start|stop|restart} $SERVICE_NAME"
    fi
    sep
    echo
}

# ---------- Docker Install ----------
install_docker() {
    if ! command -v docker &>/dev/null; then
        msg "Docker 未安装，尝试自动安装..."
        curl -fsSL https://get.docker.com | bash || err "Docker 安装失败"
    fi
    
    local port_host data_dir
    
    # 检查已存在的容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        warn "检测到已存在的 Docker 容器"
        readp "是否重新安装? [y/N]: " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
        docker rm -f "$SERVICE_NAME" 2>/dev/null
    fi
    
    echo
    sep
    echo -e " ${B}Docker 安装${N}"
    sep
    
    while true; do
        readp "映射端口" port_host "4000"
        if ! [[ "$port_host" =~ ^[0-9]+$ ]] || [[ "$port_host" -lt 1 ]] || [[ "$port_host" -gt 65535 ]]; then
            warn "端口号必须在 1-65535 之间"
        else
            break
        fi
    done
    
    local default_data_dir="${PWD}/nbpanel-data"
    readp "数据目录" data_dir "$default_data_dir"
    data_dir="${data_dir:-$default_data_dir}"
    
    echo
    readp "确认安装? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }
    
    ip_addr=$(get_public_ip)
    
    mkdir -p "$data_dir"/{logs,public,db}
    chmod 777 "$data_dir"/{logs,public,db} 2>/dev/null || true
    
    msg "拉取 Docker 镜像..."
    docker pull "$DOCKER_IMAGE" || err "镜像拉取失败"
    
    msg "启动容器..."
    if ! docker run -d \
        --name "$SERVICE_NAME" \
        --restart=always \
        -p "${port_host}:4000" \
        -e PORT=4000 \
        -v "$data_dir/logs:/app/logs" \
        -v "$data_dir/db:/app/db" \
        -v "$data_dir/public:/app/public" \
        "$DOCKER_IMAGE"; then
        err "容器启动失败"
    fi
    
    echo
    sep
    echo -e " ${G}${B}安装完成${N}"
    sep
    echo -e "   ${B}URL:${N}     ${C}http://${ip_addr}:${port_host}${N}"
    echo -e "   ${B}账号:${N} nbpanel / Np123456"
    echo -e "   ${B}数据:${N}    ${data_dir}"
    echo -e "   ${B}管理:${N}    docker {start|stop|restart} $SERVICE_NAME"
    sep
    echo
}

# ---------- Uninstall ----------
uninstall_binary() {
    if [[ ! -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
        warn "二进制版未安装"
        return
    fi
    
    readp "确认卸载? [y/N]: " ok
    [[ "$ok" =~ ^[Yy]$ ]] || return
    
    msg "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload 2>/dev/null || true
    
    readp "是否删除数据目录? [y/N]: " del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        ok "数据目录已删除"
    else
        warn "保留数据目录: $INSTALL_DIR"
    fi
    
    rm -f "/usr/local/bin/$BINARY_NAME"
    ok "二进制版已卸载"
}

uninstall_docker() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        warn "Docker 版未安装"
        return
    fi
    
    readp "确认卸载? [y/N]: " ok
    [[ "$ok" =~ ^[Yy]$ ]] || return
    
    msg "停止并删除容器..."
    docker stop "$SERVICE_NAME" 2>/dev/null || true
    docker rm "$SERVICE_NAME" 2>/dev/null || true
    
    readp "是否删除镜像? [y/N]: " del_img
    if [[ "$del_img" =~ ^[Yy]$ ]]; then
        docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
    fi
    
    readp "是否删除数据目录? [y/N]: " del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        local data_dir="${DATA_DIR:-${PWD}/nbpanel-data}"
        if [[ -d "$data_dir" ]]; then
            rm -rf "$data_dir"
            ok "数据目录已删除"
        fi
    fi
    
    ok "Docker 版已卸载"
}

# ---------- Upgrade ----------
upgrade() {
    echo
    if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        upgrade_docker
    elif [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
        upgrade_binary
    else
        warn "未检测到已安装的 NB-Panel"
    fi
}

upgrade_docker() {
    msg "Docker 升级中..."
    local port_host=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
    local data_dir=$(docker inspect "$SERVICE_NAME" 2>/dev/null | grep '"Source"' | sed 's/.*"Source": "//;s/".*//' | grep nbpanel-data | head -1)
    
    port_host="${port_host:-4000}"
    data_dir="${data_dir:-${PWD}/nbpanel-data}"
    
    docker stop "$SERVICE_NAME" 2>/dev/null
    docker rm "$SERVICE_NAME" 2>/dev/null
    docker pull "$DOCKER_IMAGE"
    
    mkdir -p "$data_dir"/{logs,public,db}
    chmod 777 "$data_dir"/{logs,public,db} 2>/dev/null || true
    
    docker run -d \
        --name "$SERVICE_NAME" \
        --restart=always \
        -p "${port_host}:4000" \
        -e PORT=4000 \
        -v "$data_dir/logs:/app/logs" \
        -v "$data_dir/db:/app/db" \
        -v "$data_dir/public:/app/public" \
        "$DOCKER_IMAGE" && ok "Docker 升级完成" || err "升级失败"
}

upgrade_binary() {
    msg "二进制升级中..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    download_binary
    
    cp "$TEMP_DIR/$BINARY_NAME" "$INSTALL_DIR/bin/$BINARY_NAME"
    chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
    systemctl start "$SERVICE_NAME" && ok "二进制升级完成" || warn "服务启动失败"
}

# ---------- Status ----------
show_status() {
    echo
    echo -e " ${B}系统信息:${N}"
    echo -e "   OS: $OS ${VERSION_ID:-}"
    echo -e "   架构: $ARCH"
    echo -e "   Init: $INIT_SYSTEM"
    echo
    
    echo -e " ${B}二进制安装:${N}"
    if [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "   状态: ${G}运行中${N}"
            local port=$(grep ^PORT= "$INSTALL_DIR/config.env" 2>/dev/null | cut -d= -f2)
            echo "   端口: ${port:-4000}"
            echo "   版本: $($INSTALL_DIR/bin/$BINARY_NAME --version 2>/dev/null || echo '未知')"
        else
            echo -e "   状态: ${R}已停止${N}"
        fi
    else
        echo "   未安装"
    fi
    
    echo
    echo -e " ${B}Docker 安装:${N}"
    if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
            echo -e "   状态: ${G}运行中${N}"
            local port=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
            echo "   端口: ${port:-4000}"
            echo "   镜像: $(docker inspect "$SERVICE_NAME" --format='{{.Config.Image}}' 2>/dev/null)"
        else
            echo -e "   状态: ${R}已停止${N}"
        fi
    else
        echo "   未安装"
    fi
    echo
}

# ---------- Logs ----------
show_logs() {
    echo
    if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        msg "Docker 日志 (最近50行):"
        docker logs --tail 50 "$SERVICE_NAME"
    elif systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        msg "Systemd 日志 (最近50行):"
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    else
        echo "无运行实例"
    fi
    echo
}

# ---------- Menu ----------
install_menu() {
    echo
    sep
    echo -e " ${B}选择安装方式${N}"
    sep
    echo -e "   ${B}1${N}. 二进制安装"
    echo -e "   ${B}2${N}. Docker 安装"
    echo -e "   ${B}0${N}. 返回"
    sep
    readp "请选择 [0-2]: " method
    
    case "$method" in
        2) install_docker ;;
        1) install_binary ;;
        0) return ;;
        *) install_menu ;;
    esac
}

uninstall_menu() {
    local has_bin=0 has_dkr=0
    [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && has_bin=1
    docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && has_dkr=1
    
    if [[ $has_bin -eq 1 && $has_dkr -eq 1 ]]; then
        echo
        echo "  检测到两种安装方式:"
        echo "    1) 二进制版"
        echo "    2) Docker 版"
        echo "    3) 全部卸载"
        echo "    0) 返回"
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

main_menu() {
    while true; do
        echo
        echo -e " ${B}${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
        echo -e " ${B}${C}  NB-Panel 管理脚本 v${VERSION}${N}"
        echo -e " ${B}${C}  github.com/lima-droid/NB-Panel${N}"
        echo -e " ${B}${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
        echo
        echo "    1. 安装"
        echo "    2. 卸载"
        echo "    3. 升级"
        echo "    4. 状态"
        echo "    5. 日志"
        echo "    0. 退出"
        echo
        readp "请选择 [0-5]: " choice
        
        case "$choice" in
            1) install_menu ;;
            2) uninstall_menu ;;
            3) upgrade ;;
            4) show_status ;;
            5) show_logs ;;
            0) exit 0 ;;
            *) ;;
        esac
        
        echo
        readp "按回车键继续... " dummy
    done
}

# ---------- Main Entry ----------
main() {
    check_root "$@"
    detect_system
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    log "Starting NB-Panel installer v$VERSION"
    
    case "${1:-}" in
        -b|--binary) install_binary ;;
        -d|--docker) install_docker ;;
        -r|--remove) uninstall_binary ;;
        -R|--remove-docker) uninstall_docker ;;
        -u|--upgrade) upgrade ;;
        -s|--status) show_status ;;
        -l|--logs) show_logs ;;
        -h|--help)
            cat << EOF
用法: bash install.sh [选项]

选项:
  -b, --binary          二进制安装
  -d, --docker          Docker 安装
  -r, --remove          卸载二进制版
  -R, --remove-docker   卸载 Docker 版
  -u, --upgrade         升级到最新版本
  -s, --status          查看安装状态
  -l, --logs            查看日志
  -h, --help            显示帮助信息
  (无参数)              交互菜单

示例:
  sudo bash install.sh           # 交互菜单
  sudo bash install.sh -b        # 二进制安装
  sudo bash install.sh -d        # Docker 安装
EOF
            exit 0
            ;;
        *) main_menu ;;
    esac
}

main "$@"
