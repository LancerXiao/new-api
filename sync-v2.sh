#!/bin/bash
# 自动从 GitHub 免费 API Key 仓库抓取 Key 并导入 New API
# 每30分钟由 crontab 执行

set -e

KEY_SOURCES=(
    "https://raw.githubusercontent.com/alistaitsacle/free-llm-api-keys/main/README.md"
)
BACKEND_BASE_URL="https://aiapiv2.pekpik.com"
PSQL_CMD="docker exec postgres psql -U newapi -d newapi -t -A"
LOG="/var/log/sync-free-keys.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(timestamp)] $1"; }

fetch_key_model_pairs() {
    local url=$1
    log "从 $url 抓取 Key-Model 对..."
    local content=$(curl -sL --connect-timeout 15 --max-time 30 "$url" 2>/dev/null)
    if [ -z "$content" ]; then
        log "无法获取内容: $url"
        return
    fi
    # 从 Markdown 表格提取 Key 和对应的 Model
    # 格式: | `sk-xxx` | model-name | ... |
    echo "$content" | grep -oP '\| `sk-[a-zA-Z0-9_-]+` \| [a-zA-Z0-9_/.:-]+ \|' | while read line; do
        local key=$(echo "$line" | grep -oP 'sk-[a-zA-Z0-9_-]+' | head -1)
        local model=$(echo "$line" | awk -F'|' '{print $3}' | sed 's/[` ]//g' | head -1)
        if [ -n "$key" ] && [ -n "$model" ]; then
            echo "${key}|${model}"
        fi
    done
}

cleanup_old_sync_channels() {
    log "清理旧的同步渠道..."
    $PSQL_CMD -c "DELETE FROM channels WHERE name LIKE 'free-key-sync-%';" 2>/dev/null
    $PSQL_CMD -c "DELETE FROM abilities WHERE channel_id NOT IN (SELECT id FROM channels);" 2>/dev/null
    log "清理完成"
}

add_channel_with_abilities() {
    local key=$1
    local model=$2
    local channel_id=$3
    local ts=$(date +%s)
    local channel_name="free-key-sync-${ts}-${channel_id}"

    $PSQL_CMD -c "INSERT INTO channels (id, name, type, key, base_url, models, \"group\", status, priority, weight, auto_ban, test_time, created_time)
        VALUES ($channel_id, '$channel_name', 1, '$key', '$BACKEND_BASE_URL', '$model', 'default', 1, 3, 3, 0, 0, $ts);" 2>/dev/null

    if [ $? -eq 0 ]; then
        $PSQL_CMD -c "INSERT INTO abilities (\"group\", model, channel_id, enabled, priority, weight)
            VALUES ('default', '$model', $channel_id, true, 3, 3);" 2>/dev/null
        log "  添加渠道 #${channel_id}: model=$model"
        return 0
    else
        log "  添加渠道失败: $channel_name"
        return 1
    fi
}

update_abilities_for_all_channels() {
    log "更新 abilities 表..."
    # 为所有启用的渠道（非 free-key-sync）插入 abilities 记录
    $PSQL_CMD -c "
        INSERT INTO abilities (\"group\", model, channel_id, enabled, priority, weight)
        SELECT 'default', unnest(string_to_array(models, ',')), id, true, 3, 3
        FROM channels
        WHERE status = 1
        AND id NOT IN (SELECT DISTINCT channel_id FROM abilities)
        ON CONFLICT DO NOTHING;" 2>/dev/null
}

main() {
    log "=========================================="
    log "开始同步免费 API Key"
    log "=========================================="

    all_pairs=""
    for source in "${KEY_SOURCES[@]}"; do
        pairs=$(fetch_key_model_pairs "$source")
        if [ -n "$pairs" ]; then
            all_pairs="${all_pairs}${pairs}"$'\n'
        fi
    done

    if [ -z "$all_pairs" ]; then
        log "未从任何源获取到 Key"
        exit 0
    fi

    unique_pairs=$(echo "$all_pairs" | sort -u -t'|' -k1,1 | grep -v '^$')
    total=$(echo "$unique_pairs" | wc -l)
    log "共 ${total} 个唯一 Key-Model 对"

    cleanup_old_sync_channels

    next_id=$($PSQL_CMD -c "SELECT COALESCE(MAX(id), 0) + 1 FROM channels;" 2>/dev/null)
    added=0

    while IFS='|' read -r key model; do
        [ -z "$key" ] && continue
        if add_channel_with_abilities "$key" "$model" "$next_id"; then
            added=$((added + 1))
        fi
        next_id=$((next_id + 1))
    done <<< "$unique_pairs"

    update_abilities_for_all_channels
    $PSQL_CMD -c "UPDATE channels SET auto_ban=0;" 2>/dev/null

    log "同步完成: 新增 ${added} 个渠道"
    log "=========================================="
}

main "$@"
