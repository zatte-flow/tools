#!/bin/bash
# 完全删除 WARP 客户端并清除所有配置
set -e

echo "=== 开始完全删除 WARP 客户端 ==="

# 1. 停止服务（如果存在且正在运行）
if systemctl is-active --quiet warp-svc 2>/dev/null; then
    echo "→ 停止 warp-svc 服务..."
    sudo systemctl stop warp-svc
fi
if systemctl is-enabled --quiet warp-svc 2>/dev/null; then
    echo "→ 禁用 warp-svc 服务..."
    sudo systemctl disable warp-svc
fi

# 2. 卸载软件包（根据发行版选择）
if command -v apt &>/dev/null; then
    echo "→ 使用 apt 卸载 cloudflare-warp ..."
    sudo apt remove --purge -y cloudflare-warp
elif command -v yum &>/dev/null; then
    echo "→ 使用 yum 卸载 cloudflare-warp ..."
    sudo yum remove -y cloudflare-warp
elif command -v dnf &>/dev/null; then
    echo "→ 使用 dnf 卸载 cloudflare-warp ..."
    sudo dnf remove -y cloudflare-warp
else
    echo "错误：未找到支持的包管理器 (apt/yum/dnf)" >&2
    exit 1
fi

# 3. 删除残留目录
echo "→ 删除残留目录..."
sudo rm -rf /var/lib/cloudflare-warp /etc/cloudflare-warp /etc/warp-cli
rm -rf ~/.warp 2>/dev/null || true

# 4. 清理 systemd 单元文件（如果存在）
if [ -f /etc/systemd/system/warp-svc.service ]; then
    echo "→ 删除 systemd 服务文件..."
    sudo rm -f /etc/systemd/system/warp-svc.service
    sudo systemctl daemon-reload
fi

echo "=== 删除完成 ==="
echo "WARP 客户端已从系统中彻底移除。"
