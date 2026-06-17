#!/bin/bash
# ============================================
# enlyai SEO 一键部署脚本
# 在阿里云ECS上执行此脚本
# 用法: bash setup-seo.sh
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }

DEPLOY_DIR="/root/new-api"
SEO_DIR="/root/seo-static"

# ============================================
# 第一步：创建静态SEO文件目录
# ============================================
info "1. 创建SEO静态文件目录..."
mkdir -p ${SEO_DIR}

# ============================================
# 第二步：创建 llms.txt
# ============================================
info "2. 创建 llms.txt..."
cat > ${SEO_DIR}/llms.txt <<'LLMS_EOF'
# [enlyai](https://www.enlyai.com)

> enlyai is a unified LLM API gateway that provides developers with access to 100+ large language models through a single OpenAI-compatible API endpoint. Built for developers in China and worldwide, it offers direct access without VPN, Alipay/WeChat payment support, and open-source self-hosting capability.

## What enlyai does

enlyai aggregates LLM APIs from OpenAI, Anthropic, Google, DeepSeek, and 50+ other providers into one unified interface. Developers use one API key to access all models, with automatic failover, load balancing, and consolidated billing. The platform is based on the open-source New API project, enabling private deployment for enterprises with data compliance requirements.

## Key features

- **Unified API**: One OpenAI-compatible endpoint (`/v1/chat/completions`) for all LLM providers — switch models by changing only the `model` parameter
- **Smart Routing & Failover**: Automatic failover and load balancing across providers to ensure high availability
- **Cost Optimization**: Transparent pricing with no markup on provider prices; real-time usage monitoring and cost tracking dashboard
- **Multi-modal Support**: Text chat, image generation, audio transcription, video generation, embeddings, and reranking
- **China-friendly**: Direct access without VPN; Alipay and WeChat payment support; Chinese-language dashboard
- **Open Source**: Based on the New API open-source project; supports private/self-hosted deployment for data compliance
- **Developer Tools**: Compatible with Cursor, Cherry Studio, Claude Code, ChatBox, NextChat, Dify, and other AI tools
- **Check-in Rewards**: Daily check-in for free quota; invitation rewards for both inviter and invitee
- **Subscription Plans**: Flexible pay-per-use and subscription billing options

## Supported providers

OpenAI (GPT-4o, GPT-5, o3, DALL-E), Anthropic (Claude Opus 4, Claude Sonnet 4), Google (Gemini 2.5 Pro, Gemini 3), DeepSeek (DeepSeek-V3, DeepSeek-R1), Mistral AI, xAI (Grok), Alibaba (Qwen), Zhipu AI (GLM), Moonshot AI (Kimi), MiniMax, Cohere, Cloudflare Workers AI, AWS Bedrock, Azure OpenAI, Vertex AI, Ollama, and 30+ more.

## Getting started

1. Sign up at https://www.enlyai.com
2. Get your API key from the dashboard
3. Replace your OpenAI base URL with `https://www.enlyai.com/v1`
4. Start calling any model with the same code

### Python example

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-your-enlyai-api-key",
    base_url="https://www.enlyai.com/v1"
)

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### cURL example

```bash
curl https://www.enlyai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-your-enlyai-api-key" \
  -d '{"model": "gpt-4o", "messages": [{"role": "user", "content": "Hello!"}]}'
```

## Pricing

Pay-per-use with no markup on provider prices. Free tier available for new users with sign-up bonus quota. Daily check-in rewards provide ongoing free usage.

## Use cases

- **AI-powered coding**: Use with Cursor, Claude Code, or Windsurf for multi-model code assistance
- **Chat applications**: Build chatbots with model switching capability via Cherry Studio, ChatBox, or NextChat
- **Enterprise AI gateway**: Private deployment for data compliance in finance, healthcare, and government
- **AI application development**: Rapid prototyping with unified API across all providers
- **Cost optimization**: Compare model performance and pricing to find the best value

## Links

- Website: https://www.enlyai.com
- Documentation: https://www.enlyai.com/docs
- GitHub (open-source base): https://github.com/Calcium-Ion/new-api
LLMS_EOF

# ============================================
# 第三步：创建 robots.txt
# ============================================
info "3. 创建 robots.txt..."
cat > ${SEO_DIR}/robots.txt <<'ROBOTS_EOF'
# https://www.robotstxt.org/robotstxt.html
User-agent: *
Allow: /
Disallow: /api/
Disallow: /panel/
Disallow: /v1/

Sitemap: https://www.enlyai.com/sitemap.xml
ROBOTS_EOF

# ============================================
# 第四步：创建 sitemap.xml
# ============================================
info "4. 创建 sitemap.xml..."
cat > ${SEO_DIR}/sitemap.xml <<'SITEMAP_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://www.enlyai.com/</loc>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/login</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/register</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/pricing</loc>
    <changefreq>weekly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/models</loc>
    <changefreq>weekly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/docs</loc>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://www.enlyai.com/about</loc>
    <changefreq>monthly</changefreq>
    <priority>0.5</priority>
  </url>
</urlset>
SITEMAP_EOF

# ============================================
# 第五步：更新 nginx 配置，添加SEO静态文件服务
# ============================================
info "5. 更新 nginx 配置..."

# 检查当前nginx配置文件
NGINX_CONF="${DEPLOY_DIR}/nginx/conf.d/default.conf"

if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${YELLOW}[WARN]${NC} 未找到 nginx 配置文件: $NGINX_CONF"
    echo "请手动添加以下 location 块到你的 nginx 配置中："
    echo ""
    echo "--- 在 server 块内添加 ---"
    echo ""
    cat <<'NGINX_LOCATION'
    # SEO static files - served directly by nginx
    location = /llms.txt {
        alias /root/seo-static/llms.txt;
        default_type text/plain;
        add_header Cache-Control "public, max-age=86400";
    }

    location = /robots.txt {
        alias /root/seo-static/robots.txt;
        default_type text/plain;
        add_header Cache-Control "public, max-age=86400";
    }

    location = /sitemap.xml {
        alias /root/seo-static/sitemap.xml;
        default_type application/xml;
        add_header Cache-Control "public, max-age=86400";
    }
NGINX_LOCATION
    echo ""
    echo "--- 结束 ---"
else
    # 检查是否已添加SEO配置
    if grep -q "llms.txt" "$NGINX_CONF"; then
        info "nginx 配置已包含SEO location块，跳过"
    else
        # 在第一个 location 块之前插入SEO配置
        # 找到 HTTPS server 块中的第一个 location 并在其之前插入
        if grep -q "listen 443" "$NGINX_CONF"; then
            # HTTPS配置存在，在443 server块的第一个location前插入
            sed -i '/listen 443/,/location/ {
                /location/i\
    # SEO static files - served directly by nginx\
    location = /llms.txt {\
        alias /root/seo-static/llms.txt;\
        default_type text/plain;\
        add_header Cache-Control "public, max-age=86400";\
    }\
\
    location = /robots.txt {\
        alias /root/seo-static/robots.txt;\
        default_type text/plain;\
        add_header Cache-Control "public, max-age=86400";\
    }\
\
    location = /sitemap.xml {\
        alias /root/seo-static/sitemap.xml;\
        default_type application/xml;\
        add_header Cache-Control "public, max-age=86400";\
    }\

            }' "$NGINX_CONF"
            info "已更新nginx HTTPS配置"
        else
            # HTTP配置，在80 server块的第一个location前插入
            sed -i '/server_name.*enlyai/,/location/ {
                /location/i\
    # SEO static files - served directly by nginx\
    location = /llms.txt {\
        alias /root/seo-static/llms.txt;\
        default_type text/plain;\
        add_header Cache-Control "public, max-age=86400";\
    }\
\
    location = /robots.txt {\
        alias /root/seo-static/robots.txt;\
        default_type text/plain;\
        add_header Cache-Control "public, max-age=86400";\
    }\
\
    location = /sitemap.xml {\
        alias /root/seo-static/sitemap.xml;\
        default_type application/xml;\
        add_header Cache-Control "public, max-age=86400";\
    }\

            }' "$NGINX_CONF"
            info "已更新nginx HTTP配置"
        fi
    fi
fi

# ============================================
# 第六步：重启 nginx
# ============================================
info "6. 重启 nginx..."
cd ${DEPLOY_DIR}
docker compose -f docker-compose.prod.yml restart nginx

info "等待 nginx 启动..."
sleep 5

# ============================================
# 第七步：验证
# ============================================
info "7. 验证SEO文件..."
echo ""

echo "--- llms.txt ---"
curl -s https://www.enlyai.com/llms.txt | head -5
echo ""

echo "--- robots.txt ---"
curl -s https://www.enlyai.com/robots.txt
echo ""

echo "--- sitemap.xml ---"
curl -s https://www.enlyai.com/sitemap.xml | head -5
echo ""

info "========================================="
info "SEO 部署完成！"
info "========================================="
info ""
info "后续操作："
info "1. 提交 sitemap 到 Google Search Console: https://search.google.com/search-console"
info "2. 提交站点到百度站长平台: https://ziyuan.baidu.com"
info "3. 提交站点到 Bing Webmaster Tools: https://www.bing.com/webmasters"
info "4. 用 Google Rich Results Test 验证结构化数据: https://search.google.com/test/rich-results"
info ""
info "注意：index.html 中的 JSON-LD 和 meta 标签需要重建 Docker 镜像才能生效"
info "当前 nginx 已直接提供 llms.txt / robots.txt / sitemap.xml"
