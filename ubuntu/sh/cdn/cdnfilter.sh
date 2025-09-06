#!/usr/bin/env bash
# ==========================================================
# CDN 域名硬筛选器 – 兼容 curl | sudo bash 直接管道执行的版本
# ==========================================================
# ① 不用自定义文件描述符；② 全部采用临时文件；③ 主逻辑无FD依赖；④ 支持直接管道 sudo
set -o pipefail
exec 2>&1

DOMAIN_URL="https://raw.githubusercontent.com/zatte-flow/tools/refs/heads/main/ubuntu/sh/cdn/domains.txt"

DEST_DIR="/tmp/cdn"
QUAL_FILE="$DEST_DIR/qualified-domains.txt"
QUAL_ONLY="$DEST_DIR/qualified-domains-only.txt"

# 目录 & 空文件
mkdir -p "$DEST_DIR" 2>/dev/null || sudo mkdir -p "$DEST_DIR"
> "$QUAL_FILE" 2>/dev/null || sudo touch "$QUAL_FILE" "$QUAL_ONLY"

# 依赖检查（缺失直接退出）
for cmd in curl openssl dig; do
  command -v "$cmd" >/dev/null || { echo "❌ 缺少 $cmd"; exit 1; }
done

# 下载域名列表
TMP_LIST=$(mktemp)
curl -fsSL "$DOMAIN_URL" -o "$TMP_LIST" || { echo "❌ 下载失败"; exit 2; }
[ -s "$TMP_LIST" ] || { echo "❌ 列表为空"; exit 3; }
trap "rm -f $TMP_LIST" EXIT

# 用临时文件遍历每个域名，避免文件描述符
while IFS= read -r domain || [ -n "$domain" ]; do
  [ -z "$domain" ] && continue
  echo -n "🔍  $domain  "

  # 1. TLS
  tls_out=$(timeout 5 openssl s_client -connect "$domain":443 -tls1_3 -alpn h2 </dev/null 2>&1)
  ok_tls=$(echo "$tls_out" | grep -Ec 'TLSv1.3|X25519|ALPN.*h2' || true)
  [ "$ok_tls" -lt 3 ] && { echo "❌ TLS"; continue; }

  # 2. 证书链
  depth=$(timeout 5 openssl s_client -connect "$domain":443 -showcerts 2>/dev/null |
          awk '/Certificate chain/,/---/' | grep -Ec '^ [0-9] s:' || true)
  [ "$depth" -gt 2 ] && { echo "❌ 证书链深度=$depth"; continue; }

  # 3. 无 301/302
  codes=$(curl -sIL -m 5 -w '%{http_code}\n' "https://$domain" -o /dev/null | grep -E '^30[12]' || true)
  [ -n "$codes" ] && { echo "❌ 跳转 $codes"; continue; }

  # 4. 跳 www/国别
  loc=$(curl -sI -m 5 "https://$domain" | awk -F': ' '/^[Ll]ocation:/ {print $2}' | tr -d '\r' || true)
  case "$loc" in
    http*//www.*|http*//*.cn|http*//*.com.cn|http*//*.co.uk) echo "❌ 跳转到 $loc"; continue ;;
  esac

  # 5. 海外 IP
  ip=$(dig +short A "$domain" | head -1 || true)
  [ -z "$ip" ] && { echo "❌ 解析失败"; continue; }
  country=$(timeout 3 curl -s "http://ip-api.com/line/$ip?fields=countryCode" 2>/dev/null || true)
  [ "$country" = "CN" ] && { echo "❌ 国内IP($ip)"; continue; }

  # 6. 404 空页面
  sz=$(curl -s --max-time 5 "https://$domain/nonexist" | wc -c || true)
  [ "$sz" -eq 0 ] && { echo "❌ 404空页面"; continue; }

  # 7. RTT
  rtt=$(ping -c3 -W1 -q "$domain" 2>/dev/null | awk -F'/' 'END{print $5}' || true)
  [ -z "$rtt" ] && rtt=999
  printf "%.1f ms\n" "$rtt"
  echo "$rtt $domain" >> "$QUAL_FILE"
done < "$TMP_LIST"

# 8. 排序（临时文件方案，永不出错）
echo "===== SORT DIAG: $(sort --version | head -1) ====="
sort -n -k1,1 "$QUAL_FILE" > "$QUAL_FILE.tmp" && mv "$QUAL_FILE.tmp" "$QUAL_FILE"
cut -d' ' -f2 "$QUAL_FILE" > "$QUAL_ONLY"

# 9. 总结（用 cat 强制输出，避免任何变量扩展失败）
cnt=$(wc -l < "$QUAL_FILE" || echo 0)
cat <<EOF
✅ 完成！共 $cnt 个合格域名
   带延时  : $QUAL_FILE
   仅域名  : $QUAL_ONLY
EOF
