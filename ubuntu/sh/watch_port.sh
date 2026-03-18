#!/bin/bash
# 系统安全快速检测脚本
# 作者: XFlow
# 描述: 检测监听端口、防火墙规则、开放端口、运行进程、常见安全配置问题，并输出报告

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局问题列表数组
declare -a ISSUES=()

# 输出带颜色的函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_good() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ISSUES+=("⚠️  $1")
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ISSUES+=("❌ $1")
}

print_section() {
    echo
    echo -e "${BLUE}========== $1 ==========${NC}"
}

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
   print_error "此脚本需要 root 权限运行，请使用 sudo 或以 root 执行。"
   exit 1
fi

echo -e "${BLUE}========== 系统安全检测报告 ==========${NC}"
echo "检测时间: $(date)"
echo "主机名: $(hostname)"
echo "内核: $(uname -r)"
echo "运行时间: $(uptime -p)"
echo

# 1. 监听端口及对应程序
print_section "1. 监听端口及对应程序 (TCP/UDP)"
if command -v ss &>/dev/null; then
    ss -tulnp | awk 'NR>1 {
        proto = $1;
        address = $5;
        port = $5;
        gsub(/.*:/, "", port);
        process = $7;
        gsub(/users:\(\(/, "", process);
        gsub(/".*/, "", process);
        if (address ~ /0.0.0.0:/ || address ~ /:::/ || address ~ /\*:/)
            print "对外暴露\t" proto "\t" port "\t" address "\t" process;
        else if (address ~ /127.0.0.1:/ || address ~ /::1:/)
            print "仅本地\t" proto "\t" port "\t" address "\t" process;
        else
            print "其他\t" proto "\t" port "\t" address "\t" process;
    }' | while read line; do
        type=$(echo $line | cut -f1)
        proto=$(echo $line | cut -f2)
        port=$(echo $line | cut -f3)
        addr=$(echo $line | cut -f4)
        proc=$(echo $line | cut -f5-)
        if [[ "$type" == "对外暴露" ]]; then
            print_warn "端口 $port/$proto 监听在 $addr，进程 $proc → 对外暴露，请确认是否必要"
        elif [[ "$type" == "仅本地" ]]; then
            print_good "端口 $port/$proto 监听在 $addr，进程 $proc → 仅本地，安全"
        else
            print_info "端口 $port/$proto 监听在 $addr，进程 $proc"
        fi
    done
else
    netstat -tulnp | awk 'NR>2 {
        proto = $1;
        address = $4;
        port = $4;
        gsub(/.*:/, "", port);
        process = $7;
        if (address ~ /0.0.0.0:/ || address ~ /:::/)
            print "对外暴露\t" proto "\t" port "\t" address "\t" process;
        else if (address ~ /127.0.0.1:/ || address ~ /::1:/)
            print "仅本地\t" proto "\t" port "\t" address "\t" process;
        else
            print "其他\t" proto "\t" port "\t" address "\t" process;
    }' | while read line; do
        type=$(echo $line | cut -f1)
        proto=$(echo $line | cut -f2)
        port=$(echo $line | cut -f3)
        addr=$(echo $line | cut -f4)
        proc=$(echo $line | cut -f5-)
        if [[ "$type" == "对外暴露" ]]; then
            print_warn "端口 $port/$proto 监听在 $addr，进程 $proc → 对外暴露，请确认是否必要"
        elif [[ "$type" == "仅本地" ]]; then
            print_good "端口 $port/$proto 监听在 $addr，进程 $proc → 仅本地，安全"
        else
            print_info "端口 $port/$proto 监听在 $addr，进程 $proc"
        fi
    done
fi

# 2. 防火墙规则及默认策略
print_section "2. 防火墙规则及默认策略"

# 检测防火墙类型
FIREWALL_TYPE=""
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    FIREWALL_TYPE="ufw"
    print_info "检测到防火墙: ufw (已启用)"
    ufw status verbose | while read line; do
        echo "  $line"
    done
    DEFAULT_IN=$(ufw status verbose | grep "Default:" | grep -o "deny (incoming)" | wc -l)
    if [[ $DEFAULT_IN -gt 0 ]]; then
        print_good "默认入站策略: deny (安全)"
    else
        print_warn "默认入站策略: allow (可能存在风险)"
    fi
    # 获取已放行端口
    ALLOWED_PORTS=$(ufw status | grep -E '^[0-9]' | awk '{print $1}')
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    FIREWALL_TYPE="firewalld"
    print_info "检测到防火墙: firewalld (已启用)"
    DEFAULT_ZONE=$(firewall-cmd --get-default-zone)
    echo "  默认区域: $DEFAULT_ZONE"
    firewall-cmd --list-all --zone=$DEFAULT_ZONE | while read line; do
        echo "  $line"
    done
    # 检查默认区域是否拒绝
    if firewall-cmd --query-panic; then
        print_error "防火墙处于panic模式！所有流量被拒绝！"
    else
        # 粗略判断：如果区域没有明确的服务和端口，可能默认拒绝
        SERVICES=$(firewall-cmd --list-services --zone=$DEFAULT_ZONE)
        PORTS=$(firewall-cmd --list-ports --zone=$DEFAULT_ZONE)
        if [[ -z "$SERVICES" && -z "$PORTS" ]]; then
            print_good "默认区域无放行服务/端口，相当于默认拒绝 (安全)"
        else
            print_info "放行服务: $SERVICES"
            print_info "放行端口: $PORTS"
        fi
        ALLOWED_PORTS="$SERVICES $PORTS"
    fi
else
    # 尝试 iptables
    if command -v iptables &>/dev/null; then
        FIREWALL_TYPE="iptables"
        print_info "检测到防火墙: iptables"
        DEFAULT_POLICY=$(iptables -L INPUT -n | head -n1 | grep -o 'policy [A-Z]*' | cut -d' ' -f2)
        echo "  INPUT 链默认策略: $DEFAULT_POLICY"
        if [[ "$DEFAULT_POLICY" == "DROP" ]] || [[ "$DEFAULT_POLICY" == "REJECT" ]]; then
            print_good "默认入站策略: $DEFAULT_POLICY (安全)"
        else
            print_warn "默认入站策略: $DEFAULT_POLICY (允许所有入站，危险)"
        fi
        # 列出放行规则（简单显示）
        echo "  INPUT 链规则 (允许的):"
        iptables -L INPUT -n -v --line-numbers | grep -E 'ACCEPT|ALLOW' | head -10 | sed 's/^/    /'
        # 收集放行端口
        ALLOWED_PORTS=$(iptables -L INPUT -n | grep ACCEPT | grep -o 'dpt:[0-9]*' | cut -d: -f2 | sort -u)
    else
        print_error "未检测到活动防火墙，系统可能没有任何防护！"
        ALLOWED_PORTS=""
    fi
fi

# 3. 实际开放入站端口 (结合监听和防火墙)
print_section "3. 实际开放入站端口 (可从外部访问)"
OPEN_PORTS=()
# 获取所有对外监听的端口
EXPOSED_PORTS=$(ss -tuln | awk '$5 ~ /0.0.0.0:/ || $5 ~ /:::/ || $5 ~ /\*:/ { split($5,a,":"); print a[length(a)]"/"$1 }' | sort -u)
if [[ -z "$EXPOSED_PORTS" ]]; then
    print_good "没有发现监听在所有接口的端口，所有服务仅本地访问。"
else
    print_info "以下端口监听在所有接口，可能对外开放:"
    for p in $EXPOSED_PORTS; do
        echo "    $p"
    done

    # 根据防火墙判断实际可达
    if [[ -n "$FIREWALL_TYPE" ]]; then
        if [[ "$FIREWALL_TYPE" == "ufw" ]] && [[ "$DEFAULT_IN" -gt 0 ]]; then
            # 默认拒绝，只有明确放行的才开放
            ALLOWED_LIST=$(ufw status | grep -E '^[0-9]' | awk '{print $1}')
            OPEN_PORTS=$(comm -12 <(echo "$EXPOSED_PORTS" | sort) <(echo "$ALLOWED_LIST" | sort))
        elif [[ "$FIREWALL_TYPE" == "firewalld" ]]; then
            # 从默认区域获取放行端口和服务
            ALLOWED_PORTS=$(firewall-cmd --list-ports --zone=$DEFAULT_ZONE)
            ALLOWED_SERVICES=$(firewall-cmd --list-services --zone=$DEFAULT_ZONE)
            # 转换服务名为端口（粗略）
            OPEN_PORTS=()
            for p in $EXPOSED_PORTS; do
                port_proto=$p
                # 检查是否在放行端口列表中
                if echo "$ALLOWED_PORTS" | grep -q "${port_proto/\//}"; then
                    OPEN_PORTS+=("$p")
                fi
                # 检查服务（需要解析，这里简化，认为服务可能对应端口，暂不处理）
            done
        elif [[ "$FIREWALL_TYPE" == "iptables" ]]; then
            if [[ "$DEFAULT_POLICY" == "DROP" ]] || [[ "$DEFAULT_POLICY" == "REJECT" ]]; then
                # 需要检查是否有针对这些端口的 ACCEPT 规则
                OPEN_PORTS=()
                for p in $EXPOSED_PORTS; do
                    port=${p%/*}
                    proto=${p#*/}
                    if iptables -L INPUT -n | grep -q "ACCEPT.*dpt:$port"; then
                        OPEN_PORTS+=("$p")
                    fi
                done
            else
                # 默认允许，所有暴露端口都开放
                OPEN_PORTS=($EXPOSED_PORTS)
            fi
        else
            OPEN_PORTS=($EXPOSED_PORTS)
        fi

        if [[ ${#OPEN_PORTS[@]} -eq 0 ]]; then
            print_good "尽管有端口监听所有接口，但防火墙阻止了入站访问，外部无法连接。"
        else
            print_warn "以下端口可能可以从外部访问 (监听所有接口 + 防火墙允许):"
            for p in "${OPEN_PORTS[@]}"; do
                echo "    $p"
                ISSUES+=("🌐 端口 $p 对外暴露，请确认是否需要")
            done
        fi
    else
        print_warn "未检测到防火墙，以下端口全部对外开放:"
        for p in $EXPOSED_PORTS; do
            echo "    $p"
            ISSUES+=("🌐 端口 $p 对外暴露 (无防火墙防护)")
        done
    fi
fi

# 4. 运行中的进程检查 (重点关注网络服务和资源占用)
print_section "4. 运行中进程分析"
print_info "以下为监听端口的进程列表 (已在前文显示)"
# 简单检查是否有CPU/内存占用异常的进程
print_info "检查 CPU/内存占用前5的进程:"
ps aux --sort=-%cpu | head -6 | tail -5 | while read line; do
    echo "    $line"
done
# 可检查可疑进程名（简单示例）
SUSPICIOUS_PROCS=("nc" "netcat" "ncat" "cryptominer" "xmr" "minerd")
for sp in "${SUSPICIOUS_PROCS[@]}"; do
    if pgrep -f "$sp" &>/dev/null; then
        print_error "发现可疑进程名包含 '$sp'，请手动检查: $(pgrep -f "$sp" | xargs ps -p)"
    fi
done

# 5. 安全配置检查
print_section "5. 常见安全配置检查"

# SSH 配置
if [ -f /etc/ssh/sshd_config ]; then
    print_info "检查 SSH 配置..."
    # 是否允许 root 登录
    if grep -E '^PermitRootLogin\s+yes' /etc/ssh/sshd_config &>/dev/null; then
        print_error "SSH 允许 root 直接登录 (PermitRootLogin yes)，建议禁止"
    else
        print_good "SSH root 登录已限制或禁止"
    fi
    # 是否允许密码认证
    if grep -E '^PasswordAuthentication\s+yes' /etc/ssh/sshd_config &>/dev/null; then
        print_error "SSH 允许密码认证，建议禁用并仅使用密钥"
    else
        print_good "SSH 密码认证已禁用"
    fi
    # 使用的端口
    SSH_PORT=$(grep -E '^Port\s+' /etc/ssh/sshd_config | awk '{print $2}' | head -1)
    if [[ -z "$SSH_PORT" ]]; then SSH_PORT=22; fi
    print_info "SSH 端口: $SSH_PORT"
    # 检查是否在开放端口列表中
    if [[ " ${OPEN_PORTS[@]} " =~ " $SSH_PORT/tcp " ]]; then
        print_warn "SSH 端口 $SSH_PORT/tcp 对外暴露，请确保密钥认证强度足够"
    fi
fi

# 用户账户检查
print_info "检查用户账户安全..."
# 空密码用户
EMPTY_PASS=$(awk -F: '($2=="") {print $1}' /etc/shadow 2>/dev/null)
if [[ -n "$EMPTY_PASS" ]]; then
    print_error "发现空密码用户: $EMPTY_PASS，极度危险！"
fi
# 密码永不过期用户
while IFS=: read user pass; do
    if [[ "$pass" != "*" && "$pass" != "!"* ]]; then
        # 获取过期信息
        expire_info=$(chage -l "$user" 2>/dev/null | grep "Password expires" | cut -d: -f2)
        if [[ "$expire_info" == *"never"* ]]; then
            print_warn "用户 $user 密码永不过期，建议设置过期策略"
        fi
    fi
done < /etc/shadow

# 关键文件权限
print_info "检查关键文件权限..."
check_perms() {
    file=$1
    required=$2
    desc=$3
    if [[ -e "$file" ]]; then
        perms=$(stat -c "%a" "$file")
        if [[ "$perms" != "$required" ]]; then
            print_warn "$desc 权限应为 $required，当前为 $perms"
        else
            print_good "$desc 权限正确 ($perms)"
        fi
    fi
}
check_perms "/etc/shadow" "640" "/etc/shadow"
check_perms "/etc/passwd" "644" "/etc/passwd"
check_perms "/etc/sudoers" "440" "/etc/sudoers"
check_perms "/etc/sudoers.d" "750" "/etc/sudoers.d 目录"

# 系统更新提示 (仅检测是否需要重启，不实际检查更新包)
if [ -f /var/run/reboot-required ]; then
    print_warn "系统有更新需要重启 (存在 /var/run/reboot-required)"
fi

# 检查是否有可疑的定时任务
print_info "检查定时任务 (cron) 中是否有可疑条目..."
CRON_FILES=("/etc/crontab" "/etc/cron.d/" "/var/spool/cron/crontabs/")
for cf in "${CRON_FILES[@]}"; do
    if [[ -d "$cf" ]]; then
        find "$cf" -type f -exec grep -l -E '(wget|curl|nc|chmod \+x|/tmp/)' {} \; 2>/dev/null | while read f; do
            print_warn "定时任务文件 $f 可能包含可疑命令"
        done
    elif [[ -f "$cf" ]]; then
        grep -E '(wget|curl|nc|chmod \+x|/tmp/)' "$cf" 2>/dev/null && print_warn "文件 $cf 可能包含可疑命令"
    fi
done

# 6. 汇总问题
print_section "6. 安全检测问题汇总"
if [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}未发现明显安全问题，系统当前较为安全。${NC}"
else
    echo -e "${YELLOW}发现以下问题，建议逐一排查修复:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo "  $issue"
    done
fi

echo
echo -e "${BLUE}========== 检测完成 ==========${NC}"
