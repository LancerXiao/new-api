#!/bin/bash
# SSL 证书签发脚本 - 使用 Let's Encrypt (Certbot)
#
# 使用方式:
#   chmod +x setup-ssl.sh
#   ./setup-ssl.sh your-domain.com your-email@example.com
#
# 前提条件:
#   1. 域名已解析到 ECS 公网 IP
#   2. 阿里云安全组已开放 80 和 443 端口
#   3. docker-compose.prod.yml 服务已启动

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

DOMAIN="${1:?用法: $0 <域名> <邮箱>}"
EMAIL="${2:?用法: $0 <域名> <邮箱>}"

info "域名: $DOMAIN"
info "邮箱: $EMAIL"

# 检查域名是否解析到当前服务器
check_dns() {
    info "检查域名解析..."
    PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
    DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -1 || echo "")

    if [ -z "$PUBLIC_IP" ] || [ -z "$DOMAIN_IP" ]; then
        warn "无法验证 DNS 解析，请确保域名已正确解析到本服务器"
    elif [ "$PUBLIC_IP" != "$DOMAIN_IP" ]; then
        error "域名 $DOMAIN 解析到 $DOMAIN_IP，但本机公网 IP 是 $PUBLIC_IP，请先配置 DNS 解析"
    else
        info "DNS 解析正确: $DOMAIN -> $DOMAIN_IP"
    fi
}

# 第一步：先用 HTTP-only 模式启动 Nginx（用于 ACME 验证）
start_http_only() {
    info "启动 HTTP-only Nginx 用于证书验证..."

    # 创建临时 Nginx 配置（只有 HTTP，用于 ACME 验证）
    cat > nginx/conf.d/default.conf <<'HTTPEOF'
upstream new_api_backend {
    server new-api:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    # Let's Encrypt ACME 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求代理到 New API
    location / {
        proxy_pass http://new_api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        client_max_body_size 100m;
    }

    location ~ ^/v1/(chat|completions|audio|images|files) {
        proxy_pass http://new_api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_set_header Accept-Encoding "";
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
HTTPEOF

    # 确保 certbot webroot 目录存在
    mkdir -p nginx/certbot/webroot

    # 重启 Nginx
    docker compose -f docker-compose.prod.yml restart nginx
    sleep 5
    info "HTTP-only Nginx 已启动"
}

# 第二步：签发证书
issue_cert() {
    info "正在签发 Let's Encrypt 证书..."

    docker compose -f docker-compose.prod.yml run --rm certbot \
        certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN"

    if [ $? -eq 0 ]; then
        info "证书签发成功！"
    else
        error "证书签发失败，请检查域名解析和 80 端口是否可访问"
    fi
}

# 第三步：切换到 HTTPS 配置
switch_to_https() {
    info "切换到 HTTPS 配置..."

    cat > nginx/conf.d/default.conf <<EOF
upstream new_api_backend {
    server new-api:3000;
    keepalive 32;
}

# HTTP - Let's Encrypt 验证 + 重定向到 HTTPS
server {
    listen 80;
    server_name ${DOMAIN};

    # Let's Encrypt ACME 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 健康检查
    location /health {
        proxy_pass http://new_api_backend/api/status;
        access_log off;
    }

    # 强制 HTTPS 重定向
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS - 主服务
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # Let's Encrypt 证书
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

    # 主代理
    location / {
        proxy_pass http://new_api_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";

        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        client_max_body_size 100m;
    }

    # API 流式端点
    location ~ ^/v1/(chat|completions|audio|images|files) {
        proxy_pass http://new_api_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";

        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_set_header Accept-Encoding "";
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    # 重启 Nginx 加载 HTTPS 配置
    docker compose -f docker-compose.prod.yml restart nginx
    sleep 5
    info "HTTPS 配置已生效"
}

# 设置自动续期
setup_renewal() {
    info "设置证书自动续期（crontab）..."

    # 创建续期脚本
    cat > renew-cert.sh <<'RENEWEOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose -f docker-compose.prod.yml run --rm certbot renew
docker compose -f docker-compose.prod.yml exec nginx nginx -s reload
echo "[$(date)] 证书续期检查完成" >> ssl-renewal.log
RENEWEOF
    chmod +x renew-cert.sh

    # 添加 crontab（每天凌晨 3 点检查续期）
    (crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/renew-cert.sh") | sort -u | crontab -

    info "自动续期已设置（每天凌晨 3:00 检查）"
}

# 显示结果
show_result() {
    echo ""
    echo "=========================================="
    info "HTTPS 配置完成！"
    echo "=========================================="
    echo ""
    info "访问地址: https://${DOMAIN}"
    info "API 端点: https://${DOMAIN}/v1/chat/completions"
    echo ""
    info "证书位置: /etc/letsencrypt/live/${DOMAIN}/"
    info "证书有效期: 90 天（自动续期已配置）"
    echo ""
    info "测试 API:"
    echo "  curl https://${DOMAIN}/v1/chat/completions \\"
    echo "    -H 'Authorization: Bearer sk-your-token' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
    echo "=========================================="
}

# 主流程
main() {
    check_dns
    start_http_only
    issue_cert
    switch_to_https
    setup_renewal
    show_result
}

main "$@"
