#!/usr/bin/env bash
# ==========================================================
# CDN 域名硬筛选器 – 必须在线拉取 domains.txt，无内置
# 输出目录：/tmp/cdn
# 一行流：
#   bash <(curl -fsSL https://your-server.tld/cdnfilter.sh)
# ==========================================================
set -euo pipefail

##############  唯一需要改的变量  ################
# 把下面换成你能确保海外服务器可通的 raw 地址
DOMAIN_URL="https://cdn.jsdelivr.net/gh/zatte-flow/tools@refs/heads/main/ubuntu/sh/cdn/domains.txt"
#################################################

DEST_DIR="/tmp/cdn"
QUAL_FILE="$DEST_DIR/qualified-domains.txt"
QUAL_ONLY="$DEST_DIR/qualified-domains-only.txt"

# 1. 保证输出目录
[ -d "$DEST_DIR" ] || mkdir -p "$DEST_DIR" 2>/dev/null || sudo mkdir -p "$DEST_DIR"
touch "$QUAL_FILE" 2>/dev/null || sudo touch "$QUAL_FILE" "$QUAL_ONLY"

# 2. 依赖检查
for cmd in curl openssl dig; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装 $cmd"; exit 1; }
done

# 3. 拉取域名列表（必须成功且非空）
TMP_LIST=$(mktemp)
if ! curl -fsSL "$DOMAIN_URL" -o "$TMP_LIST"; then
  echo "❌ 下载域名列表失败：$DOMAIN_URL"
  exit 2
fi
[ -s "$TMP_LIST" ] || { echo "❌ 域名列表为空"; exit 3; }
INPUT="$TMP_LIST"
trap "rm -f $TMP_LIST" EXIT

# 4. 清空旧结果
> "$QUAL_FILE"

while read -r domain; do
  [ -z "$domain" ] && continue
  echo -n "🔍  $domain  "

  # ---- 1. TLS1.3 + X25519 + ALPN=h2 ----
  tls_out=$(timeout 5 openssl s_client -connect "$domain":443 -tls1_3 -alpn h2 </dev/null 2>&1)
  ok_tls=$(echo "$tls_out" | grep -Ec 'TLSv1.3|X25519|ALPN.*h2')
  [ "$ok_tls" -lt 3 ] && { echo "❌ TLS"; continue; }

  # ---- 2. 证书链深度 ≤2 ----
  depth=$(timeout 5 openssl s_client -connect "$domain":443 -showcerts 2>/dev/null |
          awk '/Certificate chain/,/---/' | grep -Ec '^ [0-9] s:')
  [ "$depth" -gt 2 ] && { echo "❌ 证书链深度=$depth"; continue; }

  # ---- 3. 严格无 301/302 ----
  codes=$(curl -sIL -m 5 -w '%{http_code}\n' "https://$domain" -o /dev/null | grep -E '^30[12]')
  [ -n "$codes" ] && { echo "❌ 跳转 $codes"; continue; }

  # ---- 4. 拒绝跳 www / 国别子域 ----
  loc=$(curl -sI -m 5 "https://$domain" | awk -F': ' '/^[Ll]ocation:/ {print $2}' | tr -d '\r')
  case "$loc" in
    http*//www.*|http*//*.cn|http*//*.com.cn|http*//*.co.uk)
      echo "❌ 跳转到 $loc"; continue ;;
  esac

  # ---- 5. 海外 IP（非 CN） ----
  ip=$(dig +short A "$domain" | head -1)
  [ -z "$ip" ] && { echo "❌ 解析失败"; continue; }
  country=$(timeout 3 curl -s "http://ip-api.com/line/$ip?fields=countryCode" 2>/dev/null || true)
  [ "$country" = "CN" ] && { echo "❌ 国内IP($ip)"; continue; }

  # ---- 6. 404 页面存在 ----
  sz=$(curl -s --max-time 5 "https://$domain/nonexist" | wc -c)
  [ "$sz" -eq 0 ] && { echo "❌ 404空页面"; continue; }

  # ---- 7. 测 RTT ----
  rtt=$(ping -c3 -W1 -q "$domain" 2>/dev/null | awk -F'/' 'END{print $5}')
  [ -z "$rtt" ] && rtt=999
  printf "%.1f ms\n" "$rtt"
  echo "$rtt $domain" >> "$QUAL_FILE"

done < "$INPUT"

# 5. 排序 & 纯域名文件
sort -n -k1,1 -o "$QUAL_FILE" "$QUAL_FILE"
cut -d' ' -f2 "$QUAL_FILE" > "$QUAL_ONLY"

echo "✅ 完成！共 $(wc -l < "$QUAL_FILE") 个合格域名"
echo "   带延时  : $QUAL_FILE"
echo "   仅域名  : $QUAL_ONLY"
