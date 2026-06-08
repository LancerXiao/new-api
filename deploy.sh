#!/bin/bash
# New API 一键部署脚本 - 阿里云 ECS
# 使用方式:
#   ./deploy.sh              # 仅 HTTP 部署
#   ./deploy.sh --ssl domain email  # 部署并配置 HTTPS

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 解析参数
ENABLE_SSL=false
SSL_DOMAIN=""
SSL_EMAIL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --ssl)
            ENABLE_SSL=true
            SSL_DOMAIN="${2:?--ssl 需要域名参数}"
            SSL_EMAIL="${3:?--ssl 需要邮箱参数}"
            shift 3
            ;;
        --help|-h)
            echo "用法: $0 [--ssl 域名 邮箱]"
            echo "  无参数: 仅 HTTP 部署"
            echo "  --ssl: 部署后自动签发 Let's Encrypt 证书"
            exit 0
            ;;
        *)
            error "未知参数: $1"
            ;;
    esac
done

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        warn "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com | sh
        systemctl start docker
        systemctl enable docker
        info "Docker 安装完成"
    else
        info "Docker 已安装: $(docker --version)"
    fi

    if ! command -v docker compose &> /dev/null; then
        warn "Docker Compose 未安装，正在安装..."
        apt-get update && apt-get install -y docker-compose-plugin 2>/dev/null || {
            mkdir -p /usr/local/lib/docker/cli-plugins
            curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
            chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        }
        info "Docker Compose 安装完成"
    else
        info "Docker Compose 已安装: $(docker compose version)"
    fi
}

# 生成随机密码
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 24
}

# 配置环境变量
configure_env() {
    info "正在配置环境变量..."

    DB_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    SESSION_SECRET=$(generate_password)

    # 替换 docker-compose.prod.yml 中的默认密码
    sed -i "s/YourStrongPassword123!/${DB_PASSWORD}/g" docker-compose.prod.yml
    sed -i "s/YourRedisPassword123!/${REDIS_PASSWORD}/g" docker-compose.prod.yml
    sed -i "s/change_this_to_a_random_string_in_production/${SESSION_SECRET}/g" docker-compose.prod.yml

    info "数据库密码: ${DB_PASSWORD}"
    info "Redis 密码: ${REDIS_PASSWORD}"
    info "Session 密钥: ${SESSION_SECRET}"

    # 保存密码到文件（仅 root 可读）
    cat > .env.production <<EOF
# New API 生产环境密码（请妥善保管）
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
SESSION_SECRET=${SESSION_SECRET}
EOF
    chmod 600 .env.production
    info "密码已保存到 .env.production（权限 600）"
}

# 配置阿里云安全组提示
show_security_group_tip() {
    echo ""
    echo "=========================================="
    warn "请确保阿里云 ECS 安全组已开放以下端口："
    echo "  - 80   (HTTP)"
    echo "  - 443  (HTTPS)"
    echo "  - 3000 (New API 直接访问，可选)"
    echo "=========================================="
    echo ""
}

# 启动服务
start_services() {
    info "正在拉取镜像并启动服务..."
    docker compose -f docker-compose.prod.yml up -d

    info "等待服务启动..."
    sleep 15

    # 检查服务状态
    docker compose -f docker-compose.prod.yml ps
}

# 配置 SSL 证书
setup_ssl() {
    info "正在配置 HTTPS..."

    if [ "$ENABLE_SSL" = true ]; then
        ./setup-ssl.sh "$SSL_DOMAIN" "$SSL_EMAIL"
    else
        echo ""
        warn "未启用 HTTPS。如需配置，请运行："
        echo "  ./setup-ssl.sh your-domain.com your-email@example.com"
    fi
}

# 显示部署信息
show_deploy_info() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "无法获取公网IP")

    echo ""
    echo "=========================================="
    info "New API 部署完成！"
    echo "=========================================="
    echo ""

    if [ "$ENABLE_SSL" = true ]; then
        info "访问地址:"
        echo "  HTTPS: https://${SSL_DOMAIN}"
        echo "  API:   https://${SSL_DOMAIN}/v1/chat/completions"
        echo ""
        info "测试 API:"
        echo "  curl https://${SSL_DOMAIN}/v1/chat/completions \\"
        echo "    -H 'Authorization: Bearer sk-your-token' \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo "    -d '{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
    else
        info "访问地址:"
        echo "  本地: http://localhost:3000"
        echo "  内网: http://${LOCAL_IP}:3000"
        echo "  公网: http://${PUBLIC_IP}"
        echo "  公网直连: http://${PUBLIC_IP}:3000"
    fi

    echo ""
    info "默认管理员账号:"
    echo "  用户名: root"
    echo "  密码:   123456"
    warn "  请立即登录后修改默认密码！"
    echo ""
    info "常用命令:"
    echo "  查看日志: docker compose -f docker-compose.prod.yml logs -f new-api"
    echo "  重启服务: docker compose -f docker-compose.prod.yml restart"
    echo "  停止服务: docker compose -f docker-compose.prod.yml down"
    echo "  更新镜像: docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d"
    echo ""
    info "下一步操作:"
    echo "  1. 登录管理后台修改默认密码"
    echo "  2. 添加渠道（Channel）- 填入你的 API Key 池"
    echo "  3. 创建令牌（Token）- 生成统一对外 API Key"
    echo "  4. 使用统一 API Key 调用模型"
    echo ""
    info "配置 HTTPS（如尚未配置）:"
    echo "  ./setup-ssl.sh your-domain.com your-email@example.com"
    echo "=========================================="
}

# 主流程
main() {
    info "开始部署 New API LLM 网关..."
    check_docker
    show_security_group_tip
    configure_env
    start_services
    setup_ssl
    show_deploy_info
}

main "$@"
