#!/bin/bash
# New API Key 失效告警脚本
# 定期检查渠道状态，发现失效 Key 时发送告警
#
# 使用方式:
#   chmod +x alert.sh
#   ./alert.sh  # 手动检查
#
# 定时执行（crontab -e）:
#   */10 * * * * /path/to/alert.sh >> /var/log/new-api-alert.log 2>&1

set -e

# ============ 配置区域 ============
NEW_API_BASE="${NEW_API_BASE:-http://localhost:3000}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

# 告警方式（可多选）
ENABLE_WEBHOOK="${ENABLE_WEBHOOK:-false}"    # Webhook 告警（企业微信/飞书/钉钉）
WEBHOOK_URL="${WEBHOOK_URL:-}"

ENABLE_EMAIL="${ENABLE_EMAIL:-false}"         # 邮件告警
ALERT_EMAIL="${ALERT_EMAIL:-}"

ENABLE_LOG="${ENABLE_LOG:-true}"              # 日志告警（默认开启）
LOG_FILE="${LOG_FILE:-./logs/alert.log}"
# ============ 配置结束 ============

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_alert() {
    [ "$ENABLE_LOG" = "true" ] && echo "[$(timestamp)] $1" >> "$LOG_FILE"
}

# 发送 Webhook 告警（支持企业微信/飞书/钉钉）
send_webhook() {
    local message="$1"
    [ -z "$WEBHOOK_URL" ] && return

    # 自动检测 Webhook 类型
    if [[ "$WEBHOOK_URL" == *"qyapi.weixin"* ]]; then
        # 企业微信
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$message\"}}" > /dev/null 2>&1
    elif [[ "$WEBHOOK_URL" == *"open.feishu"* ]] || [[ "$WEBHOOK_URL" == *"open.larksuite"* ]]; then
        # 飞书
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"$message\"}}" > /dev/null 2>&1
    elif [[ "$WEBHOOK_URL" == *"oapi.dingtalk"* ]]; then
        # 钉钉
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$message\"}}" > /dev/null 2>&1
    else
        # 通用 Webhook
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"$message\"}" > /dev/null 2>&1
    fi
}

# 检查渠道状态
check_channels() {
    if [ -z "$ADMIN_TOKEN" ]; then
        echo "[$(timestamp)] ERROR: ADMIN_TOKEN 未设置" >> "$LOG_FILE"
        exit 1
    fi

    local response=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${NEW_API_BASE}/api/channel/?p=0&page_size=200")

    local alert_count=0
    local alert_messages=""

    # 解析渠道状态
    local result=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if not data.get('success'):
        print('ERROR:' + data.get('message', '未知错误'))
        sys.exit(0)

    alerts = []
    for ch in data.get('data', []):
        status = ch.get('status', 0)
        name = ch.get('name', 'unknown')
        ch_id = ch.get('id', 0)
        test_time = ch.get('test_time', '未测试') or '未测试'
        response_time = ch.get('response_time', 0) or 0

        # 状态 3 = 自动禁用（key 失效）
        if status == 3:
            alerts.append(f'DISABLED|{ch_id}|{name}|key已失效，渠道已被自动禁用')
        # 状态 2 = 手动禁用
        elif status == 2:
            pass  # 手动禁用不告警
        # 响应时间过长
        elif response_time > 10000:
            alerts.append(f'SLOW|{ch_id}|{name}|响应时间过长: {response_time}ms')

    for a in alerts:
        print(a)
except Exception as e:
    print(f'ERROR:解析失败 {e}')
" 2>/dev/null)

    if [ -z "$result" ]; then
        log_alert "所有渠道运行正常"
        exit 0
    fi

    # 处理告警
    while IFS= read -r line; do
        if [[ "$line" == ERROR:* ]]; then
            log_alert "ERROR: ${line#ERROR:}"
            continue
        fi

        IFS='|' read -r type ch_id name detail <<< "$line"
        alert_count=$((alert_count + 1))

        local emoji=""
        case "$type" in
            DISABLED) emoji="🔴" ;;
            SLOW) emoji="🟡" ;;
            *) emoji="⚠️" ;;
        esac

        local msg="${emoji} [New API 告警] 渠道 #${ch_id} ${name}: ${detail}"
        alert_messages="${alert_messages}${msg}\n"

        echo -e "${RED}${msg}${NC}"
        log_alert "$msg"
    done <<< "$result"

    # 发送 Webhook 告警
    if [ $alert_count -gt 0 ] && [ "$ENABLE_WEBHOOK" = "true" ]; then
        send_webhook "New API 告警 (${alert_count}个渠道异常):\n${alert_messages}"
    fi

    return $alert_count
}

# 主流程
mkdir -p "$(dirname "$LOG_FILE")"
check_channels
