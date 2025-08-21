#!/usr/bin/env bash
# sec-tools-v2.sh
# 自动安装 lynis、rkhunter、chkrootkit，并设置定期自动巡检
# 包含：工具更新、基线检查、摘要生成、运维小工具提示

set -eu
LOGDIR="/var/log/weekly-sec"
SCRIPT_PATH="/usr/local/bin/weekly-sec.sh"

# 防止 getcwd 报错
if ! cd /tmp 2>/dev/null; then
  cd /
fi

echo "[INFO] 开始安装 lynis、rkhunter、chkrootkit..."
sudo apt-get update
sudo apt-get install -y lynis rkhunter chkrootkit

# 修复 rkhunter WEB_CMD
sudo sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf 2>/dev/null || true
sudo sed -i 's|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf.local 2>/dev/null || true

# 同步 SSH 与 rkhunter 的 root 登录配置
SSH_ROOT_SETTING=$(if sudo grep -Eq '^PermitRootLogin\s+(yes|prohibit-password|without-password)' /etc/ssh/sshd_config 2>/dev/null; then echo "yes"; else echo "no"; fi)
for RKH_CONF in /etc/rkhunter.conf /etc/rkhunter.conf.local; do
    [ -f "$RKH_CONF" ] && sudo sed -i "s/^ALLOW_SSH_ROOT_USER=.*/ALLOW_SSH_ROOT_USER=${SSH_ROOT_SETTING}/" "$RKH_CONF" 2>/dev/null || true
done

# 生成 weekly-sec.sh 巡检脚本
sudo tee "$SCRIPT_PATH" > /dev/null <<'EOF'
#!/bin/bash
# weekly-sec.sh
# 每周安全巡检：lynis/rkhunter/chkrootkit
# 支持 manual/quick/propupd 子命令
# 自动更新工具包 + 自动生成每日摘要

# set -eu
if ! cd /tmp 2>/dev/null; then
  cd /
fi

LOGDIR=/var/log/weekly-sec
sudo mkdir -p "$LOGDIR"
DATE=$(date +%F)

# ---------- 1. 先更新工具 ----------
echo "[巡检] 更新 lynis、rkhunter、chkrootkit ..."
sudo apt-get update -qq
sudo apt-get install -y lynis rkhunter chkrootkit

# ---------- 2. 同步 SSH 与 rkhunter 配置 ----------
SSH_ROOT_SETTING=$(sudo grep -E '^PermitRootLogin\s+(yes|prohibit-password|without-password)' /etc/ssh/sshd_config 2>/dev/null && echo "yes" || echo "no")
for RKH_CONF in /etc/rkhunter.conf /etc/rkhunter.conf.local; do
    [ -f "$RKH_CONF" ] && sudo sed -i "s/^ALLOW_SSH_ROOT_USER=.*/ALLOW_SSH_ROOT_USER=${SSH_ROOT_SETTING}/" "$RKH_CONF" 2>/dev/null
done

# ---------- 3. 主巡检逻辑 ----------
main() {
    echo "[巡检] 开始安全巡检 ($DATE)"

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

    # 清理 21 天前的日志
    sudo find "$LOGDIR" -type f -mtime +21 -delete

    # ---------- 4. 自动生成每日告警摘要 ----------
    {
        echo "====== 安全巡检快速摘要 $DATE ======"
        echo "--- rkhunter 告警 ---"
        awk '/Warning:/{print "  - " $0}' "$LOGDIR/rkhunter-${DATE}.log" 2>/dev/null || echo "  无"
        echo "--- chkrootkit 告警 ---"
        awk '/INFECTED|sniffer/{print "  - " $0}' "$LOGDIR/chkrootkit-${DATE}.log" 2>/dev/null || echo "  无"
        echo "--- lynis TOP-10 建议 ---"
        awk '/WARNING|SUGGESTION/{print "  - " $0}' "$LOGDIR/lynis-${DATE}.log" 2>/dev/null | head -10 || echo "  无"
    } > "$LOGDIR/summary-${DATE}.txt"

    echo "[巡检] 完成！日志与摘要已保存到 $LOGDIR"
}

# ---------- 5. 子命令支持 ----------
case "${1:-}" in
  manual)
    echo "[手动] 立即执行巡检..."
    main
    ;;
  quick)
    echo "[INFO] 今日告警摘要："
    cat "$LOGDIR/summary-$(date +%F).txt"
    ;;
  propupd)
    echo "[INFO] 更新 rkhunter 基线..."
    sudo rkhunter --propupd
    ;;
  *)
    # 无参数：自动任务也走这里
    main
    ;;
esac

# ----- 运维小工具提示（追加到脚本最后） -----
echo "[INFO] 附加命令已集成："
echo "  sudo $0 manual   # 立即再跑一遍巡检"
echo "  sudo $0 quick    # 查看今日告警摘要"
echo "  sudo $0 propupd  # 更新 rkhunter 基线"
EOF

sudo chmod +x "$SCRIPT_PATH"

echo "[INFO] 设置每周日凌晨 2:00 自动巡检..."
(sudo crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "0 2 * * 0 $SCRIPT_PATH") | sudo crontab -

echo "[INFO] 立即手动执行一次巡检..."
sudo "$SCRIPT_PATH"
echo "[INFO] 自动巡检全部配置完成，日志目录：$LOGDIR"
