#!/usr/bin/env bash
# ==========================================================
# CDN 域名硬筛选器 – 本地文件优先，无则下载
# ===========================================================
set -o pipefail
exec 2>&1

##############  默认变量  ################
# ① 本地优先：如果运行脚本时给了参数，就用它；否则下载远程
LOCAL_LIST="${1:-}"                          # 用户给的本地文件
REMOTE_URL="https://raw.githubusercontent.com/zatte-flow/tools/refs/heads/main/ubuntu/sh/cdn/domains.txt"
DEST_DIR="/tmp/cdn"
QUAL_FILE="$DEST_DIR/qualified-domains.txt"
QUAL_ONLY="$DEST_DIR/qualified-domains-only.txt"
##########################################

# 1. 目录准备
mkdir -p "$DEST_DIR" 2>/dev/null || sudo mkdir -p "$DEST_DIR"
> "$QUAL_FILE" 2>/dev/null || sudo touch "$QUAL_FILE" "$QUAL_ONLY"

# 2. 依赖检查
for cmd in curl openssl dig; do
  command -v "$cmd" >/dev/null || { echo "❌ 缺少 $cmd"; exit 1; }
done

# 3. 域名列表来源：本地文件 > 远程下载
if [ -n "$LOCAL_LIST" ]; then
  # 用户给了本地文件
  [ -r "$LOCAL_LIST" ] || { echo "❌ 本地文件不存在或不可读：$LOCAL_LIST"; exit 2; }
  INPUT="$LOCAL_LIST"
  echo "===== 使用本地列表：$LOCAL_LIST ====="
else
  # 没给参数 → 下载远程
  TMP_LIST=$(mktemp)
  curl -fsSL "$REMOTE_URL" -o "$TMP_LIST" || { echo "❌ 下载失败"; exit 3; }
  [ -s "$TMP_LIST" ] || { echo "❌ 远程列表为空"; exit 4; }
  INPUT="$TMP_LIST"
  echo "===== 使用远程列表：$REMOTE_URL ====="
  trap "rm -f $TMP_LIST" EXIT
fi

# 可选：看一眼行数
echo "===== 共 $(wc -l < "$INPUT") 行域名 ====="

# 4. 主循环（你已验证，零改动）
exec 3<"$INPUT"
while read -r domain <&3; do
  [ -z "$domain" ] && continue
  echo -n "🔍  $domain  "

  # 1. TLS
  tls_out=$(timeout 5 openssl s_client -connect "$domain":443 -tls1_3 -alpn h2 </dev/null 2>&1)
  ok_tls=$(echo "$tls_out" | grep -Ec 'TLSv1.3|X25519|ALPN.*h2')
  [ "$ok_tls" -lt 3 ] && { echo "❌ TLS"; continue; }

  # 2. 证书链
  depth=$(timeout 5 openssl s_client -connect "$domain":443 -showcerts 2>/dev/null |
          awk '/Certificate chain/,/---/' | grep -Ec '^ [0-9] s:' || true)
  [ "$depth" -gt 2 ] && { echo "❌ 证书链深度=$depth"; continue; }

  # 3. 无 301/302
  codes=$(curl -sIL -m 5 -w '%{http_code}\n' "https://$domain" -o /dev/null | grep -E '^30[12]' || true)
  [ -n "$codes" ] && { echo "❌ 跳转 $codes"; continue; }

  # 4. 跳 www/国别
  loc=$(curl -sI -m 5 "https://$domain" | awk -F': ' '/^[Ll]ocation:/ {print $2}' | tr -d '\r')
  case "$loc" in
    http*//www.*|http*//*.cn|http*//*.com.cn|http*//*.co.uk) echo "❌ 跳转到 $loc"; continue ;;
  esac

  # 5. 海外 IP
  ip=$(dig +short A "$domain" | head -1)
  [ -z "$ip" ] && { echo "❌ 解析失败"; continue; }
  country=$(timeout 3 curl -s "http://ip-api.com/line/$ip?fields=countryCode" 2>/dev/null || true)
  [ "$country" = "CN" ] && { echo "❌ 国内IP($ip)"; continue; }

  # 6. 404 空页面
  sz=$(curl -s --max-time 5 "https://$domain/nonexist" | wc -c)
  [ "$sz" -eq 0 ] && { echo "❌ 404空页面"; continue; }

  # 7. RTT
  rtt=$(ping -c3 -W1 -q "$domain" 2>/dev/null | awk -F'/' 'END{print $5}' || true)
  [ -z "$rtt" ] && rtt=999
  printf "%.1f ms\n" "$rtt"
  echo "$rtt $domain" >> "$QUAL_FILE"
done
exec 3<&-

# 5. 排序 + 纯域名
sort -n -k1,1 "$QUAL_FILE" > "$QUAL_FILE.tmp" && mv "$QUAL_FILE.tmp" "$QUAL_FILE"
cut -d' ' -f2 "$QUAL_FILE" > "$QUAL_ONLY"

# 6. 总结（必出现）
cnt=$(wc -l < "$QUAL_FILE")
echo "✅ 完成！共 $cnt 个合格域名"
echo "   带延时  : $QUAL_FILE"
echo "   仅域名  : $QUAL_ONLY"
