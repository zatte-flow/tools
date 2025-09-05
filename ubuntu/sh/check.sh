#!/bin/bash
# Ubuntu 24.04 全面体检脚本  2025-09-05
REPORT=/tmp/system-check-$(hostname)-$(date +%F).log
echo "===== 全面系统体检 $(date) =====" > $REPORT

# 0. 颜色
RED='\e[1;31m'; GRN='\e[1;32m'; YEL='\e[1;33m'; NC='\e[0m'
log(){ echo -e "$1" | tee -a $REPORT; }

# 1. 安全补丁
log "${YEL}① 安全补丁 & 仓库配置${NC}"
if ! grep -q noble-security /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
    log "${RED}✗ 缺少 noble-security 仓库${NC}"
else
    log "${GRN}✓ 安全仓库已启用${NC}"
fi
apt list --upgradable 2>/dev/null | grep -c security && log "${RED}✗ 存在安全更新待安装${NC}" || log "${GRN}✓ 安全更新已最新${NC}"

# 2. 已知 CVE 内核漏洞
log "${YEL}② 内核 CVE 快速比对${NC}"
CURRENT=$(uname -r)
if command -v ubuntu-security-status >/dev/null 2>&1; then
    ubuntu-security-status --unavailable | grep -i "kernel" && log "${RED}✗ 内核有未修复 CVE${NC}" || log "${GRN}✓ 内核暂无已知 CVE${NC}"
else
    log "${YEL}! ubuntu-security-status 未安装，略过 CVE 检查${NC}"
fi

# 3. Rootkit / 文件完整性
log "${YEL}③ Rootkit 检测${NC}"
# ---- 先更新特征库，再扫描 ----
rkhunter --update --quiet
rkhunter -c --skip-keypress --rwo >> "$REPORT" 2>&1
chkrootkit -q >> "$REPORT" 2>&1
# ---- 判断结果 ----
if grep -Eiq "warning|infected" "$REPORT"; then
    log "${RED}✗ rkhunter/chkrootkit 存在告警，见报告${NC}"
else
    log "${GRN}✓ Rootkit 检测通过${NC}"
fi

# 4. 系统启动异常
log "${YEL}④ 启动失败单元${NC}"
FAILED=$(systemctl --failed --no-legend | wc -l)
[[ $FAILED -gt 0 ]] && log "${RED}✗ 有 $FAILED 个失败单元${NC}" || log "${GRN}✓ 无失败单元${NC}"

# 5. 日志异常（近 1 天）
log "${YEL}⑤ 内核 & 认证异常日志${NC}"
journalctl -k -b -0 -p err --since "1 day ago" -q | tee -a $REPORT
journalctl -u ssh -p err --since "1 day ago" -q | tee -a $REPORT
[[ $(journalctl -k -b -0 -p err --since "1 day ago" -q | wc -l) -gt 0 ]] && log "${RED}✗ 内核/SSH 存在错误日志${NC}" || log "${GRN}✓ 近 1 天无关键错误${NC}"

# 6. 网络监听 & 特权进程
log "${YEL}⑥ 监听端口 & 特权进程${NC}"
ss -tulnp | tee -a $REPORT
[[ $(ss -tulnp | grep -vE '127\.0\.0\.1|::1' | grep LISTEN | wc -l) -gt 10 ]] && log "${YEL}! 公网监听端口较多，请复核${NC}"
ps aux | awk '$3>10.0' | tee -a $REPORT        # CPU>10%

# 7. 磁盘健康
log "${YEL}⑦ 磁盘/文件系统健康${NC}"
command -v smartctl >/dev/null && \
for disk in /dev/sd? /dev/nvme?n1; do [[ -e $disk ]] && smartctl -H "$disk" | grep -i health; done | tee -a $REPORT
df -h | grep -E '9[0-9]%|100%' && log "${RED}✗ 分区使用率 >90%${NC}" || log "${GRN}✓ 磁盘空间正常${NC}"

# 8. 温度 & 硬件
log "${YEL}⑧ 温度/风扇${NC}"
sensors 2>/dev/null | tee -a $REPORT
[[ $(sensors 2>/dev/null | awk '/°C/ && $2+0>80' | wc -l) -gt 0 ]] && log "${RED}✗ 温度 >80°C${NC}" || log "${GRN}✓ 温度正常${NC}"

# 9. 关键服务在线
log "${YEL}⑨ 关键服务${NC}"
for s in ssh systemd-resolved systemd-timesyncd; do
    systemctl is-active $s >/dev/null && log "${GRN}✓ $s 运行${NC}" || log "${RED}✗ $s 未运行${NC}"
done

# 10. 生成摘要
log "${YEL}⑩ 报告位置${NC}"
log "完整报告 → $REPORT"
[[ $(grep -c "${RED}" $REPORT) -gt 0 ]] && log "${RED}>>> 存在 ${RED}$(grep -c "${RED}" $REPORT)${RED} 项需人工复核 <<<${NC}" || log "${GRN}>>> 系统状态良好 <<<${NC}"
