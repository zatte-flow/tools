#!/bin/bash
# 服务器安全检测脚本 - 保存到 /var/tmp
# 用法: sudo bash /var/tmp/security_audit.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "      服务器安全检测脚本"
echo "      时间: $(date)"
echo "      位置: /var/tmp"
echo "=========================================="

# 1. 系统信息
echo -e "\n${YELLOW}[1/10] 系统信息${NC}"
echo "主机名: $(hostname)"
echo "内网IP: $(ip route get 1 | awk '{print $7;exit}')"
echo "公网IP: $(curl -s ip.sb 2>/dev/null || echo '无法获取')"
echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"

# 2. 端口监听检查
echo -e "\n${YELLOW}[2/10] 端口监听状态${NC}"
ss -tulpn | grep -E '53196|19023|22' | while read line; do
    if echo "$line" | grep -q '0.0.0.0'; then
        echo -e "${RED}[暴露公网]${NC} $line"
    else
        echo -e "${GREEN}[受限]${NC} $line"
    fi
done

# 3. fail2ban 状态（关键）
echo -e "\n${YELLOW}[3/10] fail2ban 防护状态${NC}"
if systemctl is-active fail2ban >/dev/null 2>&1; then
    echo -e "${GREEN}[运行中]${NC} fail2ban"
    echo "--- SSH jail 状态 ---"
    sudo fail2ban-client status sshd 2>/dev/null || echo -e "${RED}[错误]${NC} SSH jail 未配置"
    
    # 检查是否有实际封禁记录
    TOTAL_BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $3}')
    if [ "$TOTAL_BANNED" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}[有效]${NC} 已封禁 $TOTAL_BANNED 个IP"
    else
        echo -e "${RED}[警告]${NC} 无封禁记录，可能未读到日志！"
    fi
else
    echo -e "${RED}[严重]${NC} fail2ban 未运行！"
fi

# 4. 最近攻击记录（关键）
echo -e "\n${YELLOW}[4/10] 最近 SSH 攻击 (TOP 10)${NC}"
echo "--- 失败登录 ---"
sudo grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 | awk '{print $1,$2,$3,$9,$11}' || echo "无记录"

echo "--- 无效用户 ---"
sudo grep "Invalid user" /var/log/auth.log 2>/dev/null | tail -5 | awk '{print $1,$2,$3,$8,$10}' || echo "无记录"

# 5. 当前封禁的 IP
echo -e "\n${YELLOW}[5/10] 当前封禁的 IP${NC}"
sudo fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" -A 1 || echo "无"

# 6. iptables 封禁列表
echo -e "\n${YELLOW}[6/10] 手动封禁的 IP${NC}"
sudo iptables -L INPUT -n | grep DROP | head -10 || echo "无手动封禁"

# 7. 攻击者 IP 统计（24小时内）
echo -e "\n${YELLOW}[7/10] 攻击者 IP TOP 5 (24小时)${NC}"
sudo grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -5 || echo "无数据"

# 8. 隐藏文件检查
echo -e "\n${YELLOW}[8/10] 隐藏文件检查${NC}"
if [ -f "/etc/.updated" ]; then
    echo -e "${YELLOW}[发现]${NC} /etc/.updated"
    ls -la /etc/.updated
    dpkg -S /etc/.updated 2>/dev/null && echo -e "${GREEN}[系统文件]${NC}" || echo -e "${RED}[未知文件]${NC}"
fi

# 9. 嗅探器检查
echo -e "\n${YELLOW}[9/10] 嗅探器检查${NC}"
ip link show | grep -q PROMISC && echo -e "${RED}[警告]${NC} 混杂模式" || echo -e "${GREEN}[正常]${NC} 无混杂模式"
lsof | grep -i pcap 2>/dev/null | grep -q . && echo -e "${RED}[警告]${NC} 发现嗅探器" || echo -e "${GREEN}[正常]${NC} 无嗅探器"

# 10. 1Panel 检查
echo -e "\n${YELLOW}[10/10] 1Panel 安全${NC}"
if systemctl is-active 1panel >/dev/null 2>&1; then
    echo -e "${GREEN}[运行]${NC} 1Panel"
    ss -tulpn | grep 19023 | grep -q "0.0.0.0" && echo -e "${RED}[风险]${NC} 暴露公网，需设置IP白名单" || echo -e "${GREEN}[安全]${NC} 未暴露"
else
    echo "1Panel 未运行"
fi

echo -e "\n=========================================="
echo "           检测完成"
echo "=========================================="
echo -e "${YELLOW}紧急建议:${NC}"
echo "1. 确认 fail2ban 有封禁记录 (Total banned > 0)"
echo "2. 如攻击持续，手动封禁: sudo iptables -I INPUT -s 92.118.39.0/24 -j DROP"
echo "3. 1Panel 必须设置授权IP白名单"
