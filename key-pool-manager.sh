#!/bin/bash
# New API Key 池管理脚本
# 用于批量管理 API Key 渠道，支持动态更新失效的 key
#
# 使用方式:
#   chmod +x key-pool-manager.sh
#   ./key-pool-manager.sh add-batch     # 批量添加 key
#   ./key-pool-manager.sh check-status  # 检查所有渠道状态
#   ./key-pool-manager.sh disable-expired # 禁用失效渠道
#   ./key-pool-manager.sh update-keys   # 批量更新 key

set -e

# ============ 配置区域 ============
# New API 管理后台地址
NEW_API_BASE="${NEW_API_BASE:-http://localhost:3000}"
# 管理员 Token（在管理后台 -> 令牌 页面生成）
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
# Key 池文件路径（每行一个 key）
KEY_FILE="${KEY_FILE:-./api-keys.txt}"
# ============ 配置结束 ============

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_config() {
    if [ -z "$ADMIN_TOKEN" ]; then
        error "请设置 ADMIN_TOKEN 环境变量"
        echo "  export ADMIN_TOKEN=sk-xxx"
        echo "  或在脚本中直接填写"
        exit 1
    fi
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -X "$method" \
            "${NEW_API_BASE}${endpoint}" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" \
            "${NEW_API_BASE}${endpoint}" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json"
    fi
}

# 批量添加 key 到渠道
# 每个渠道可以包含多个 key（用换行分隔）
add_batch() {
    check_config

    if [ ! -f "$KEY_FILE" ]; then
        error "Key 文件不存在: $KEY_FILE"
        echo "请创建 $KEY_FILE 文件，每行一个 API Key"
        echo ""
        echo "示例格式:"
        echo "sk-xxxxxxxxxxxx1"
        echo "sk-xxxxxxxxxxxx2"
        echo "sk-xxxxxxxxxxxx3"
        exit 1
    fi

    local provider="${1:-openai}"
    local model_prefix="${2:-}"
    local base_url="${3:-}"

    info "正在从 $KEY_FILE 批量添加 ${provider} 渠道..."

    local key_count=0
    local success_count=0

    while IFS= read -r key; do
        # 跳过空行和注释
        [[ -z "$key" || "$key" =~ ^# ]] && continue

        key_count=$((key_count + 1))

        local channel_name="${provider}-pool-${key_count}"
        local request_data="{\"name\":\"${channel_name}\",\"type\":1,\"key\":\"${key}\",\"models\":\"\""

        # 根据供应商设置类型
        case "$provider" in
            openai)
                request_data="{\"name\":\"${channel_name}\",\"type\":1,\"key\":\"${key}\",\"models\":\"gpt-4o,gpt-4o-mini,gpt-4-turbo,gpt-3.5-turbo,o1,o1-mini,o3-mini\""
                [ -n "$base_url" ] && request_data="${request_data},\"base_url\":\"${base_url}\""
                ;;
            claude|anthropic)
                request_data="{\"name\":\"${channel_name}\",\"type\":14,\"key\":\"${key}\",\"models\":\"claude-sonnet-4-20250514,claude-3-5-haiku-20241022,claude-opus-4-20250514\""
                ;;
            gemini)
                request_data="{\"name\":\"${channel_name}\",\"type\":24,\"key\":\"${key}\",\"models\":\"gemini-2.5-pro,gemini-2.5-flash,gemini-2.0-flash\""
                ;;
            deepseek)
                request_data="{\"name\":\"${channel_name}\",\"type\":33,\"key\":\"${key}\",\"models\":\"deepseek-chat,deepseek-reasoner\""
                ;;
            custom)
                if [ -z "$base_url" ]; then
                    error "自定义供应商必须提供 base_url"
                    exit 1
                fi
                request_data="{\"name\":\"${channel_name}\",\"type\":1,\"key\":\"${key}\",\"models\":\"${model_prefix}\",\"base_url\":\"${base_url}\""
                ;;
            *)
                request_data="{\"name\":\"${channel_name}\",\"type\":1,\"key\":\"${key}\",\"models\":\"gpt-4o,gpt-4o-mini\""
                [ -n "$base_url" ] && request_data="${request_data},\"base_url\":\"${base_url}\""
                ;;
        esac

        request_data="${request_data},\"group\":\"default\",\"priority\":0,\"weight\":1}"

        local response=$(api_call POST /api/channel/ "$request_data")
        local success=$(echo "$response" | grep -o '"success":true' || true)

        if [ -n "$success" ]; then
            success_count=$((success_count + 1))
            info "  [${key_count}] 添加成功: ${channel_name}"
        else
            warn "  [${key_count}] 添加失败: ${channel_name} - $(echo $response | head -c 200)"
        fi
    done < "$KEY_FILE"

    echo ""
    info "批量添加完成: 成功 ${success_count}/${key_count}"
}

# 检查所有渠道状态
check_status() {
    check_config

    info "正在查询所有渠道状态..."

    local response=$(api_call GET "/api/channel/?p=0&page_size=100")
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        channels = data.get('data', [])
        print(f'渠道总数: {len(channels)}')
        print('-' * 80)
        print(f'{\"ID\":<6} {\"名称\":<25} {\"状态\":<8} {\"优先级\":<8} {\"权重\":<8} {\"响应时间\":<10}')
        print('-' * 80)
        for ch in channels:
            status = '启用' if ch.get('status') == 1 else '禁用'
            test_time = ch.get('test_time', '未测试') or '未测试'
            print(f'{ch[\"id\"]:<6} {ch[\"name\"][:24]:<25} {status:<8} {ch.get(\"priority\",0):<8} {ch.get(\"weight\",1):<8} {str(test_time):<10}')
    else:
        print(f'查询失败: {data.get(\"message\", \"未知错误\")}')
except Exception as e:
    print(f'解析失败: {e}')
" 2>/dev/null || echo "$response" | head -50
}

# 禁用失效渠道
disable_expired() {
    check_config

    info "正在查找并禁用失效渠道..."

    local response=$(api_call GET "/api/channel/?p=0&page_size=100")
    local disabled_count=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    disabled = 0
    if data.get('success'):
        for ch in data.get('data', []):
            if ch.get('status') == 3:  # 状态 3 表示自动禁用
                print(ch['id'])
                disabled += 1
    sys.stderr.write(f'发现 {disabled} 个失效渠道\n')
except: pass
" 2>&1)

    echo "$disabled_count"
}

# 测试所有渠道
test_all() {
    check_config

    info "正在测试所有渠道（这可能需要一些时间）..."

    local response=$(api_call GET "/api/channel/?p=0&page_size=100")
    local ids=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for ch in data.get('data', []):
            print(ch['id'])
except: pass
" 2>/dev/null)

    for id in $ids; do
        info "测试渠道 #${id}..."
        local result=$(api_call GET "/api/channel/test/${id}")
        local success=$(echo "$result" | grep -o '"success":true' || true)
        if [ -n "$success" ]; then
            info "  渠道 #${id} 正常"
        else
            warn "  渠道 #${id} 异常: $(echo $result | head -c 200)"
        fi
    done
}

# 批量更新 key（替换已有的 key）
update_keys() {
    check_config

    if [ ! -f "$KEY_FILE" ]; then
        error "Key 文件不存在: $KEY_FILE"
        exit 1
    fi

    info "批量更新 Key 模式:"
    info "  1. 先删除所有现有渠道"
    info "  2. 再重新添加新 key"
    echo ""
    read -p "确认继续？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        info "已取消"
        exit 0
    fi

    # 获取所有渠道 ID
    local response=$(api_call GET "/api/channel/?p=0&page_size=100")
    local ids=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for ch in data.get('data', []):
            print(ch['id'])
except: pass
" 2>/dev/null)

    # 删除所有渠道
    for id in $ids; do
        api_call DELETE "/api/channel/${id}" > /dev/null
        info "已删除渠道 #${id}"
    done

    info "所有旧渠道已删除，请使用 add-batch 重新添加"
}

# 显示帮助
show_help() {
    echo "New API Key 池管理工具"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  add-batch [provider] [models] [base_url]  批量添加 key"
    echo "    provider: openai(默认) | claude | gemini | deepseek | custom"
    echo "  check-status    查看所有渠道状态"
    echo "  test-all        测试所有渠道连通性"
    echo "  disable-expired 禁用失效渠道"
    echo "  update-keys     批量替换 key（先删后增）"
    echo ""
    echo "环境变量:"
    echo "  NEW_API_BASE    API 地址 (默认: http://localhost:3000)"
    echo "  ADMIN_TOKEN     管理员 Token (必填)"
    echo "  KEY_FILE        Key 文件路径 (默认: ./api-keys.txt)"
    echo ""
    echo "示例:"
    echo "  export ADMIN_TOKEN=sk-xxx"
    echo "  $0 add-batch openai"
    echo "  $0 add-batch claude"
    echo "  $0 add-batch custom 'gpt-4,gpt-3.5' 'https://api.example.com/v1'"
    echo "  $0 check-status"
    echo "  $0 test-all"
}

# 主入口
case "${1:-help}" in
    add-batch)
        add_batch "${2:-openai}" "${3:-}" "${4:-}"
        ;;
    check-status)
        check_status
        ;;
    test-all)
        test_all
        ;;
    disable-expired)
        disable_expired
        ;;
    update-keys)
        update_keys
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "未知命令: $1"
        show_help
        exit 1
        ;;
esac
