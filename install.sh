#!/bin/bash
#
# Komari Safe - 精简安全版安装脚本
# 纯监控面板，无远程控制功能
# 仓库: https://github.com/bldcn/komari-safe
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "$1"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_step()  { echo -e "${YELLOW}$1${NC}"; }

INSTALL_DIR="/opt/komari-safe"
SERVICE_NAME="komari-safe"
BINARY_PATH="$INSTALL_DIR/komari"
DEFAULT_PORT="25774"
LISTEN_PORT=""
REPO="https://github.com/bldcn/komari-safe"

is_non_interactive() {
    # 安全检测：stdin 不是终端 或 显式传了 --yes
    [ ! -t 0 ] && return 0
    [ "$NONINTERACTIVE" = "1" ] && return 0
    return 1
}

show_banner() {
    echo "=============================================================="
    echo "       Komari Safe - 精简监控面板安装脚本"
    echo "       已移除 terminal / exec / clip / CF tunnel / Nezha"
    echo "       $REPO"
    echo "=============================================================="
    echo
}

check_root() {
    [ "$EUID" -ne 0 ] && { log_error "请使用 root 权限运行"; exit 1; }
}

check_systemd() { command -v systemctl >/dev/null 2>&1; }

detect_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        i386|i686) echo "386" ;;
        riscv64) echo "riscv64" ;;
        *) log_error "不支持的架构"; exit 1 ;;
    esac
}

ask_port() {
    if is_non_interactive; then
        LISTEN_PORT="$DEFAULT_PORT"
        log_info "非交互模式，使用默认端口: $DEFAULT_PORT"
        return
    fi
    while true; do
        read -p "监听端口 [$DEFAULT_PORT]: " p
        [ -z "$p" ] && { LISTEN_PORT="$DEFAULT_PORT"; break; }
        [[ "$p" =~ ^[0-9]+$ ]] && ((p>=1 && p<=65535)) && { LISTEN_PORT="$p"; break; }
        log_error "无效端口 (1-65535)"
    done
}

install_deps() {
    log_step "安装依赖 (git, curl)..."
    if command -v apt >/dev/null 2>&1; then
        apt update -qq && apt install -y git curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git curl
    elif command -v apk >/dev/null 2>&1; then
        apk add git curl
    else
        log_error "未找到包管理器 (apt/yum/apk)"; exit 1
    fi
}

ensure_go() {
    local need="1.21"
    if command -v go >/dev/null 2>&1; then
        local ver=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+' | head -1)
        if [ -n "$ver" ] && [ "$(printf '%s\n' "$need" "$ver" | sort -V | head -1)" = "$need" ]; then
            log_info "Go $ver 满足要求 (>= $need)"
            return 0
        fi
        log_info "Go $ver 版本过低，需要 >= $need，正在升级..."
    else
        log_info "未检测到 Go，正在安装..."
    fi

    local go_ver="1.22.1"
    local arch=$(uname -m)
    case $arch in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) log_error "不支持的架构: $arch"; exit 1 ;;
    esac

    local url="https://go.dev/dl/go${go_ver}.linux-${arch}.tar.gz"
    log_step "下载 Go $go_ver ..."
    curl -fsSL "$url" -o /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    # Add to PATH
    export PATH=/usr/local/go/bin:$PATH
    grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null || echo 'export PATH=/usr/local/go/bin:$PATH' >> /etc/profile

    log_success "Go $(go version) 安装完成"
}

install_from_source() {
    set -e
    log_step "从源码编译安装..."
    ask_port
    install_deps
    ensure_go

    mkdir -p "$INSTALL_DIR"

    BUILD_DIR=$(mktemp -d)
    trap "rm -rf $BUILD_DIR" EXIT

    log_step "克隆 $REPO ..."
    git clone --depth 1 "$REPO" "$BUILD_DIR"

    log_step "编译中 (约 1-3 分钟)..."
    cd "$BUILD_DIR"
    go mod tidy
    go build -o "$BINARY_PATH" .

    chmod +x "$BINARY_PATH"
    log_success "编译完成: $BINARY_PATH"

    if ! check_systemd; then
        log_info "手动运行: $BINARY_PATH server -l 0.0.0.0:$LISTEN_PORT"
        return
    fi

    create_service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "服务启动成功"
        local pass=$(journalctl -u "$SERVICE_NAME" --since "1 min ago" 2>/dev/null | grep "admin account created" | tail -1 | sed 's/.*admin account created.//' || true)
        show_access "$pass"
    else
        log_error "启动失败: journalctl -u $SERVICE_NAME -f"
    fi
}

install_binary() {
    log_step "下载二进制安装..."
    ask_port

    if ! command -v curl >/dev/null 2>&1; then
        command -v apt >/dev/null 2>&1 && { apt update -qq; apt install -y curl; }
        command -v yum >/dev/null 2>&1 && yum install -y curl
        command -v apk >/dev/null 2>&1 && apk add curl
    fi

    local arch=$(detect_arch)
    log_info "架构: $arch"
    mkdir -p "$INSTALL_DIR"

    local url="$REPO/releases/latest/download/komari-safe-linux-${arch}"
    log_step "下载 $url"
    curl -fsSL -o "$BINARY_PATH" "$url" || { log_error "下载失败，请用 source 模式: bash install.sh source"; exit 1; }

    chmod +x "$BINARY_PATH"
    log_success "安装完成"

    if ! check_systemd; then
        log_info "手动运行: $BINARY_PATH server -l 0.0.0.0:$LISTEN_PORT"
        return
    fi

    create_service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "服务启动成功"
        local pass=$(journalctl -u "$SERVICE_NAME" --since "1 min ago" 2>/dev/null | grep "admin account created" | tail -1 | sed 's/.*admin account created.//' || true)
        show_access "$pass"
    else
        log_error "启动失败: journalctl -u $SERVICE_NAME -f"
    fi
}

create_service() {
    log_step "创建 systemd 服务..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Komari Safe Monitor (security-hardened, no remote-control)
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} server -l 0.0.0.0:${LISTEN_PORT}
WorkingDirectory=${INSTALL_DIR}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    log_success "systemd 服务已创建"
}

show_access() {
    local pass="$1"
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_IP")
    echo
    log_success "=============================================="
    log_success "  Komari Safe 安装完成!"
    log_success "  地址: http://${ip}:${LISTEN_PORT}"
    if [ -n "$pass" ]; then
        log_info "  $pass"
    else
        log_info "  账号密码: journalctl -u $SERVICE_NAME | grep 'admin account'"
    fi
    log_success "=============================================="
}

uninstall() {
    check_root
    if [ ! -f "$BINARY_PATH" ]; then log_info "未安装"; return; fi
    read -p "确认卸载? (y/N): " c
    [[ ! $c =~ ^[Yy]$ ]] && return
    check_systemd && { systemctl stop "$SERVICE_NAME" 2>/dev/null; systemctl disable "$SERVICE_NAME" 2>/dev/null; rm -f "/etc/systemd/system/${SERVICE_NAME}.service"; systemctl daemon-reload; }
    rm -f "$BINARY_PATH"
    rmdir "$INSTALL_DIR" 2>/dev/null || true
    log_success "卸载完成"
}

# ====== Main ======
case "${1:-}" in
    source) check_root; show_banner; install_from_source ;;
    binary|"") check_root; show_banner; install_binary ;;
    uninstall) uninstall ;;
    status) check_systemd && systemctl status "$SERVICE_NAME" --no-pager -l || log_error "未安装 systemd" ;;
    logs)  check_systemd && journalctl -u "$SERVICE_NAME" -f --no-pager || log_error "未安装 systemd" ;;
    *) echo "用法: $0 [source|binary|uninstall|status|logs]" ;;
esac
