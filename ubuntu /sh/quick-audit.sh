#!/bin/bash
# quick-audit.sh —— 一键提取本周报告核心信息
LOGDIR="/var/log/weekly-sec"
TODAY=$(date +%F)
REPORT="/tmp/security-scan-${TODAY}.txt"

echo "====== $(hostname) 安全巡检核心摘要 ${TODAY} ======" > "$REPORT"

echo -e "\n1) rkhunter 告警" >> "$REPORT"
awk '/Warning:/{print "  - " $0}' "$LOGDIR/rkhunter-${TODAY}.log" 2>/dev/null >> "$REPORT" || echo "  无告警" >> "$REPORT"

echo -e "\n2) chkrootkit 告警" >> "$REPORT"
awk '/INFECTED|sniffer/{print "  - " $0}' "$LOGDIR/chkrootkit-${TODAY}.log" 2>/dev/null >> "$REPORT" || echo "  无告警" >> "$REPORT"

echo -e "\n3) lynis TOP-10 建议" >> "$REPORT"
awk '/WARNING|SUGGESTION/{print "  - " $0}' "$LOGDIR/lynis-${TODAY}.log" \
  | head -10 >> "$REPORT" || echo "  日志不存在" >> "$REPORT"

echo -e "\n报告已保存：$REPORT\n"
cat "$REPORT"
