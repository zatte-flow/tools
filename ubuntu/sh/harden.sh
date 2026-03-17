#!/bin/bash
#
# Ubuntu 24.04 安全加固脚本（最终优化版）
# 默认用户名: next-flow, 默认 SSH 端口: 58639, 默认 1panel 端口: 52936
# 功能: 可选安装 Nginx/sing-box/cloudflared，可选放行 1panel 端口（可自定义）
# 请使用 root 用户或具有 sudo 权限的用户运行
#

set -euo pipefail

# 声明变量
SSH_USER=""
SSH_PORT=""
PANEL_PORT=""
ALLOW_1PANEL="no"
INSTALL_NGINX="no"
ALLOW_NGINX_PORTS="no"
INSTALL_SINGBOX="no"
INSTALL_CLOUDFLARED="no"
CLOUDFLARED_TOKEN=""

# 彩色输出
print_info() { echo -e "\e[32m[INFO]\e[0m $1"; }
print_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
print_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
print_question() { echo -e "\e[36m[QUESTION]\e[0m $1"; }

# 检查 root
if [[ $EUID -ne 0 ]]; then
    print_error "请使用 sudo 或以 root 用户运行此脚本。"
    exit 1
fi

# 默认值
DEFAULT_USER="next-flow"
DEFAULT_PORT=58639
DEFAULT_1PANEL_PORT=52936

# 检查默认 SSH 端口占用
if ss -tuln | grep -q ":$DEFAULT_PORT "; then
    print_error "默认 SSH 端口 $DEFAULT_PORT 已被占用，请修改为其他端口。"
    exit 1
fi

# 检查默认用户是否存在（仅用于后续提示）
if id "$DEFAULT_USER" &>/dev/null; then
    print_warn "默认用户 $DEFAULT_USER 已存在，后续将使用现有用户。"
fi

# ========== 交互式配置 ==========
# 用户名输入
while true; do
    print_question "请输入要创建的普通管理员用户名 [默认: ${DEFAULT_USER}]: "
    read -r SSH_USER_INPUT
    SSH_USER="${SSH_USER_INPUT:-$DEFAULT_USER}"

    if [[ -z "$SSH_USER" ]]; then
        print_error "用户名不能为空，请重新输入。"
        continue
    fi
    if [[ "$SSH_USER" =~ ^- ]]; then
        print_error "用户名不能以连字符开头，请重新输入。"
        continue
    fi
    if [[ ! "$SSH_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "用户名只能包含字母、数字、下划线(_)和连字符(-)，请重新输入。"
        continue
    fi
    break
done
print_info "用户名设置为: ${SSH_USER}"

# SSH 端口输入
while true; do
    print_question "请输入新的 SSH 监听端口 (必须大于50000) [默认: ${DEFAULT_PORT}]: "
    read -r SSH_PORT_INPUT
    if [[ -z "$SSH_PORT_INPUT" ]]; then
        SSH_PORT="$DEFAULT_PORT"
        print_info "使用默认端口: ${SSH_PORT}"
        break
    fi

    if [[ "$SSH_PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$SSH_PORT_INPUT" -gt 50000 ]] && [[ "$SSH_PORT_INPUT" -le 65535 ]]; then
        if ss -tuln | grep -q ":$SSH_PORT_INPUT "; then
            print_error "端口 $SSH_PORT_INPUT 已被占用，请选择其他端口。"
            continue
        fi
        SSH_PORT="$SSH_PORT_INPUT"
        print_info "SSH端口设置为: ${SSH_PORT}"
        break
    else
        print_error "端口号必须是 50001-65535 之间的数字，请重新输入。"
    fi
done

# 1panel 端口询问
ALLOW_1PANEL="no"
PANEL_PORT=""
print_question "是否预留 1panel 面板端口（防火墙放行）？(y/N): "
read -r ALLOW_1PANEL_INPUT
if [[ "$ALLOW_1PANEL_INPUT" =~ ^[Yy]$ ]]; then
    ALLOW_1PANEL="yes"
    while true; do
        print_question "请输入 1panel 面板端口 [默认: ${DEFAULT_1PANEL_PORT}]: "
        read -r PANEL_PORT_INPUT
        if [[ -z "$PANEL_PORT_INPUT" ]]; then
            PANEL_PORT="$DEFAULT_1PANEL_PORT"
            print_info "使用默认 1panel 端口: ${PANEL_PORT}"
            break
        fi
        if [[ "$PANEL_PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$PANEL_PORT_INPUT" -ge 1 ]] && [[ "$PANEL_PORT_INPUT" -le 65535 ]]; then
            PANEL_PORT="$PANEL_PORT_INPUT"
            print_info "1panel 端口设置为: ${PANEL_PORT}"
            break
        else
            print_error "端口号必须是 1-65535 之间的数字，请重新输入。"
        fi
    done
fi

# Nginx 安装询问
INSTALL_NGINX="no"
print_question "是否安装 Nginx？(y/N): "
read -r INSTALL_NGINX_INPUT
if [[ "$INSTALL_NGINX_INPUT" =~ ^[Yy]$ ]]; then
    INSTALL_NGINX="yes"
    ALLOW_NGINX_PORTS="no"
    print_question "是否放行 Nginx 的 80/443 端口？(y/N，默认不放行): "
    read -r ALLOW_NGINX_PORTS_INPUT
    if [[ "$ALLOW_NGINX_PORTS_INPUT" =~ ^[Yy]$ ]]; then
        ALLOW_NGINX_PORTS="yes"
        print_info "将在防火墙放行 80/443 端口"
    fi
fi

# Sing-box 安装询问
INSTALL_SINGBOX="no"
print_question "是否安装 sing-box？(y/N): "
read -r INSTALL_SINGBOX_INPUT
if [[ "$INSTALL_SINGBOX_INPUT" =~ ^[Yy]$ ]]; then
    INSTALL_SINGBOX="yes"
fi

# Cloudflared 安装询问（带 token 反馈）
INSTALL_CLOUDFLARED="no"
print_question "是否安装 cloudflared 隧道？(y/N): "
read -r INSTALL_CLOUDFLARED_INPUT
if [[ "$INSTALL_CLOUDFLARED_INPUT" =~ ^[Yy]$ ]]; then
    INSTALL_CLOUDFLARED="yes"
    print_question "请输入您的 cloudflared 隧道 token: "
    read -rs CLOUDFLARED_TOKEN
    echo
    if [[ -z "$CLOUDFLARED_TOKEN" ]]; then
        print_error "Token 不能为空，将跳过 cloudflared 安装。"
        INSTALL_CLOUDFLARED="no"
    else
        print_info "Token 已接收 (长度: ${#CLOUDFLARED_TOKEN})"
    fi
fi

# 最终确认
print_info "即将开始安全加固，使用的配置如下："
echo "  用户名: ${SSH_USER}"
echo "  SSH端口: ${SSH_PORT}"
echo "  1panel端口放行: ${ALLOW_1PANEL} (端口: ${PANEL_PORT:-无})"
echo "  安装Nginx: ${INSTALL_NGINX}"
if [[ "$INSTALL_NGINX" == "yes" ]]; then echo "  放行80/443: ${ALLOW_NGINX_PORTS}"; fi
echo "  安装sing-box: ${INSTALL_SINGBOX}"
echo "  安装cloudflared: ${INSTALL_CLOUDFLARED}"
print_question "是否继续？(y/N): "
read -r confirm_start
if [[ ! "$confirm_start" =~ ^[Yy]$ ]]; then
    print_warn "用户取消操作，脚本退出。"
    exit 0
fi

# ========== 第一阶段：基础系统准备 ==========
print_info "========== 第一阶段：基础系统准备 =========="

# 1. 系统更新（带容错）
print_info "更新软件包列表并升级所有软件..."
if ! apt update; then
    print_warn "apt update 失败，尝试修复源列表..."
    apt update --fix-missing
fi

if ! apt upgrade -y; then
    print_warn "apt upgrade 遇到错误，尝试修复依赖并重试..."
    apt --fix-broken install -y
    apt upgrade -y --fix-missing
fi

# 2. 安装必要工具
print_info "安装常用工具（curl、wget、ufw、sudo 等）..."
apt install -y curl wget software-properties-common gnupg2 ufw sudo

# 3. 时钟同步检测
if systemctl is-active systemd-timesyncd &>/dev/null; then
    print_info "系统已启用 systemd-timesyncd，跳过 NTP 安装。"
else
    print_info "安装 ntpsec 用于时钟同步..."
    apt install -y ntpsec
    systemctl enable --now ntpsec
fi

# 4. 防火墙初始化
print_info "初始化 UFW 防火墙..."
ufw --force disable &>/dev/null || true
ufw default deny incoming
ufw default allow outgoing

# ========== 用户创建与配置 ==========
print_info "========== 用户创建与配置 =========="

# 5. 检查用户是否存在，若不存在则创建并设置密码
print_info "检查用户 ${SSH_USER} 状态..."
if id "${SSH_USER}" &>/dev/null; then
    print_warn "用户 ${SSH_USER} 已存在，将使用现有用户，密码保持不变。"
else
    print_info "创建用户 ${SSH_USER}..."
    useradd -m -s /bin/bash -G sudo "${SSH_USER}"
    # 强制非空密码
    while true; do
        read -s -p "Enter password for user ${SSH_USER}: " PASSWORD1
        echo
        read -s -p "Re-enter password: " PASSWORD2
        echo
        if [[ -z "$PASSWORD1" ]]; then
            print_error "密码不能为空，请重新输入。"
            continue
        fi
        if [[ "$PASSWORD1" != "$PASSWORD2" ]]; then
            print_error "两次输入的密码不一致，请重新输入。"
            continue
        fi
        break
    done
    echo "$SSH_USER:$PASSWORD1" | chpasswd
    print_info "用户 ${SSH_USER} 密码设置成功。"
    unset PASSWORD1 PASSWORD2
fi

# 6. 确保用户属于 sudo 组（如果已存在但不在组中）
if ! groups "${SSH_USER}" | grep -q "\bsudo\b"; then
    print_warn "用户 ${SSH_USER} 不在 sudo 组中，正在添加..."
    usermod -aG sudo "${SSH_USER}"
    print_info "已添加用户 ${SSH_USER} 到 sudo 组。"
else
    print_info "用户 ${SSH_USER} 已在 sudo 组中。"
fi

# 7. SSH 服务加固
print_info "配置 SSH 服务（端口 ${SSH_PORT}，禁用 root 登录，保留密码认证）..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

if grep -q "^#*Port " "${SSHD_CONFIG}"; then
    sed -i "s/^#*Port .*/Port ${SSH_PORT}/" "${SSHD_CONFIG}"
else
    echo "Port ${SSH_PORT}" >> "${SSHD_CONFIG}"
fi
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "${SSHD_CONFIG}"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${SSHD_CONFIG}"
sed -i 's/^#*UsePAM.*/UsePAM yes/' "${SSHD_CONFIG}"

# 8. 防火墙放行 SSH 端口
print_info "防火墙放行 SSH 端口 ${SSH_PORT}..."
ufw allow "${SSH_PORT}/tcp" comment "SSH custom port"
if [[ "$ALLOW_1PANEL" == "yes" && -n "$PANEL_PORT" ]]; then
    print_info "防火墙放行 1panel 端口 ${PANEL_PORT}..."
    ufw allow "${PANEL_PORT}/tcp" comment "1panel panel"
fi
ufw --force enable
ufw status verbose

# 9. 重启 SSH 服务
print_info "重启 SSH 服务以应用新配置..."
systemctl restart ssh
print_info "SSH 服务已重启，请使用端口 ${SSH_PORT} 连接（保留密码认证）。"

# 10. 验证用户配置（不依赖 sudo 命令）
print_info "验证用户 ${SSH_USER} 的配置..."
if id "${SSH_USER}" &>/dev/null; then
    print_info "用户 ${SSH_USER} 存在。"
else
    print_error "用户 ${SSH_USER} 不存在，请检查。"
    exit 1
fi

if groups "${SSH_USER}" | grep -q "\bsudo\b"; then
    print_info "用户 ${SSH_USER} 已加入 sudo 组。"
else
    print_error "用户 ${SSH_USER} 不在 sudo 组中，请手动添加：usermod -aG sudo ${SSH_USER}"
    exit 1
fi

if command -v sudo &>/dev/null; then
    print_info "sudo 命令可用。"
else
    print_error "sudo 命令未安装，请执行：apt install sudo"
    exit 1
fi

print_info "用户配置验证通过。"

# ========== 第二阶段：应用安装与服务配置 ==========
print_info "========== 第二阶段：应用安装与服务配置 =========="

# 11. 安装 Nginx
if [[ "$INSTALL_NGINX" == "yes" ]]; then
    print_info "安装 Nginx..."
    apt install -y nginx
    systemctl enable --now nginx
    if [[ "$ALLOW_NGINX_PORTS" == "yes" ]]; then
        print_info "防火墙放行 80/443 端口..."
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
        ufw reload
    fi
fi

# 12. 安装 sing-box
if [[ "$INSTALL_SINGBOX" == "yes" ]]; then
    print_info "使用官方脚本安装 sing-box..."
    bash -c "$(curl -fsSL https://sing-box.app/install.sh)"
    systemctl enable sing-box || print_warn "sing-box 服务无法启用，请手动检查"
fi

# 13. 安装 cloudflared
if [[ "$INSTALL_CLOUDFLARED" == "yes" ]]; then
    print_info "安装 cloudflared..."
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
    apt update
    apt install -y cloudflared
    if [[ -n "$CLOUDFLARED_TOKEN" ]]; then
        print_info "使用提供的 token 安装隧道服务..."
        cloudflared service install "$CLOUDFLARED_TOKEN"
    fi
fi

# 14. 自动安全更新
print_info "配置自动安全更新..."
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# 15. 安装 fail2ban
print_info "安装并配置 fail2ban..."
apt install -y fail2ban
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
EOF
systemctl enable --now fail2ban

# 16. 内核参数加固
print_info "应用内核安全参数..."
cat > /etc/sysctl.d/99-hardening.conf <<EOF
kernel.yama.ptrace_scope = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
EOF
sysctl --system

# 17. 日志持久化
print_info "配置 systemd 日志持久化..."
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald

# 18. 检查 AppArmor 状态
print_info "AppArmor 状态:"
aa-status || print_warn "AppArmor 未激活或未安装。"

# ========== 最终状态检测 ==========
print_info "========== 最终状态检测 =========="

print_info "当前系统监听的端口（LISTEN 状态）:"
ss -tulpn | grep LISTEN || echo "无监听端口"

print_info "关键服务运行状态:"
declare -A VERSIONS
services=("ssh" "fail2ban" "ufw")
if [[ "$INSTALL_NGINX" == "yes" ]]; then
    services+=("nginx")
    VERSIONS["nginx"]=$(nginx -v 2>&1 | awk '{print $3}' || echo "未知")
fi
if [[ "$INSTALL_SINGBOX" == "yes" ]]; then
    services+=("sing-box")
    VERSIONS["sing-box"]=$(sing-box version 2>/dev/null | head -n1 || echo "未知")
fi
if [[ "$INSTALL_CLOUDFLARED" == "yes" ]]; then
    services+=("cloudflared")
    VERSIONS["cloudflared"]=$(cloudflared version 2>/dev/null | head -n1 || echo "未知")
fi

for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        echo "  - $svc: 运行中"
    else
        echo "  - $svc: 未运行"
    fi
done

# 打印汇总信息
print_info "========== 配置汇总 =========="
echo "  创建的用户名: ${SSH_USER}"
echo "  SSH 端口: ${SSH_PORT}"
echo "  SSH 登录方式: 密码 (请妥善保管)"
echo "  1panel 端口放行: ${ALLOW_1PANEL} (端口: ${PANEL_PORT:-无})"
echo "  Nginx 安装: ${INSTALL_NGINX}"
if [[ "$INSTALL_NGINX" == "yes" ]]; then
    echo "  Nginx 版本: ${VERSIONS["nginx"]}"
    echo "  Nginx 端口放行: ${ALLOW_NGINX_PORTS}"
fi
echo "  sing-box 安装: ${INSTALL_SINGBOX}"
if [[ "$INSTALL_SINGBOX" == "yes" ]]; then
    echo "  sing-box 版本: ${VERSIONS["sing-box"]}"
fi
echo "  cloudflared 安装: ${INSTALL_CLOUDFLARED}"
if [[ "$INSTALL_CLOUDFLARED" == "yes" ]]; then
    echo "  cloudflared 版本: ${VERSIONS["cloudflared"]}"
fi
echo "  Fail2ban 状态: $(systemctl is-active fail2ban)"
echo "  UFW 状态: $(ufw status | head -n1)"

# 询问是否重启
print_info "所有配置已完成。建议重启系统以应用全部更改。"
print_question "是否立即重启？(y/N): "
read -r do_reboot
if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
    print_info "系统将在 10 秒后重启..."
    sleep 10
    reboot
else
    print_info "请记得稍后手动重启系统以应用所有更改。"
fi

print_info "========== 脚本执行完毕 =========="
