### 1、脚本（任选其一）

- Ubuntu 22.04 正常运行

```bash
# 检查后，自动生成告警摘要日志（quick-audit.sh） 
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/sec-tools-v2.sh | sudo bash

# 旧版，无自动生成告警摘要日志
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/sec-tools.sh | sudo bash
```

### 2、下载脚本后本地运行

```bash
# 赋权 & 执行
chmod +x sec-tools-v2.sh && sudo ./sec-tools-v2.sh
```

### 3、提取本周报告核心信息（需 sec-tools.sh 自动执行完后，v2 版自动执行）

```bash
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/quick-audit.sh | sudo bash
```

### 4、清理系统

```bash
# 22.04
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/clear.sh | sudo bash

# 24.04版
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/clean-2404.sh | sudo bash
```

### 5、卸载

```bash
sudo apt-get purge -y wazuh-agent lynis rkhunter chkrootkit && sudo rm -rf /var/ossec /etc/ossec-init.conf /var/log/weekly-sec /usr/local/bin/weekly-sec.sh && sudo rm -f /etc/apt/sources.list.d/wazuh.list /etc/apt/trusted.gpg.d/wazuh.gpg && sudo crontab -l 2>/dev/null | grep -v '/usr/local/bin/weekly-sec.sh' | sudo crontab - || true
```
