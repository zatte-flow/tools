#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本（例如 sudo bash $0）"
    exit 1
fi

echo "=== ZeroTier 零端口暴露配置脚本 ==="

# 1. 安装 ZeroTier
if ! command -v zerotier-cli &> /dev/null; then
    echo "正在安装 ZeroTier..."
    curl -s https://install.zerotier.com | bash
    echo "安装完成。"
else
    echo "ZeroTier 已安装，跳过安装步骤。"
fi

# 2. 创建零端口暴露配置文件
CONFIG_FILE="/var/lib/zerotier-one/local.conf"
echo "正在创建配置文件: $CONFIG_FILE"
cat > "$CONFIG_FILE" <<EOF
{
  "settings": {
    "primaryPort": 9993,
    "secondaryPort": 0,
    "tertiaryPort": 0,
    "allowSecondaryPort": false,
    "portMappingEnabled": false,
    "forceTcpRelay": true,
    "allowTcpFallbackRelay": true,
    "allowManagementFrom": ["127.0.0.1"]
  }
}
EOF
echo "配置文件已写入。"

# 3. 重启 ZeroTier 服务
echo "正在重启 ZeroTier 服务..."
systemctl restart zerotier-one
sleep 2

# 4. 确保 UFW 已安装并启用
if ! command -v ufw &> /dev/null; then
    echo "UFW 未安装，正在安装..."
    apt update && apt install ufw -y
fi

# 启用 UFW（如果未启用）
if ! ufw status | grep -q "Status: active"; then
    echo "正在启用 UFW（默认拒绝入站，允许出站）..."
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
fi

# 5. 添加防火墙规则，彻底封锁 9993 端口（入站+出站）
echo "正在添加 UFW 规则，封锁所有 9993 端口..."

# 删除可能存在的旧规则（避免重复）
ufw delete deny 9993/tcp 2>/dev/null || true
ufw delete deny 9993/udp 2>/dev/null || true
ufw delete deny out 9993/udp 2>/dev/null || true

# 添加新规则
ufw deny in 9993/tcp      # 阻止外部访问 TCP 管理端口
ufw deny in 9993/udp      # 阻止外部访问 UDP 直连端口
ufw deny out 9993/udp     # 阻止出站 UDP 直连尝试（可选，但符合“关闭所有”的要求）

# 6. 重新加载 UFW
ufw reload
echo "UFW 规则已生效。"

# 7. 提示输入网络 ID
echo ""
read -p "请输入您在 ZeroTier Central 创建的网络 ID: " NETWORK_ID
if [ -z "$NETWORK_ID" ]; then
    echo "错误：网络 ID 不能为空。"
    exit 1
fi

# 8. 加入网络
echo "正在加入网络 $NETWORK_ID ..."
zerotier-cli join "$NETWORK_ID"

# 9. 确保 allowManaged=1（自动分配 IP）
zerotier-cli set "$NETWORK_ID" allowManaged=1

# 10. 提示用户授权
echo ""
echo "================================================="
echo "请在浏览器中登录 https://my.zerotier.com"
echo "进入网络 $NETWORK_ID 的详情页面，"
echo "找到刚刚加入的设备（状态为 ACCESS_DENIED），"
echo "勾选前面的复选框进行授权。"
echo "================================================="
echo "脚本执行完毕。"
echo ""
echo "验证："
echo "  sudo ss -ulnp | grep 9993   # 应无 UDP 监听"
echo "  sudo ufw status             # 应显示 9993 端口被阻止"
echo "  sudo zerotier-cli peers     # 应全部显示 RELAY"
