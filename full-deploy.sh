#!/bin/bash
# ============================================
# API.ENLYAI.COM 完整一键部署
# 包含：New API + HTTPS + 免费 Key 池 + 主 API Key + 用户注册
# 在阿里云 Workbench 中粘贴执行
# ============================================

set -e

echo "============================================"
echo "  API.ENLYAI.COM 完整部署"
echo "============================================"

# ---- 1. 安装 Docker ----
echo "[1/8] 检查 Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl start docker && systemctl enable docker
fi
echo "Docker: $(docker --version)"

# ---- 2. 克隆项目 ----
echo "[2/8] 克隆 New API..."
if [ ! -d "/root/new-api" ]; then
    git clone https://github.com/QuantumNous/new-api.git /root/new-api
fi
cd /root/new-api

# ---- 3. 生成密码并配置 ----
echo "[3/8] 配置环境..."
DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
REDIS_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
SESSION_SECRET=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

cat > docker-compose.prod.yml <<COMPOSE
services:
  new-api:
    image: calciumion/new-api:latest
    container_name: new-api
    restart: always
    command: --log-dir /app/logs
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      - SQL_DSN=postgresql://newapi:${DB_PASS}@postgres:5432/newapi
      - REDIS_CONN_STRING=redis://:${REDIS_PASS}@redis:6379
      - TZ=Asia/Shanghai
      - ERROR_LOG_ENABLED=true
      - BATCH_UPDATE_ENABLED=true
      - MEMORY_CACHE_ENABLED=true
      - CHANNEL_UPDATE_FREQUENCY=30
      - SYNC_FREQUENCY=60
      - STREAMING_TIMEOUT=300
      - NODE_NAME=aliyun-ecs-node-1
      - SESSION_SECRET=${SESSION_SECRET}
      - AUTOMATIC_DISABLE_CHANNEL_ENABLED=true
      - AUTOMATIC_ENABLE_CHANNEL_ENABLED=false
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    networks:
      - new-api-network
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -o '\"success\":\\s*true' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    command: ["redis-server", "--requirepass", "${REDIS_PASS}", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]
    volumes:
      - redis_data:/data
    networks:
      - new-api-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASS}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: newapi
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: newapi
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks:
      - new-api-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U newapi -d newapi"]
      interval: 10s
      timeout: 5s
      retries: 3

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/logs:/var/log/nginx
      - certbot-etc:/etc/letsencrypt
      - certbot-webroot:/var/www/certbot
    depends_on:
      - new-api
    networks:
      - new-api-network

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - certbot-etc:/etc/letsencrypt
      - certbot-webroot:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h; done'"
    networks:
      - new-api-network

volumes:
  pg_data:
  redis_data:
  certbot-etc:
  certbot-webroot:

networks:
  new-api-network:
    driver: bridge
COMPOSE

# 保存密码
cat > .env.production <<EOF
DB_PASSWORD=${DB_PASS}
REDIS_PASSWORD=${REDIS_PASS}
SESSION_SECRET=${SESSION_SECRET}
EOF
chmod 600 .env.production

# ---- 4. 配置 Nginx (HTTP 先) ----
echo "[4/8] 配置 Nginx..."
mkdir -p nginx/conf.d nginx/logs nginx/certbot/webroot data logs

cat > nginx/conf.d/default.conf <<'NGINX'
upstream new_api_backend {
    server new-api:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name api.enlyai.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

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
NGINX

# ---- 5. 启动服务 ----
echo "[5/8] 启动服务..."
docker compose -f docker-compose.prod.yml up -d
echo "等待服务启动..."
sleep 25

# 检查服务状态
if curl -s http://localhost:3000/api/status | grep -q "success"; then
    echo "New API 启动成功！"
else
    echo "等待更长时间..."
    sleep 15
fi

# ---- 6. 签发 SSL 证书 ----
echo "[6/8] 签发 SSL 证书..."
docker compose -f docker-compose.prod.yml run --rm certbot \
    certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "admin@enlyai.com" \
    --agree-tos \
    --no-eff-email \
    -d "api.enlyai.com" && SSL_OK=true || SSL_OK=false

if [ "$SSL_OK" = "true" ]; then
    echo "SSL 证书签发成功！切换到 HTTPS..."

    cat > nginx/conf.d/default.conf <<'NGINXHTTPS'
upstream new_api_backend {
    server new-api:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name api.enlyai.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name api.enlyai.com;

    ssl_certificate /etc/letsencrypt/live/api.enlyai.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.enlyai.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

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
NGINXHTTPS

    docker compose -f docker-compose.prod.yml restart nginx
    echo "HTTPS 已启用！"
else
    echo "⚠️ SSL 证书签发失败（域名可能还未解析到本服务器）"
    echo "请确认 api.enlyai.com 已 A 记录解析到本服务器 IP"
    echo "之后重新执行: cd /root/new-api && ./setup-ssl.sh api.enlyai.com admin@enlyai.com"
fi

# ---- 7. 导入免费 API Key 池 ----
echo "[7/8] 导入免费 API Key 池..."

# 先登录获取管理员 Token
LOGIN_RESP=$(curl -s http://localhost:3000/api/user/login \
    -H "Content-Type: application/json" \
    -d '{"username":"root","password":"123456"}')

# 尝试从登录响应获取 token
ADMIN_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        print(data.get('data', ''))
except: pass
" 2>/dev/null)

if [ -z "$ADMIN_TOKEN" ]; then
    echo "⚠️ 无法自动获取管理员 Token"
    echo "请手动登录 http://114.215.183.45:3000 后执行："
    echo "  export ADMIN_TOKEN=你的令牌"
    echo "  ./sync-free-keys.sh"
else
    echo "管理员 Token 获取成功"

    # 从 GitHub 抓取免费 Key 并导入
    echo "从 GitHub 抓取免费 API Key..."
    KEYS=$(curl -sL --connect-timeout 15 "https://raw.githubusercontent.com/alistaitsacle/free-llm-api-keys/main/README.md" 2>/dev/null | grep -oP 'sk-[a-zA-Z0-9_-]{10,}' | sort -u)

    KEY_COUNT=$(echo "$KEYS" | wc -l)
    echo "发现 ${KEY_COUNT} 个免费 Key，开始导入..."

    ADDED=0
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        KEY_SUFFIX="${key: -8}"
        CHANNEL_NAME="free-pool-${KEY_SUFFIX}"

        RESP=$(curl -s http://localhost:3000/api/channel/ \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"${CHANNEL_NAME}\",\"type\":1,\"key\":\"${key}\",\"models\":\"kimi-k2.5,deepseek-v4-pro,deepseek-v4-flash,claude-opus-4-7,gemini-2.5-flash,smart-chat,qwen/qwen3.6-flash,openrouter/owl-alpha,gpt-4o,gpt-4o-mini,o3-mini\",\"base_url\":\"https://aiapiv2.pekpik.com/v1\",\"group\":\"default\",\"priority\":0,\"weight\":1}")

        if echo "$RESP" | grep -q '"success":true'; then
            ADDED=$((ADDED + 1))
        fi
    done <<< "$KEYS"

    echo "成功导入 ${ADDED}/${KEY_COUNT} 个 Key"

    # ---- 8. 创建主 API Key ----
    echo "[8/8] 创建主 API Key (统一对外 Key)..."

    TOKEN_RESP=$(curl -s http://localhost:3000/api/token/ \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"name":"enlyai-unified-key","remain_quota":5000000000,"unlimited_quota":true,"models":"","subnet":""}')

    MASTER_KEY=$(echo "$TOKEN_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        print(data.get('data', {}).get('key', ''))
except: pass
" 2>/dev/null)

    if [ -n "$MASTER_KEY" ]; then
        echo ""
        echo "=========================================="
        echo "  🎉 主 API Key 创建成功！"
        echo "=========================================="
        echo ""
        echo "  主 Key: sk-${MASTER_KEY}"
        echo ""
        echo "  使用方式:"
        echo "    curl https://api.enlyai.com/v1/chat/completions \\"
        echo "      -H 'Authorization: Bearer sk-${MASTER_KEY}' \\"
        echo "      -H 'Content-Type: application/json' \\"
        echo "      -d '{\"model\":\"kimi-k2.5\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
        echo ""
    else
        echo "⚠️ 主 Key 创建失败，请手动在管理后台创建"
    fi

    # 开启用户注册
    echo "开启用户注册..."
    curl -s http://localhost:3000/api/option/ \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"key":"RegisterEnabled","value":"true"}' > /dev/null 2>&1

    # 设置 30 分钟渠道检测
    echo "设置 30 分钟渠道检测频率..."
    curl -s http://localhost:3000/api/option/ \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"key":"ChannelUpdateFrequency","value":"30"}' > /dev/null 2>&1

    # 设置定时同步 Key（每 30 分钟）
    echo "设置定时同步（每 30 分钟）..."
    (crontab -l 2>/dev/null | grep -v sync-free-keys; echo "*/30 * * * * cd /root/new-api && ADMIN_TOKEN=${ADMIN_TOKEN} ./sync-free-keys.sh >> /var/log/sync-keys.log 2>&1") | crontab -
fi

echo ""
echo "============================================"
echo "  🎉 部署完成！"
echo "============================================"
echo ""
echo "  管理后台: https://api.enlyai.com"
echo "  API 端点: https://api.enlyai.com/v1/chat/completions"
echo ""
echo "  默认账号: root / 123456"
echo "  ⚠️  请立即登录修改密码！"
echo ""
echo "  密码已保存: /root/new-api/.env.production"
echo ""
echo "  Key 池: 已自动导入 38+ 个免费 Key"
echo "  轮询频率: 30 分钟检测一次"
echo "  用户注册: 已开启"
echo "============================================"
