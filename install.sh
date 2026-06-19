#!/bin/bash
#
# Komari Safe - 精简安全版安装脚本
# 纯监控面板，无远程控制功能
# 仓库: https://github.com/bldcn/komari-safe
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "$1"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_step() { echo -e "${YELLOW}$1${NC}"; }

INSTALL_DIR="/opt/komari-safe"
SERVICE_NAME="komari-safe"
BINARY_PATH="$INSTALL_DIR/komari"
DEFAULT_PORT="25774"
LISTEN_PORT=""
REPO="https://github.com/bldcn/komari-safe"

show_banner() {
    echo "=============================================================="
    echo "       Komari Safe - 精简监控面板安装脚本"
    echo "       已移除 terminal / exec / clip / CF tunnel / Nezha"
    echo "       $REPO"
    echo "=============================================================="
    echo
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

check_systemd() {
    command -v systemctl >/dev/null 2>&1
}

detect_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        i386|i686) echo "386" ;;
        riscv64) echo "riscv64" ;;
        *) log_error "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
}

is_installed() {
    [ -f "$BINARY_PATH" ]
}

install_deps() {
    log_step "检查并安装依赖 (git, go, curl)..."
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y git curl golang-go
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git curl golang
    elif command -v apk >/dev/null 2>&1; then
        apk add git curl go
    else
        log_error "未找到支持的包管理器 (apt/yum/apk)"
        exit 1
    fi
}

install_from_source() {
    log_step "从源码编译安装..."

    while true; do
        read -p "请输入监听端口 [默认: $DEFAULT_PORT]: " input_port
        if [[ -z "$input_port" ]]; then
            LISTEN_PORT="$DEFAULT_PORT"; break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && (( input_port >= 1 && input_port <= 65535 )); then
            LISTEN_PORT="$input_port"; break
        else
            log_error "端口号无效 (1-65535)"
        fi
    done

    install_deps

    mkdir -p "$INSTALL_DIR"

    # Clone and build
    BUILD_DIR=$(mktemp -d)
    trap "rm -rf $BUILD_DIR" EXIT

    log_step "克隆仓库..."
    git clone --depth 1 "$REPO" "$BUILD_DIR"

    log_step "编译 Komari Safe..."
    cd "$BUILD_DIR"
    go build -o "$BINARY_PATH" .

    chmod +x "$BINARY_PATH"
    log_success "编译完成: $BINARY_PATH"

    if ! check_systemd; then
        log_step "未检测到 systemd，手动运行命令:"
        echo "    $BINARY_PATH server -l 0.0.0.0:$LISTEN_PORT"
        return
    fi

    create_service "$LISTEN_PORT"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "服务启动成功"
        local pass=$(journalctl -u "$SERVICE_NAME" --since "1 min ago" 2>/dev/null | grep "admin account created" | tail -1 | sed 's/.*admin account created.//' || true)
        show_access "$pass" "$LISTEN_PORT"
    else
        log_error "服务启动失败，请查看: journalctl -u $SERVICE_NAME -f"
    fi
}

install_binary() {
    log_step "从预编译二进制安装..."

    while true; do
        read -p "请输入监听端口 [默认: $DEFAULT_PORT]: " input_port
        if [[ -z "$input_port" ]]; then
            LISTEN_PORT="$DEFAULT_PORT"; break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && (( input_port >= 1 && input_port <= 65535 )); then
            LISTEN_PORT="$input_port"; break
        else
            log_error "端口号无效 (1-65535)"
        fi
    done

    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt >/dev/null 2>&1; then apt update && apt install -y curl
        elif command -v yum >/dev/null 2>&1; then yum install -y curl
        elif command -v apk >/dev/null 2>&1; then apk add curl
        fi
    fi

    local arch=$(detect_arch)
    log_info "检测到架构: $arch"

    mkdir -p "$INSTALL_DIR"

    local file_name="komari-safe-linux-${arch}"
    local download_url="$REPO/releases/latest/download/${file_name}"

    log_step "下载 Komari Safe..."
    log_info "URL: $download_url"

    if ! curl -fsSL -o "$BINARY_PATH" "$download_url"; then
        log_error "下载失败。请确保已发布 Release，或使用源码安装模式。"
        log_info "尝试源码安装: bash $0 source"
        return 1
    fi

    chmod +x "$BINARY_PATH"
    log_success "安装完成: $BINARY_PATH"

    if ! check_systemd; then
        echo "手动运行: $BINARY_PATH server -l 0.0.0.0:$LISTEN_PORT"
        return
    fi

    create_service "$LISTEN_PORT"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "服务启动成功"
        local pass=$(journalctl -u "$SERVICE_NAME" --since "1 min ago" 2>/dev/null | grep "admin account created" | tail -1 | sed 's/.*admin account created.//' || true)
        show_access "$pass" "$LISTEN_PORT"
    else
        log_error "服务启动失败: journalctl -u $SERVICE_NAME -f"
    fi
}

create_service() {
    local port="$1"
    log_step "创建 systemd 服务..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Komari Safe Monitor (security-hardened, no remote-control)
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} server -l 0.0.0.0:${port}
WorkingDirectory=${INSTALL_DIR}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    log_success "systemd 服务已创建"
}

show_access() {
    local pass="$1"; local port="${2:-$DEFAULT_PORT}"
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_IP")
    echo
    log_success "=============================================="
    log_success "  Komari Safe 安装完成！"
    log_success "=============================================="
    echo
    log_info "  访问地址: http://${ip}:${port}"
    if [ -n "$pass" ]; then
        log_info "  $pass"
    else
        log_info "  账号密码: 查看日志 journalctl -u $SERVICE_NAME | grep 'admin account'"
    fi
    echo
    log_info "  服务管理:"
    log_info "    状态: systemctl status $SERVICE_NAME"
    log_info "    重启: systemctl restart $SERVICE_NAME"
    log_info "    停止: systemctl stop $SERVICE_NAME"
    log_info "    日志: journalctl -u $SERVICE_NAME -f"
    echo
}

uninstall() {
    log_step "卸载 Komari Safe..."
    if ! is_installed; then log_info "未安装"; return; fi
    read -p "确认卸载? (y/N): " confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return

    if check_systemd; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    rm -f "$BINARY_PATH"
    rmdir "$INSTALL_DIR" 2>/dev/null || true
    log_success "卸载完成。数据目录保留在 $INSTALL_DIR"
}

show_status() {
    if ! is_installed; then log_error "未安装"; return; fi
    if check_systemd; then systemctl status "$SERVICE_NAME" --no-pager -l; fi
}

show_logs() {
    if ! is_installed; then log_error "未安装"; return; fi
    if check_systemd; then journalctl -u "$SERVICE_NAME" -f --no-pager; fi
}

restart_service() {
    if ! is_installed; then return; fi
    if check_systemd; then systemctl restart "$SERVICE_NAME" && log_success "已重启"; fi
}

# ----- Main -----
case "${1:-}" in
    source) check_root; show_banner; install_from_source ;;
    uninstall) check_root; uninstall ;;
    status) show_status ;;
    logs) show_logs ;;
    restart) check_root; restart_service ;;
    binary|"") check_root; show_banner; install_binary ;;
    *) echo "用法: $0 [binary|source|uninstall|status|logs|restart]"; exit 1 ;;
esac
