#!/bin/bash
#
# Komari Safe 一键部署脚本
# 初始化 git 仓库，提交代码，推送到 GitHub
#
# 用法:
#   bash deploy.sh                              # SSH 方式推送
#   bash deploy.sh https                        # HTTPS 方式 (需要手动输入 token)
#   bash deploy.sh https <github_token>         # HTTPS + token
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "$1"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_step()  { echo -e "${YELLOW}$1${NC}"; }

# ========== 配置 ==========
GITHUB_USER="bldcn"
REPO_NAME="komari-safe"
REPO_DESC="Komari 精简安全版 - 纯监控面板，已移除全部远程控制功能 (terminal/exec/clipboard/CF tunnel/Nezha)"
REPO_VISIBILITY="public"
# ==========================

SSH_REMOTE="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
HTTPS_REMOTE="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

show_banner() {
    echo "=============================================================="
    echo "  Komari Safe 一键部署到 GitHub"
    echo "  仓库: $HTTPS_REMOTE"
    echo "  可见性: $REPO_VISIBILITY"
    echo "=============================================================="
    echo
}

check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "git 未安装，请先安装 git"
        exit 1
    fi
}

check_gh_cli() {
    if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI (gh) 未安装"
        log_info "安装方法: https://cli.github.com/"
        log_info "或手动在 GitHub 创建仓库后，使用: $REPO_DESC 作为描述"
        exit 1
    fi
}

auth_check() {
    log_step "检查 GitHub 认证..."
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI 未登录"
        log_info "请运行: gh auth login"
        log_info "然后重新执行此脚本"
        exit 1
    fi
    log_success "GitHub 认证 OK"
}

create_repo() {
    log_step "创建 GitHub 仓库: $GITHUB_USER/$REPO_NAME"
    if gh repo view "$GITHUB_USER/$REPO_NAME" >/dev/null 2>&1; then
        log_info "仓库已存在，跳过创建"
    else
        gh repo create "$GITHUB_USER/$REPO_NAME" \
            --"$REPO_VISIBILITY" \
            --description "$REPO_DESC" \
            --push \
            --source . \
            --remote origin
        log_success "仓库创建成功"
    fi
}

init_and_push() {
    local auth_method="${1:-ssh}"
    local github_token="${2:-}"

    cd "$(dirname "$0")/.." 2>/dev/null || cd "$(dirname "$0")"

    log_step "初始化 git 仓库..."

    if [ ! -d .git ]; then
        git init
        log_success "git init 完成"
    else
        log_info "git 仓库已存在"
    fi

    # 设置远端
    if [ "$auth_method" = "https" ]; then
        if [ -n "$github_token" ]; then
            REMOTE_URL="https://${github_token}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
        else
            REMOTE_URL="$HTTPS_REMOTE"
        fi
    else
        REMOTE_URL="$SSH_REMOTE"
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
    fi
    log_info "远端地址: $REMOTE_URL"

    # 添加所有文件
    log_step "添加文件..."
    git add -A

    # 检查是否有变更
    if git diff --cached --quiet 2>/dev/null; then
        # 检查是否有未跟踪文件
        if [ -z "$(git ls-files --others --exclude-standard)" ] && [ -z "$(git diff --cached --name-only)" ]; then
            log_info "没有新变更"
        fi
    fi

    # 提交
    log_step "提交代码..."
    git commit -m "Komari Safe - initial security-hardened release. Removed: terminal/exec/clipboard/CF tunnel/Nezha/v2 protocol/JS engine. Origin: komari-monitor/komari" \
" || log_info "提交可能为空或已存在"

    # 推送
    log_step "推送到 GitHub..."
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    # 确保分支名为 main
    if [ "$BRANCH" != "main" ]; then
        git branch -M main
        BRANCH="main"
    fi

    if git push -u origin "$BRANCH" 2>&1; then
        log_success "=============================================="
        log_success "  推送成功！"
        log_success "  仓库地址: $HTTPS_REMOTE"
        log_success "=============================================="
    else
        log_error "推送失败。请检查:"
        log_error "  1. 仓库是否已创建"
        log_error "  2. 认证方式是否正确"
        log_error "  3. 网络连接"
        log_info ""
        log_info "手动创建仓库:"
        log_info "  gh repo create $GITHUB_USER/$REPO_NAME --public"
        log_info ""
        log_info "手动推送:"
        log_info "  git push -u origin main"
        exit 1
    fi
}

# ====== Main ======
show_banner
check_git

case "${1:-}" in
    gh|github)
        # 使用 gh CLI 创建仓库并推送
        check_gh_cli
        auth_check
        init_and_push "ssh"
        create_repo
        log_success "全部完成！"
        ;;
    https)
        if [ -n "$2" ]; then
            log_info "使用 HTTPS + Token 方式"
            init_and_push "https" "$2"
        else
            log_info "使用 HTTPS 方式 (克隆时需要输入用户名和 token)"
            init_and_push "https"
        fi
        log_info ""
        log_info "请在 GitHub 上手动创建仓库:"
        log_info "  https://github.com/new"
        log_info "  名称: $REPO_NAME"
        log_info "  描述: $REPO_DESC"
        log_info ""
        log_info "创建后执行: git push -u origin main"
        ;;
    ssh|"")
        log_info "使用 SSH 方式"
        init_and_push "ssh"
        log_info ""
        log_info "请在 GitHub 上手动创建仓库:"
        log_info "  https://github.com/new"
        log_info "  名称: $REPO_NAME"
        log_info "  描述: $REPO_DESC"
        log_info ""
        log_info "创建后执行: git push -u origin main"
        ;;
    *)
        echo "用法: bash deploy.sh [gh|ssh|https [token]]"
        echo ""
        echo "  gh       - 使用 GitHub CLI 一键创建仓库 + 推送 (推荐)"
        echo "  ssh      - SSH 方式 (默认)"
        echo "  https    - HTTPS 方式"
        echo "  https TOKEN - HTTPS + Personal Access Token"
        exit 1
        ;;
esac
