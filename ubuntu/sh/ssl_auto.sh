#!/bin/bash
# ====================================================
# 脚本：自动设置 SSL 证书共享权限（交互式输入版）
# 功能：自动检测 Nginx 和 sing-box 用户，
#       创建共享组，将用户加入组，
#       设置指定证书文件的权限，并验证读取权限。
# 用法：以 root 用户运行
#       sudo bash ssl_auto.sh
# ====================================================

set -e  # 遇到错误立即退出

# 颜色提示
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== SSL 证书共享权限自动设置工具（交互式） ===${NC}"

# ------------------- 交互输入配置 -------------------
# 共享组名称（默认 ssl-group）
default_group="ssl-group"
read -p "请输入共享组名称 [默认: $default_group]: " input_group
GROUP_NAME="${input_group:-$default_group}"
echo -e "${GREEN}共享组名称: $GROUP_NAME${NC}"

# 私钥文件路径（需确认）
while true; do
    read -p "请输入私钥文件完整路径: " PRIVKEY
    if [ -z "$PRIVKEY" ]; then
        echo -e "${RED}私钥路径不能为空，请重新输入。${NC}"
        continue
    fi
    echo "您输入的私钥路径为: $PRIVKEY"
    read -p "确认路径正确吗？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ ! -f "$PRIVKEY" ]; then
            echo -e "${RED}错误: 文件 $PRIVKEY 不存在，请重新输入。${NC}"
            continue
        fi
        break
    else
        echo -e "${YELLOW}请重新输入私钥路径。${NC}"
    fi
done

# 公钥文件路径（需确认）
while true; do
    read -p "请输入公钥文件完整路径: " PUBKEY
    if [ -z "$PUBKEY" ]; then
        echo -e "${RED}公钥路径不能为空，请重新输入。${NC}"
        continue
    fi
    echo "您输入的公钥路径为: $PUBKEY"
    read -p "确认路径正确吗？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ ! -f "$PUBKEY" ]; then
            echo -e "${RED}错误: 文件 $PUBKEY 不存在，请重新输入。${NC}"
            continue
        fi
        break
    else
        echo -e "${YELLOW}请重新输入公钥路径。${NC}"
    fi
done

# ------------------- 1. 自动检测应用用户名 -------------------
echo -e "\n${YELLOW}步骤1：自动检测 Nginx 和 sing-box 运行用户${NC}"

# 检测 Nginx 用户
NGINX_USER=""
if command -v nginx &>/dev/null; then
    NGINX_USER=$(ps aux | grep -E '[n]ginx: worker process' | awk '{print $1}' | head -1)
fi
if [ -z "$NGINX_USER" ]; then
    if id www-data &>/dev/null; then
        NGINX_USER="www-data"
    elif id nginx &>/dev/null; then
        NGINX_USER="nginx"
    fi
fi
if [ -z "$NGINX_USER" ]; then
    echo -e "${RED}错误：无法自动检测 Nginx 用户，请手动设置脚本中的 NGINX_USER 变量。${NC}"
    exit 1
fi
echo "Nginx 用户: $NGINX_USER"

# 检测 sing-box 用户
SINGBOX_USER=""
if pgrep -x "sing-box" &>/dev/null; then
    SINGBOX_USER=$(ps -o user= -p $(pgrep -x "sing-box" | head -1))
fi
if [ -z "$SINGBOX_USER" ] && id sing-box &>/dev/null; then
    SINGBOX_USER="sing-box"
fi
if [ -z "$SINGBOX_USER" ]; then
    echo -e "${RED}错误：无法自动检测 sing-box 用户，请手动设置脚本中的 SINGBOX_USER 变量。${NC}"
    exit 1
fi
echo "sing-box 用户: $SINGBOX_USER"

# ------------------- 2. 创建/确认共享组 -------------------
echo -e "\n${YELLOW}步骤2：确保共享用户组存在${NC}"

if getent group "$GROUP_NAME" >/dev/null; then
    echo "组 '$GROUP_NAME' 已存在，将直接使用。"
else
    echo "组 '$GROUP_NAME' 不存在，正在创建..."
    groupadd "$GROUP_NAME"
    echo -e "${GREEN}组 '$GROUP_NAME' 创建成功。${NC}"
fi

# ------------------- 3. 将用户加入组 -------------------
echo -e "\n${YELLOW}步骤3：将用户加入共享组${NC}"

usermod -a -G "$GROUP_NAME" "$NGINX_USER"
echo "用户 $NGINX_USER 已加入组 $GROUP_NAME"
usermod -a -G "$GROUP_NAME" "$SINGBOX_USER"
echo "用户 $SINGBOX_USER 已加入组 $GROUP_NAME"

echo -e "${GREEN}用户组添加完成。${NC}"

# ------------------- 4. 检查证书文件是否存在 -------------------
echo -e "\n${YELLOW}步骤4：检查证书文件${NC}"

for file in "$PRIVKEY" "$PUBKEY"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}错误：文件 $file 不存在，请检查路径。${NC}"
        exit 1
    fi
done
echo "所有证书文件存在。"

# ------------------- 5. 设置目录权限 -------------------
CERT_DIR=$(dirname "$PRIVKEY")
if [ -d "$CERT_DIR" ]; then
    chmod 755 "$CERT_DIR"
    echo "目录 $CERT_DIR 权限设置为 755"
else
    echo -e "${RED}错误：目录 $CERT_DIR 不存在。${NC}"
    exit 1
fi

# ------------------- 6. 设置证书文件权限 -------------------
echo -e "\n${YELLOW}步骤5：设置证书文件权限${NC}"

# 设置私钥权限：640，属主 root，属组共享组
chown root:"$GROUP_NAME" "$PRIVKEY"
chmod 640 "$PRIVKEY"
echo "私钥 $PRIVKEY 权限已设置为 640，属组 $GROUP_NAME"

# 设置公钥权限：644，属主 root，属组 root
chown root:root "$PUBKEY"
chmod 644 "$PUBKEY"
echo "公钥 $PUBKEY 权限已设置为 644"

echo -e "${GREEN}文件权限设置完成。${NC}"

# ------------------- 7. 验证读取权限 -------------------
echo -e "\n${YELLOW}步骤6：验证用户是否能读取私钥${NC}"

echo "--- 私钥读取测试 ---"
if sudo -u "$NGINX_USER" cat "$PRIVKEY" >/dev/null 2>&1; then
    echo -e "${GREEN}Nginx 用户 ($NGINX_USER) 可读取私钥${NC}"
else
    echo -e "${RED}Nginx 用户 ($NGINX_USER) 读取私钥失败！${NC}"
fi

if sudo -u "$SINGBOX_USER" cat "$PRIVKEY" >/dev/null 2>&1; then
    echo -e "${GREEN}sing-box 用户 ($SINGBOX_USER) 可读取私钥${NC}"
else
    echo -e "${RED}sing-box 用户 ($SINGBOX_USER) 读取私钥失败！${NC}"
fi

echo "--- 公钥读取测试 ---"
if sudo -u "$NGINX_USER" cat "$PUBKEY" >/dev/null 2>&1; then
    echo -e "${GREEN}Nginx 用户 ($NGINX_USER) 可读取公钥${NC}"
else
    echo -e "${RED}Nginx 用户 ($NGINX_USER) 读取公钥失败！${NC}"
fi

if sudo -u "$SINGBOX_USER" cat "$PUBKEY" >/dev/null 2>&1; then
    echo -e "${GREEN}sing-box 用户 ($SINGBOX_USER) 可读取公钥${NC}"
else
    echo -e "${RED}sing-box 用户 ($SINGBOX_USER) 读取公钥失败！${NC}"
fi

# ------------------- 8. 重启服务 -------------------
echo -e "\n${YELLOW}步骤7：重启服务使组权限生效${NC}"
echo "正在重启 Nginx 和 sing-box 服务..."

if systemctl restart nginx; then
    echo "Nginx 重启成功。"
else
    echo -e "${RED}Nginx 重启失败，请手动检查。${NC}"
fi

if systemctl restart sing-box; then
    echo "sing-box 重启成功。"
else
    echo -e "${RED}sing-box 重启失败，请手动检查。${NC}"
fi

sleep 2
echo -e "\n${GREEN}服务状态：${NC}"
systemctl status nginx --no-pager | head -5
systemctl status sing-box --no-pager | head -5

# ------------------- 打印完成结果 -------------------
echo -e "\n${GREEN}========== 操作完成 ==========${NC}"
echo -e "共享组名称: ${YELLOW}$GROUP_NAME${NC}"
echo -e "私钥文件:   ${YELLOW}$PRIVKEY${NC}"
echo -e "公钥文件:   ${YELLOW}$PUBKEY${NC}"
echo -e "${GREEN}所有步骤执行完毕，请检查上方验证结果。${NC}"
