### CDN 域名筛选器

一键筛选支持  
TLS1.3 + X25519 + ALPN=h2、证书链≤2、30 天无跳转、404 页面正常的 CDN 域名，并按延时排序。

### 远程直接跑
```bash
# 下载
curl -fsSL https://raw.githubusercontent.com/zatte-flow/tools/main/ubuntu/sh/cdn/cdnfilter.sh -o /tmp/cdnfilter.sh

# 执行
sudo bash /tmp/cdnfilter.sh

