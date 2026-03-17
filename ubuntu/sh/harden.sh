#!/bin/bash
#
# Ubuntu 24.04 安全加固脚本（最终版）
# 默认用户名: next-flow, 默认 SSH 端口: 58639, 默认 1panel 端口: 52936
# 功能: 可选安装 Nginx/sing-box/cloudflared，可选放行 1panel 端口（可自定义）
# 流程: Root 执行基础准备 -> 验证用户权限 -> 新用户通过 sudo 安装应用
# 请使用 root 用户或具有 sudo 权限的用户运行
#

set -euo pipefail

# 彩色输出函数
print_info() {
    echo -e "\e[32m[INFO]\e[0m $1"
}
print_warn() {
    echo -e "\e[33m[WARN]\e[0m $1"
}
print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}
print_question() {
    echo -e "\e[36m[QUESTION]\e[0m $1"
}

# 检查是否 root
if [[ $EUID -ne 0 ]]; then
    print_error "请使用 sudo 或以 root 用户运行此脚本。"
    exit 1
fi

# 固定默认值
DEFAULT_USER="next-flow"
DEFAULT_PORT=58639
DEFAULT_1PANEL_PORT=52936

# 检查默认 SSH 端口是否被占用
if ss -tuln | grep -q ":$DEFAULT_PORT "; then
    print_error "默认 SSH 端口 $DEFAULT_PORT 已被占用，请修改为其他端口。"
    exit 1
fi

# 检查默认用户名是否已存在
if id "$DEFAULT_USER" &>/dev/null; then
    print_warn "默认用户 $DEFAULT_USER 已存在，后续将跳过创建步骤。"
fi

# ========== 交互式配置收集 ==========
print_question "请输入要创建的普通管理员用户名 [默认: ${DEFAULT_USER}]: "
read -r SSH_USER_INPUT
SSH_USER="${SSH_USER_INPUT:-$DEFAULT_USER}"
print_info "用户名设置为: ${SSH_USER}"

print_question "请输入新的 SSH 监听端口 (必须大于50000) [默认: ${DEFAULT_PORT}]: "
read -r SSH_PORT_INPUT
if [[ -z "$SSH_PORT_INPUT" ]]; then
    SSH_PORT="$DEFAULT_PORT"
    print_info "使用默认端口: ${SSH_PORT}"
else
    if [[ "$SSH_PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$SSH_PORT_INPUT" -gt 50000 ]] && [[ "$SSH_PORT_INPUT" -le 65535 ]]; then
        SSH_PORT="$SSH_PORT_INPUT"
        if ss -tuln | grep -q ":$SSH_PORT "; then
            print_error "端口 $SSH_PORT 已被占用，请选择其他端口。"
            exit 1
        fi
        print_info "SSH端口设置为: ${SSH_PORT}"
    else
        print_error "端口号必须是 50001-65535 之间的数字，使用默认端口: ${DEFAULT_PORT}"
        SSH_PORT="$DEFAULT_PORT"
    fi
fi

# 1panel 端口询问
ALLOW_1PANEL="no"
PANEL_PORT=""
print_question "是否预留 1panel 面板端口（防火墙放行）？(y/N): "
read -r ALLOW_1PANEL_INPUT
if [[ "$ALLOW_1PANEL_INPUT" =~ ^[Yy]$ ]]; then
    ALLOW_1PANEL="yes"
    print_question "请输入 1panel 面板端口 [默认: ${DEFAULT_1PANEL_PORT}]: "
    read -r PANEL_PORT_INPUT
    if [[ -z "$PANEL_PORT_INPUT" ]]; then
        PANEL_PORT="$DEFAULT_1PANEL_PORT"
        print_info "使用默认 1panel 端口: ${PANEL_PORT}"
    else
        if [[ "$PANEL_PORT_INPUT" =~ ^[0-9]+$ ]] && [[ "$PANEL_PORT_INPUT" -ge 1 ]] && [[ "$PANEL_PORT_INPUT" -le 65535 ]]; then
            PANEL_PORT="$PANEL_PORT_INPUT"
            print_info "1panel 端口设置为: ${PANEL_PORT}"
        else
            print_error "端口号无效，使用默认端口: ${DEFAULT_1PANEL_PORT}"
            PANEL_PORT="$DEFAULT_1PANEL_PORT"
        fi
    fi
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

# Cloudflared 安装询问
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

# ========== 第一阶段：基础系统准备 (以 root 执行) ==========
print_info "========== 第一阶段：基础系统准备 (Root) =========="

# 1. 系统更新
print_info "更新软件包列表并升级所有软件..."
apt update && apt upgrade -y

# 2. 安装必要工具
print_info "安装常用工具（curl、wget、ufw 等）..."
apt install -y curl wget software-properties-common gnupg2 ufw

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

# 5. 创建用户并加入 sudo 组
print_info "创建用户 ${SSH_USER} 并加入 sudo 组..."
if id "${SSH_USER}" &>/dev/null; then
    print_warn "用户 ${SSH_USER} 已存在，跳过创建。"
else
    useradd -m -s /bin/bash -G sudo "${SSH_USER}"
    passwd "${SSH_USER}"
    print_info "用户 ${SSH_USER} 创建成功。"
fi

# 6. SSH 服务加固（先修改配置，稍后重启）
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

# 7. 防火墙放行 SSH 端口
print_info "防火墙放行 SSH 端口 ${SSH_PORT}..."
ufw allow "${SSH_PORT}/tcp" comment "SSH custom port"
if [[ "$ALLOW_1PANEL" == "yes" && -n "$PANEL_PORT" ]]; then
    print_info "防火墙放行 1panel 端口 ${PANEL_PORT}..."
    ufw allow "${PANEL_PORT}/tcp" comment "1panel panel"
fi
ufw --force enable
ufw status verbose

# 8. 重启 SSH 服务应用配置
print_info "重启 SSH 服务以应用新配置..."
systemctl restart sshd
print_info "SSH 服务已重启，请使用端口 ${SSH_PORT} 连接（保留密码认证）。"

# 9. 验证新用户 sudo 权限（关键步骤）
print_info "验证用户 ${SSH_USER} 的 sudo 权限..."
if su - "${SSH_USER}" -c "sudo whoami" | grep -q "root"; then
    print_info "用户 ${SSH_USER} sudo 权限验证成功。"
else
    print_error "用户 ${SSH_USER} sudo 权限验证失败，请手动检查！脚本退出。"
    exit 1
fi

# ========== 第二阶段：应用安装与服务配置 (以新用户通过 sudo 执行) ==========
print_info "========== 第二阶段：应用安装与服务配置 (User: ${SSH_USER}) =========="

# 辅助函数：以新用户身份执行需要 sudo 的命令
run_as_user() {
    sudo -u "${SSH_USER}" sudo "$@"
}

# 10. 安装 Nginx
if [[ "$INSTALL_NGINX" == "yes" ]]; then
    print_info "安装 Nginx..."
    run_as_user apt install -y nginx
    run_as_user systemctl enable --now nginx
    if [[ "$ALLOW_NGINX_PORTS" == "yes" ]]; then
        print_info "防火墙放行 80/443 端口..."
        run_as_user ufw allow 80/tcp comment "HTTP"
        run_as_user ufw allow 443/tcp comment "HTTPS"
        run_as_user ufw reload
    fi
fi

# 11. 安装 sing-box
if [[ "$INSTALL_SINGBOX" == "yes" ]]; then
    print_info "使用官方脚本安装 sing-box..."
    run_as_user bash -c "$(curl -fsSL https://sing-box.app/install.sh)"
    run_as_user systemctl enable sing-box || print_warn "sing-box 服务无法启用，请手动检查"
fi

# 12. 安装 cloudflared
if [[ "$INSTALL_CLOUDFLARED" == "yes" ]]; then
    print_info "安装 cloudflared..."
    run_as_user bash -c "mkdir -p --mode=0755 /usr/share/keyrings"
    run_as_user bash -c "curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null"
    run_as_user bash -c "echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list"
    run_as_user apt update
    run_as_user apt install -y cloudflared
    if [[ -n "$CLOUDFLARED_TOKEN" ]]; then
        print_info "使用提供的 token 安装隧道服务..."
        run_as_user cloudflared service install "$CLOUDFLARED_TOKEN"
    fi
fi

# 13. 自动安全更新
print_info "配置自动安全更新..."
run_as_user apt install -y unattended-upgrades
run_as_user dpkg-reconfigure -plow unattended-upgrades

# 14. 安装 fail2ban
print_info "安装并配置 fail2ban..."
run_as_user apt install -y fail2ban
run_as_user bash -c "cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
EOF"
run_as_user systemctl enable --now fail2ban

# 15. 内核参数加固
print_info "应用内核安全参数..."
run_as_user bash -c "cat > /etc/sysctl.d/99-hardening.conf <<EOF
kernel.yama.ptrace_scope = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
EOF"
run_as_user sysctl --system

# 16. 日志持久化
print_info "配置 systemd 日志持久化..."
run_as_user mkdir -p /var/log/journal
run_as_user systemd-tmpfiles --create --prefix /var/log/journal
run_as_user systemctl restart systemd-journald

# 17. 检查 AppArmor 状态
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
    # 使用确认后的命令获取版本 [citation:3][citation:9]
    VERSIONS["nginx"]=$(su - "${SSH_USER}" -c "nginx -v" 2>&1 | awk '{print $3}' || echo "未知")
fi
if [[ "$INSTALL_SINGBOX" == "yes" ]]; then
    services+=("sing-box")
    # 使用官方指定的 version 命令 [citation:1][citation:7][citation:10]
    VERSIONS["sing-box"]=$(su - "${SSH_USER}" -c "sing-box version" 2>/dev/null | head -n1 || echo "未知")
fi
if [[ "$INSTALL_CLOUDFLARED" == "yes" ]]; then
    services+=("cloudflared")
    # version 和 --version 均可，这里使用 version [citation:2][citation:8]
    VERSIONS["cloudflared"]=$(su - "${SSH_USER}" -c "cloudflared version" 2>/dev/null | head -n1 || echo "未知")
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
