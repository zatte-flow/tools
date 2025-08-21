#!/usr/bin/env bash
# sec-tools.sh
# 自动安装 lynis、rkhunter、chkrootkit，并设置定期自动巡检，自动修复配置问题

set -eu

LOGDIR="/var/log/weekly-sec"
SCRIPT_PATH="/usr/local/bin/weekly-sec.sh"

# 进入安全目录，避免 getcwd 报错
cd /tmp 2>/dev/null || cd /

echo "[INFO] 开始安装 lynis、rkhunter、chkrootkit..."
sudo apt-get update
sudo apt-get install -y lynis rkhunter chkrootkit

# 修复 rkhunter WEB_CMD 配置
sudo sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf 2>/dev/null || true
sudo sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf.local 2>/dev/null || true

# 修复点：精确同步SSH和rkhunter的root登录配置
SSH_ROOT_SETTING=$(sudo grep -E '^PermitRootLogin\s+(yes|prohibit-password|without-password)' /etc/ssh/sshd_config 2>/dev/null && echo "yes" || echo "no")
for RKH_CONF in /etc/rkhunter.conf /etc/rkhunter.conf.local; do
    [ -f "$RKH_CONF" ] && sudo sed -i "s/^ALLOW_SSH_ROOT_USER=.*/ALLOW_SSH_ROOT_USER=${SSH_ROOT_SETTING}/" "$RKH_CONF" 2>/dev/null || true
done

echo "[INFO] 创建自动巡检脚本..."
sudo tee "$SCRIPT_PATH" > /dev/null <<'EOF'
#!/bin/bash
cd /tmp 2>/dev/null || cd /

LOGDIR=/var/log/weekly-sec
sudo mkdir -p "$LOGDIR"
DATE=$(date +%F)

# 修复点：巡检时的配置同步（与安装时逻辑一致）
SSH_ROOT_SETTING=$(sudo grep -E '^PermitRootLogin\s+(yes|prohibit-password|without-password)' /etc/ssh/sshd_config 2>/dev/null && echo "yes" || echo "no")
for RKH_CONF in /etc/rkhunter.conf /etc/rkhunter.conf.local; do
    [ -f "$RKH_CONF" ] && sudo sed -i "s/^ALLOW_SSH_ROOT_USER=.*/ALLOW_SSH_ROOT_USER=${SSH_ROOT_SETTING}/" "$RKH_CONF" 2>/dev/null
done

echo "[巡检] 开始自动安全巡检..."

# Lynis
echo "[巡检] 执行 lynis..."
sudo lynis audit system > "$LOGDIR/lynis-${DATE}.log"

# rkhunter
echo "[巡检] 执行 rkhunter..."
sudo rkhunter --update --quiet
sudo rkhunter --check --skip-keypress --report-warnings-only --logfile "$LOGDIR/rkhunter-${DATE}.log"

# chkrootkit
echo "[巡检] 执行 chkrootkit..."
(cd /tmp && sudo chkrootkit) > "$LOGDIR/chkrootkit-${DATE}.log" 2>&1

# 清理旧日志（保留 3 周）
sudo find "$LOGDIR" -type f -mtime +21 -delete

echo "[巡检] 本次自动巡检完成，日志保存在 $LOGDIR"
EOF

sudo chmod +x "$SCRIPT_PATH"

echo "[INFO] 设置每周日凌晨 2:00 自动巡检..."
(sudo crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "0 2 * * 0 $SCRIPT_PATH") | sudo crontab -

echo "[INFO] 立即手动执行一次巡检..."
sudo "$SCRIPT_PATH"
echo "[INFO] 自动巡检全部配置完成，日志目录：$LOGDIR"
