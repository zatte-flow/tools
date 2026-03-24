#!/bin/bash
# setup_nginx_runtime_dir.sh
# 为 nginx 服务配置 RuntimeDirectory，自动创建 /run/proxy/nginx 目录并设置权限
# 需要以 root 权限运行

set -e  # 遇到错误立即退出

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本 (sudo $0)"
    exit 1
fi

# 定义路径
OVERRIDE_DIR="/etc/systemd/system/nginx.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"

# 检查 nginx 服务是否存在
if ! systemctl list-unit-files | grep -q "^nginx.service"; then
    echo "错误：未找到 nginx.service，请先安装 nginx。"
    exit 1
fi

# 创建目录
mkdir -p "$OVERRIDE_DIR"

# 检查是否已存在 override 文件，若存在则询问是否覆盖
if [ -f "$OVERRIDE_FILE" ]; then
    echo "警告：$OVERRIDE_FILE 已存在。"
    read -p "是否覆盖？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
fi

# 写入配置
cat > "$OVERRIDE_FILE" << 'EOF'
[Service]
RuntimeDirectory=proxy/nginx
RuntimeDirectoryMode=0750
RuntimeDirectoryOwner=www-data
RuntimeDirectoryGroup=www-data
EOF

echo "已写入 $OVERRIDE_FILE"

# 重新加载 systemd 配置
systemctl daemon-reload
echo "systemd 配置已重新加载"

# 重启 nginx 服务
systemctl restart nginx
echo "nginx 服务已重启"

# 等待一小段时间，检查服务状态
sleep 2
if systemctl is-active --quiet nginx; then
    echo "✓ nginx 服务运行正常"
    echo "目录已创建："
    ls -ld /run/proxy/nginx 2>/dev/null || echo "（目录将在服务启动时自动创建）"
else
    echo "✗ nginx 服务启动失败，请检查日志："
    systemctl status nginx --no-pager
    exit 1
fi
