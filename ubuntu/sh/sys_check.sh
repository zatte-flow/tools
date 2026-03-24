#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 安全检测脚本 - 适用于 Ubuntu 24 (亦兼容其他 Ubuntu 版本)
# 功能：
#   1. 检查 UFW 状态及规则，验证默认入站策略是否为 deny。
#   2. 检查实际生效的 iptables 规则（INPUT 链）。
#   3. 列出所有监听端口及关联进程，并与防火墙规则对比判断暴露风险。
#   4. 检查 SSH 配置安全性（root 登录、密码认证等）。
#   5. 检查系统用户安全（特权用户、无密码账户等）。
#   6. 提供其他基础安全建议。
# 运行建议：使用 root 用户执行以获得完整信息。
# -----------------------------------------------------------------------------

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出标题
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}       Ubuntu 安全检测报告             ${NC}"
echo -e "${BLUE}========================================${NC}"
echo "生成时间: $(date)"
echo ""

# 检查是否以 root 运行
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}警告: 未以 root 用户运行，部分信息可能不完整。${NC}"
    echo "建议使用 sudo 执行此脚本。"
    echo ""
fi

# -----------------------------------------------------------------------------
# 1. UFW 状态与规则
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 1. UFW 防火墙状态 <<<${NC}"
if command -v ufw &> /dev/null; then
    ufw_status=$(ufw status verbose)
    if echo "$ufw_status" | grep -q "Status: active"; then
        echo -e "${GREEN}UFW 状态: 已启用${NC}"
    else
        echo -e "${RED}UFW 状态: 未启用！${NC}"
    fi
    echo "$ufw_status"
    echo ""
else
    echo -e "${RED}UFW 未安装，请使用 apt install ufw 安装。${NC}"
    echo ""
fi

# 获取默认策略
echo -e "${BLUE}--- 默认策略 ---${NC}"
ufw show raw | grep -i "default" || echo "未获取到默认策略，请检查 UFW 配置。"
echo ""

# -----------------------------------------------------------------------------
# 2. iptables INPUT 链规则（实际生效的防火墙）
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 2. iptables INPUT 链规则（实际过滤） <<<${NC}"
if command -v iptables &> /dev/null; then
    iptables -L INPUT -n -v --line-numbers 2>/dev/null || echo "无法获取 iptables 规则，请确保有权限或 nftables 未覆盖。"
else
    echo "iptables 命令不可用。"
fi
echo ""

# -----------------------------------------------------------------------------
# 3. 监听端口与服务
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 3. 当前监听端口及关联服务 <<<${NC}"
if command -v ss &> /dev/null; then
    listening_ports=$(ss -tulpn 2>/dev/null | grep -v "users:" | grep LISTEN || true)
else
    listening_ports=$(netstat -tulpn 2>/dev/null | grep LISTEN)
fi

if [[ -n "$listening_ports" ]]; then
    echo -e "${YELLOW}以下端口正在监听：${NC}"
    echo "$listening_ports"
    echo ""
else
    echo -e "${GREEN}未发现任何监听端口。${NC}"
    echo ""
fi

# 分析哪些监听端口可能被防火墙允许（入站）
echo -e "${BLUE}--- 防火墙允许入站的端口（基于 UFW 规则） ---${NC}"
allowed_ports=$(ufw status | grep -E "ALLOW|LIMIT" | awk '{print $1}' | sort -u)
if [[ -n "$allowed_ports" ]]; then
    echo "$allowed_ports"
else
    echo "未发现任何允许入站的端口（或 UFW 未启用）。"
fi
echo ""

# 对比监听端口与允许规则，找出潜在暴露端口
echo -e "${BLUE}--- 风险端口（监听且防火墙允许入站） ---${NC}"
# 提取监听端口号
listening_ports_numbers=$(echo "$listening_ports" | awk -F'[ :]+' '/LISTEN/ {print $5}' | sort -u)
exposed_ports=()
for port in $listening_ports_numbers; do
    if ufw status | grep -q -E "($port/|$port )" && ufw status | grep -q -E "ALLOW|LIMIT"; then
        exposed_ports+=("$port")
    fi
done

if [[ ${#exposed_ports[@]} -eq 0 ]]; then
    echo -e "${GREEN}没有发现监听端口被防火墙显式允许入站。${NC}"
else
    echo -e "${RED}警告：以下监听端口被防火墙允许入站：${NC}"
    printf '%s\n' "${exposed_ports[@]}"
fi
echo ""

# -----------------------------------------------------------------------------
# 4. SSH 安全性检查
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 4. SSH 配置安全评估 <<<${NC}"
if [[ -f /etc/ssh/sshd_config ]]; then
    # 检查 PermitRootLogin
    root_login=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    if [[ -z "$root_login" ]]; then
        echo -e "${YELLOW}PermitRootLogin 未明确设置，默认为 yes (危险)${NC}"
    elif [[ "$root_login" != "no" && "$root_login" != "prohibit-password" && "$root_login" != "without-password" ]]; then
        echo -e "${RED}PermitRootLogin 设置为 $root_login，建议设置为 no 或 prohibit-password。${NC}"
    else
        echo -e "${GREEN}PermitRootLogin 设置为 $root_login，较为安全。${NC}"
    fi

    # 检查密码认证
    password_auth=$(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' || echo "未设置")
    if [[ -z "$password_auth" ]]; then
        echo -e "${YELLOW}PasswordAuthentication 未明确设置，默认为 yes (建议使用密钥认证)${NC}"
    elif [[ "$password_auth" == "yes" ]]; then
        echo -e "${RED}PasswordAuthentication 设置为 yes，建议改为 no 并仅使用密钥认证。${NC}"
    else
        echo -e "${GREEN}PasswordAuthentication 设置为 no，较为安全。${NC}"
    fi

    # 检查 SSH 端口
    ssh_port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    if [[ "$ssh_port" != "22" ]]; then
        echo -e "${GREEN}SSH 端口已修改为 $ssh_port，可降低扫描风险。${NC}"
    else
        echo -e "${YELLOW}SSH 端口为默认 22，建议修改为非标准端口。${NC}"
    fi
else
    echo -e "${RED}未找到 /etc/ssh/sshd_config，请确认 SSH 服务是否安装。${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# 5. 用户与权限安全
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 5. 用户账户安全检查 <<<${NC}"
# 检查特权用户 (uid=0)
privileged_users=$(awk -F: '$3==0 {print $1}' /etc/passwd)
if [[ "$privileged_users" != "root" ]]; then
    echo -e "${RED}警告：存在非 root 的特权用户 (UID 0): $privileged_users${NC}"
else
    echo -e "${GREEN}仅 root 用户拥有 UID 0。${NC}"
fi

# 检查没有密码的账户
no_passwd_users=$(awk -F: '($2=="") {print $1}' /etc/shadow 2>/dev/null || echo "")
if [[ -n "$no_passwd_users" ]]; then
    echo -e "${RED}警告：以下用户没有设置密码，请立即处理：$no_passwd_users${NC}"
else
    echo -e "${GREEN}所有用户均已设置密码。${NC}"
fi

# 检查可登录的 shell 用户
echo -e "${BLUE}--- 可登录的普通用户 ---${NC}"
grep -E "sh$|bash$" /etc/passwd | awk -F: '{print $1}' | grep -v root | while read -r user; do
    echo "  $user"
done
echo ""

# -----------------------------------------------------------------------------
# 6. 其他安全建议
# -----------------------------------------------------------------------------
echo -e "${GREEN}>>> 6. 其他安全建议 <<<${NC}"
# 检查 fail2ban 是否运行
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    echo -e "${GREEN}fail2ban 服务正在运行，可防御暴力破解。${NC}"
else
    echo -e "${YELLOW}fail2ban 未运行，建议安装以增强 SSH 等服务的防护。${NC}"
fi

# 检查 unattended-upgrades 是否启用
if dpkg -l unattended-upgrades &>/dev/null; then
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        echo -e "${GREEN}自动安全更新已启用。${NC}"
    else
        echo -e "${YELLOW}unattended-upgrades 已安装但未运行，请检查服务状态。${NC}"
    fi
else
    echo -e "${YELLOW}未安装 unattended-upgrades，建议安装以自动更新安全补丁。${NC}"
fi

# 简单检查系统是否已更新
if command -v apt &>/dev/null; then
    updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    if [[ $updates -gt 0 ]]; then
        echo -e "${YELLOW}有 $updates 个软件包可更新，建议执行 apt update && apt upgrade。${NC}"
    else
        echo -e "${GREEN}所有软件包已是最新。${NC}"
    fi
fi
echo ""

# -----------------------------------------------------------------------------
# 7. 总结
# -----------------------------------------------------------------------------
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}          检测完成                      ${NC}"
echo -e "${BLUE}========================================${NC}"
echo "请根据以上输出评估服务器的安全状况。如有异常，请及时修复。"
