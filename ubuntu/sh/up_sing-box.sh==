# 使用方式：
# chmod +x up_sing-box.sh
# sudo ./up_sing-box.sh 1.13.8
# =========================
#!/bin/bash
set -e  # 遇到错误立即退出

# ========== 参数检查 ==========
if [[ $# -ne 1 ]]; then
    echo "用法: $0 <版本号>"
    echo "示例: $0 1.13.8"
    exit 1
fi

VERSION="$1"
# 简单验证版本号格式（数字.数字.数字）
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误：版本号格式应为 x.y.z，例如 1.13.8"
    exit 1
fi

# ========== 配置 ==========
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-amd64.tar.gz"
TEMP_DIR=$(mktemp -d)                    # 创建临时目录
BACKUP_NAME="/usr/bin/sing-box=="        # 备份文件名
TARGET_BIN="/usr/bin/sing-box"           # 目标二进制路径

# ========== 颜色输出 ==========
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# ========== 检查权限 ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 权限运行此脚本（sudo $0）${NC}"
    exit 1
fi

# ========== 检查必要命令 ==========
for cmd in wget tar systemctl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}错误：未找到命令 '$cmd'，请先安装${NC}"
        exit 1
    fi
done

# ========== 开始执行 ==========
echo -e "${GREEN}>>> 开始下载 Sing-box v${VERSION} ...${NC}"
wget -q --show-progress -P "$TEMP_DIR" "$DOWNLOAD_URL"
TAR_FILE="$TEMP_DIR/sing-box-${VERSION}-linux-amd64.tar.gz"

echo -e "${GREEN}>>> 解压到临时目录 ...${NC}"
tar -xzf "$TAR_FILE" -C "$TEMP_DIR"
EXTRACTED_DIR="$TEMP_DIR/sing-box-${VERSION}-linux-amd64"
NEW_BIN="$EXTRACTED_DIR/sing-box"

if [[ ! -f "$NEW_BIN" ]]; then
    echo -e "${RED}错误：解压后未找到 sing-box 可执行文件${NC}"
    exit 1
fi

# ========== 处理旧文件 ==========
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
# 创建 sing-box 用户组（如果不存在）
if ! getent group sing-box >/dev/null; then
    groupadd -r sing-box
fi
chown root:sing-box "$TARGET_BIN"
chmod 750 "$TARGET_BIN"

# ========== 显示 sing-box 版本 ==========
echo -e "${GREEN}>>> 新安装的 sing-box 版本信息：${NC}"
$TARGET_BIN version || echo -e "${YELLOW}警告：无法获取版本信息，请检查二进制文件是否可执行${NC}"

# ========== 清理临时文件（下载、解压残留） ==========
echo -e "${GREEN}>>> 清理临时目录 ...${NC}"
rm -rf "$TEMP_DIR"

# ========== 重启服务并查看状态 ==========
echo -e "${YELLOW}>>> 重启 sing-box 服务 ...${NC}"
systemctl restart sing-box || echo -e "${RED}警告：重启 sing-box 失败，请检查服务是否存在${NC}"

echo -e "${YELLOW}>>> 重启 nginx 服务 ...${NC}"
systemctl restart nginx || echo -e "${RED}警告：重启 nginx 失败，请检查服务是否存在${NC}"

echo -e "${GREEN}>>> 服务状态：${NC}"
echo -e "${GREEN}--- sing-box 状态 ---${NC}"
systemctl status sing-box --no-pager -l || echo -e "${RED}sing-box 服务状态获取失败${NC}"
echo ""
echo -e "${GREEN}--- nginx 状态 ---${NC}"
systemctl status nginx --no-pager -l || echo -e "${RED}nginx 服务状态获取失败${NC}"

echo -e "${GREEN}✅ 全部操作完成！新版本 v${VERSION} 已生效。${NC}"
