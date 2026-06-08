#!/bin/bash
# 阿里云 ECS 安全加固脚本
# 配置 iptables 防火墙规则
#
# 使用方式: chmod +x firewall-setup.sh && ./firewall-setup.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 你的可信 IP（管理后台只允许这些 IP 访问）
# 请替换为你自己的 IP
TRUSTED_IPS="${TRUSTED_IPS:-}"

if [ -z "$TRUSTED_IPS" ]; then
    warn "未设置 TRUSTED_IPS 环境变量"
    warn "管理后台将允许所有 IP 访问（不安全）"
    warn "建议: export TRUSTED_IPS=\"1.2.3.4,5.6.7.8\""
    echo ""
    read -p "是否继续？(y/N): " confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || exit 0
fi

info "正在配置防火墙规则..."

# 安装 iptables-persistent（自动保存规则）
export DEBIAN_FRONTEND=noninteractive
apt-get install -y iptables-persistent 2>/dev/null || true

# 清除现有规则（谨慎操作）
info "设置默认策略..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许回环接口
iptables -A INPUT -i lo -j ACCEPT

# 允许已建立的连接
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许 ICMP (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# ============================================
# SSH 访问（端口 22）
# ============================================
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
info "SSH (22): 允许所有 IP"

# ============================================
# HTTP/HTTPS（Nginx 代理端口）
# ============================================
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
info "HTTP (80) + HTTPS (443): 允许所有 IP"

# ============================================
# New API 管理后台（端口 3000）- 仅限可信 IP
# ============================================
if [ -n "$TRUSTED_IPS" ]; then
    IFS=',' read -ra IPS <<< "$TRUSTED_IPS"
    for ip in "${IPS[@]}"; do
        ip=$(echo "$ip" | xargs)  # trim
        iptables -A INPUT -p tcp --dport 3000 -s "$ip" -j ACCEPT
        info "管理后台 (3000): 允许 $ip"
    done
    # 拒绝其他 IP 访问 3000
    iptables -A INPUT -p tcp --dport 3000 -j DROP
    info "管理后台 (3000): 拒绝其他所有 IP"
else
    iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
    warn "管理后台 (3000): 允许所有 IP（不安全！）"
fi

# ============================================
# PostgreSQL 和 Redis - 仅 Docker 内网访问
# ============================================
iptables -A INPUT -p tcp --dport 5432 -s 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -p tcp --dport 5432 -j DROP
iptables -A INPUT -p tcp --dport 6379 -s 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -p tcp --dport 6379 -j DROP
info "PostgreSQL (5432) + Redis (6379): 仅 Docker 内网"

# 保存规则
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
info "防火墙规则已保存"

# 显示当前规则
echo ""
info "当前防火墙规则:"
iptables -L INPUT -n --line-numbers

echo ""
info "安全加固完成！"
echo ""
info "常用命令:"
echo "  查看规则: iptables -L INPUT -n --line-numbers"
echo "  临时开放端口: iptables -I INPUT 5 -p tcp --dport 8080 -j ACCEPT"
echo "  删除规则: iptables -D INPUT <行号>"
echo "  清除所有规则: iptables -F INPUT && iptables -P INPUT ACCEPT"
