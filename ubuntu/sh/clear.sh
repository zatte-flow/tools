#!/bin/bash

# Ubuntu 22.04 系统清理脚本
# 需要以 root 用户或使用 sudo 权限运行

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

echo "开始 Ubuntu 22.04 系统清理..."

# 1. 清理 apt 缓存
echo "清理 apt 缓存..."
apt-get clean
apt-get autoclean

# 2. 移除不再需要的依赖包
echo "移除不再需要的依赖包..."
apt-get autoremove --purge -y

# 3. 清理旧的 snap 版本
echo "清理旧的 snap 版本..."
set -eu
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    snap remove "$snapname" --revision="$revision"
done

# 4. 清理旧的日志文件
echo "清理旧的日志文件..."
journalctl --vacuum-time=30d
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.old" -delete
find /var/log -type f -name "*.log.*" -delete
truncate -s 0 /var/log/*.log

# 5. 清理临时文件
echo "清理临时文件..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# 6. 清理缩略图缓存
echo "清理缩略图缓存..."
rm -rf ~/.cache/thumbnails/*

# 7. 清理浏览器缓存（可选，取消注释以启用）
# echo "清理浏览器缓存..."
# rm -rf ~/.cache/mozilla/firefox/*.default-release/cache/*
# rm -rf ~/.config/google-chrome/Default/Cache/*
# rm -rf ~/.config/google-chrome/Default/Code\ Cache/*

# 8. 清理旧的配置文件
echo "清理旧的配置文件..."
apt-get purge -y $(dpkg -l | awk '/^rc/ { print $2 }')

# 9. 清理旧的备份文件（可选，取消注释以启用）
# echo "清理旧的备份文件..."
# find /var/backups -type f -mtime +30 -delete

# 10. 清理下载的软件包（可选，取消注释以启用）
# echo "清理下载的软件包..."
# rm -rf /var/cache/apt/archives/*.deb

# 11. 清理 Docker 无用数据（如果安装了 Docker）
if command -v docker &> /dev/null; then
    echo "清理 Docker 无用数据..."
    docker system prune -f
fi

# 12. 清理旧的未使用内核
echo "清理旧的未使用内核..."
current_kernel=$(uname -r)
echo "当前内核版本: $current_kernel"
echo "已安装的内核版本:"
dpkg --list | grep linux-image

read -p "是否要移除旧的内核? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt-get purge -y $(dpkg --list | grep 'linux-image' | awk '{ print $2 }' | grep -v "$current_kernel" | grep -v "linux-image-generic")
    update-grub
fi

echo "清理完成!"
echo "建议重启系统以确保所有清理生效。"
