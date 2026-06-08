#!/bin/bash
# New API 一键部署脚本 - 阿里云 ECS
# 使用方式: chmod +x deploy.sh && ./deploy.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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

    # 同步替换 nginx 健康检查中的密码（Redis healthcheck）
    info "数据库密码: ${DB_PASSWORD}"
    info "Redis 密码: ${REDIS_PASSWORD}"
    info "Session 密钥: ${SESSION_SECRET}"
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

# 显示部署信息
show_deploy_info() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "无法获取公网IP")

    echo ""
    echo "=========================================="
    info "New API 部署完成！"
    echo "=========================================="
    echo ""
    info "访问地址:"
    echo "  本地: http://localhost:3000"
    echo "  内网: http://${LOCAL_IP}:3000"
    echo "  公网: http://${PUBLIC_IP}:3000"
    echo "  Nginx代理: http://${PUBLIC_IP}"
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
    echo "=========================================="
}

# 主流程
main() {
    info "开始部署 New API LLM 网关..."
    check_docker
    show_security_group_tip
    configure_env
    start_services
    show_deploy_info
}

main "$@"
