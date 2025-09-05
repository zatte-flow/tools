#!/bin/bash
# ============================================================================
#  Ubuntu 24.04 系统清理脚本
#  需要 root 或 sudo 权限执行
# ============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "请以 sudo 或 root 身份运行此脚本" >&2
   exit 1
fi

echo "========== Ubuntu 24.04 清理开始 =========="

# 1. apt 缓存与孤立包
echo "[1/10] 清理 apt 缓存与孤立包..."
apt-get clean
apt-get autoclean
apt-get autoremove --purge -y

# 2. 旧配置文件（rc 状态）
echo "[2/10] 清理已卸载包的残留配置文件..."
dpkg -l | awk '/^rc/ {print $2}' | xargs -r apt-get purge -y

# 3. snap 保留最近 2 个 revision
echo "[3/10] 清理旧 snap 版本..."
# 让系统以后只保留 2 份
snap set system refresh.retain=2
# 立即触发一次裁剪（snap 会自动删）
snap refresh

# 4. 日志轮转
echo "[4/10] 清理旧日志..."
journalctl --vacuum-time=30d --quiet
find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.log.*" \) -delete
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;

# 5. 临时目录
echo "[5/10] 清理临时文件..."
rm -rf /tmp/* /var/tmp/*

# 6. 缩略图缓存（所有用户）
echo "[6/10] 清理缩略图缓存..."
for home in /home/*; do
  [[ -d "$home/.cache/thumbnails" ]] && rm -rf "$home/.cache/thumbnails"/*
done
# 也清 root
rm -rf /root/.cache/thumbnails/*

# 7. 旧内核（保留当前+最新元包）
echo "[7/10] 清理旧内核..."
cur=$(uname -r | sed 's/-generic//')
dpkg -l | grep '^ii.*linux-image-[0-9]' |
  awk '{print $2}' |
  grep -v "$cur" |
  xargs -r apt-get purge -y
# 更新 grub 菜单
update-grub

# 8. Docker 环境（如已安装）
if command -v docker &>/dev/null; then
  echo "[8/10] 清理 Docker 无用数据..."
  docker system prune -af --volumes
fi

# 9. 可选：浏览器缓存（默认关闭，需手动取消注释）
# echo "[9/10] 清理浏览器缓存..."
# for prof in /home/*/.cache/mozilla/firefox/*.default*/cache/*; do
#   [[ -d "$prof" ]] && rm -rf "$prof"
# done
# for prof in /home/*/.config/google-chrome/Default/{Cache,"Code Cache"}; do
#   [[ -d "$prof" ]] && rm -rf "$prof"
# done

# 10. 可选：/var/cache/apt/archives 中的 deb 包
# echo "[10/10] 清理已下载的 deb 包..."
# rm -f /var/cache/apt/archives/*.deb

echo "========== 清理完成！建议重启系统 =========="
