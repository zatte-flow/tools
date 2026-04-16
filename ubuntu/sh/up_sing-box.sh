#!/bin/bash
set -e

# ========== 颜色输出 ==========
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 显示帮助 ==========
show_help() {
    cat << EOF
用法: $0 [版本号]

示例:
  $0               # 自动查询最新版本，交互式选择安装
  $0 1.13.8        # 直接安装指定版本
  $0 --help        # 显示此帮助

版本号格式: x.y.z (例如 1.13.8)
EOF
}

# ========== 检查 root 权限 ==========
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 权限运行此脚本（sudo $0）${NC}"
        exit 1
    fi
}

# ========== 检查必要命令 ==========
check_commands() {
    for cmd in wget tar systemctl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}错误：未找到命令 '$cmd'，请先安装${NC}"
            exit 1
        fi
    done
}

# ========== 获取当前已安装版本 ==========
get_current_version() {
    if [[ -f /usr/bin/sing-box ]]; then
        local version
        version=$(/usr/bin/sing-box version 2>/dev/null | grep -oP 'sing-box version \K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "未知"
        fi
    else
        echo "未安装"
    fi
}

# ========== 查询最新版本（从 GitHub API） ==========
get_latest_version() {
    # 所有提示信息输出到 stderr，避免污染 stdout（stdout 只输出版本号）
    echo -e "${BLUE}>>> 正在查询最新版本 ...${NC}" >&2
    local latest
    latest=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -o '"tag_name": *"[^"]*"' | sed 's/.*"v\([^"]*\)"/\1/')
    if [[ -z "$latest" ]]; then
        echo -e "${RED}错误：无法获取最新版本，请检查网络或 GitHub API 限制${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}最新版本: v${latest}${NC}" >&2
    echo "$latest"
}

# ========== 版本号格式校验 ==========
validate_version() {
    local ver="$1"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误：版本号格式应为 x.y.z，例如 1.13.8，您输入的是 '$ver'${NC}"
        return 1
    fi
    return 0
}

# ========== 安装指定版本 ==========
install_version() {
    local VERSION="$1"
    local DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-amd64.tar.gz"
    local TEMP_DIR=$(mktemp -d)
    local BACKUP_NAME="/usr/bin/sing-box=="
    local TARGET_BIN="/usr/bin/sing-box"

    echo -e "${GREEN}>>> 开始下载 Sing-box v${VERSION} ...${NC}"
    wget -q --show-progress -P "$TEMP_DIR" "$DOWNLOAD_URL"
    local TAR_FILE="$TEMP_DIR/sing-box-${VERSION}-linux-amd64.tar.gz"

    echo -e "${GREEN}>>> 解压到临时目录 ...${NC}"
    tar -xzf "$TAR_FILE" -C "$TEMP_DIR"
    local EXTRACTED_DIR="$TEMP_DIR/sing-box-${VERSION}-linux-amd64"
    local NEW_BIN="$EXTRACTED_DIR/sing-box"

    if [[ ! -f "$NEW_BIN" ]]; then
        echo -e "${RED}错误：解压后未找到 sing-box 可执行文件${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # 备份旧文件
    if [[ -f "$BACKUP_NAME" ]]; then
        echo -e "${GREEN}>>> 删除旧备份 $BACKUP_NAME ...${NC}"
        rm -f "$BACKUP_NAME"
    fi
    if [[ -f "$TARGET_BIN" ]]; then
        echo -e "${GREEN}>>> 备份当前版本到 $BACKUP_NAME ...${NC}"
        mv "$TARGET_BIN" "$BACKUP_NAME"
    fi

    echo -e "${GREEN}>>> 移动新版本到 $TARGET_BIN ...${NC}"
    mv "$NEW_BIN" "$TARGET_BIN"

    echo -e "${GREEN}>>> 设置权限和所有者 ...${NC}"
    if ! getent group sing-box >/dev/null; then
        groupadd -r sing-box
    fi
    chown root:sing-box "$TARGET_BIN"
    chmod 750 "$TARGET_BIN"

    # 显示版本
    echo -e "${GREEN}>>> 新安装的 sing-box 版本信息：${NC}"
    $TARGET_BIN version || echo -e "${YELLOW}警告：无法获取版本信息${NC}"

    # 清理临时目录
    echo -e "${GREEN}>>> 清理临时目录 ...${NC}"
    rm -rf "$TEMP_DIR"

    # 重启服务
    echo -e "${YELLOW}>>> 重启 sing-box 服务 ...${NC}"
    systemctl restart sing-box || echo -e "${RED}警告：重启 sing-box 失败${NC}"
    echo -e "${YELLOW}>>> 重启 nginx 服务 ...${NC}"
    systemctl restart nginx || echo -e "${RED}警告：重启 nginx 失败${NC}"

    # 显示服务状态
    echo -e "${GREEN}>>> 服务状态：${NC}"
    echo -e "${GREEN}--- sing-box 状态 ---${NC}"
    systemctl status sing-box --no-pager -l || echo -e "${RED}sing-box 状态获取失败${NC}"
    echo ""
    echo -e "${GREEN}--- nginx 状态 ---${NC}"
    systemctl status nginx --no-pager -l || echo -e "${RED}nginx 状态获取失败${NC}"

    echo -e "${GREEN}✅ 全部操作完成！Sing-box v${VERSION} 已生效。${NC}"
}

# ========== 交互式安装（无参数时） ==========
interactive_install() {
    # 获取当前版本
    CURRENT=$(get_current_version)
    echo -e "${BLUE}当前已安装版本: ${YELLOW}${CURRENT}${NC}"

    # 获取最新版本（提示信息会输出到 stderr，不会干扰变量）
    LATEST=$(get_latest_version)

    # 比较当前版本与最新版本
    if [[ "$CURRENT" == "$LATEST" ]]; then
        echo -e "${YELLOW}⚠️ 当前版本已是最新版本 v${LATEST}${NC}"
        echo -e -n "${YELLOW}是否重新安装？[y/N]: ${NC}"
        read -r reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}已取消安装。${NC}"
            exit 0
        fi
        # 用户选择重新安装，直接安装最新版
        install_version "$LATEST"
        return
    fi

    # 正常情况：最新版与当前不同
    echo -e "${YELLOW}请选择要安装的版本：${NC}"
    echo -e "  [1] 安装最新版 v${LATEST} (推荐)"
    echo -e "  [2] 安装指定版本 (手动输入版本号)"
    echo -e "  [3] 退出"
    echo -e -n "${BLUE}请输入选项 [1-3] (默认: 1): ${NC}"
    read -r choice

    case "$choice" in
        1|"")
            echo -e "${GREEN}将安装最新版 v${LATEST}${NC}"
            install_version "$LATEST"
            ;;
        2)
            echo -e -n "${BLUE}请输入要安装的版本号 (格式如 1.13.8): ${NC}"
            read -r user_version
            if validate_version "$user_version"; then
                install_version "$user_version"
            else
                echo -e "${RED}版本号格式错误，退出安装。${NC}"
                exit 1
            fi
            ;;
        3)
            echo -e "${BLUE}已退出。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，退出。${NC}"
            exit 1
            ;;
    esac
}

# ========== 主逻辑 ==========
main() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
        exit 0
    fi

    check_root
    check_commands

    if [[ -n "$1" ]]; then
        validate_version "$1" || exit 1
        install_version "$1"
    else
        interactive_install
    fi
}

main "$@"
