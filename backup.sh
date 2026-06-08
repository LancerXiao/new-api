#!/bin/bash
# New API 数据备份与恢复脚本
#
# 使用方式:
#   ./backup.sh                    # 创建备份
#   ./backup.sh restore <文件>     # 从备份恢复
#   ./backup.sh list               # 列出所有备份
#   ./backup.sh cleanup            # 清理旧备份（保留最近7天）
#
# 定时备份（crontab -e）:
#   0 2 * * * /path/to/backup.sh >> /var/log/new-api-backup.log 2>&1

set -e

# ============ 配置区域 ============
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
# PostgreSQL 连接信息（从 docker-compose.prod.yml 读取）
PG_CONTAINER="${PG_CONTAINER:-postgres}"
PG_USER="${PG_USER:-newapi}"
PG_DB="${PG_DB:-newapi}"
# ============ 配置结束 ============

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

timestamp() { date '+%Y%m%d_%H%M%S'; }

# 创建备份
create_backup() {
    local ts=$(timestamp)
    local backup_path="${BACKUP_DIR}/${ts}"
    mkdir -p "$backup_path"

    info "开始备份 [${ts}]..."

    # 1. 备份 PostgreSQL 数据库
    info "  备份 PostgreSQL 数据库..."
    docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" "$PG_DB" \
        > "${backup_path}/database.sql" 2>/dev/null
    gzip "${backup_path}/database.sql"
    info "  数据库备份完成: ${backup_path}/database.sql.gz"

    # 2. 备份 New API 数据目录（上传文件等）
    info "  备份数据目录..."
    if [ -d "./data" ]; then
        tar czf "${backup_path}/data.tar.gz" -C . data/ 2>/dev/null || true
        info "  数据目录备份完成: ${backup_path}/data.tar.gz"
    fi

    # 3. 备份配置文件
    info "  备份配置文件..."
    mkdir -p "${backup_path}/config"
    [ -f docker-compose.prod.yml ] && cp docker-compose.prod.yml "${backup_path}/config/"
    [ -f .env.production ] && cp .env.production "${backup_path}/config/"
    [ -f nginx/conf.d/default.conf ] && cp nginx/conf.d/default.conf "${backup_path}/config/"
    info "  配置文件备份完成"

    # 4. 创建备份元信息
    cat > "${backup_path}/backup.info" <<EOF
timestamp=${ts}
pg_container=${PG_CONTAINER}
pg_user=${PG_USER}
pg_db=${PG_DB}
db_size=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "SELECT pg_size_pretty(pg_database_size('$PG_DB'));" -t 2>/dev/null | xargs || "unknown")
data_size=$(du -sh ./data 2>/dev/null | cut -f1 || "unknown")
created_at=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 5. 打包整个备份
    local archive="${BACKUP_DIR}/new-api-backup-${ts}.tar.gz"
    tar czf "$archive" -C "$BACKUP_DIR" "$ts"
    rm -rf "$backup_path"

    local size=$(du -sh "$archive" | cut -f1)
    info "备份完成: ${archive} (${size})"

    # 6. 清理旧备份
    cleanup_old_backups
}

# 从备份恢复
restore_backup() {
    local archive="${1:?请指定备份文件}"
    [ ! -f "$archive" ] && error "备份文件不存在: $archive"

    warn "恢复操作将覆盖当前数据！"
    read -p "确认恢复？(输入 YES 继续): " confirm
    [ "$confirm" = "YES" ] || { info "已取消"; exit 0; }

    info "开始从 ${archive} 恢复..."

    # 解压备份
    local temp_dir="${BACKUP_DIR}/restore_temp"
    mkdir -p "$temp_dir"
    tar xzf "$archive" -C "$temp_dir"

    # 找到备份子目录
    local backup_subdir=$(ls "$temp_dir" | head -1)
    local backup_path="${temp_dir}/${backup_subdir}"

    # 1. 恢复数据库
    if [ -f "${backup_path}/database.sql.gz" ]; then
        info "  恢复 PostgreSQL 数据库..."
        gunzip "${backup_path}/database.sql.gz"

        # 停止 New API 避免写入冲突
        docker compose -f docker-compose.prod.yml stop new-api 2>/dev/null || true

        # 恢复数据库
        docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" \
            < "${backup_path}/database.sql" 2>/dev/null || warn "数据库恢复可能有部分错误"

        info "  数据库恢复完成"
    fi

    # 2. 恢复数据目录
    if [ -f "${backup_path}/data.tar.gz" ]; then
        info "  恢复数据目录..."
        tar xzf "${backup_path}/data.tar.gz" -C . 2>/dev/null || true
        info "  数据目录恢复完成"
    fi

    # 3. 恢复配置
    if [ -d "${backup_path}/config" ]; then
        info "  恢复配置文件..."
        cp -r "${backup_path}/config/"* . 2>/dev/null || true
    fi

    # 清理临时文件
    rm -rf "$temp_dir"

    # 重启服务
    info "  重启服务..."
    docker compose -f docker-compose.prod.yml start new-api 2>/dev/null || \
        docker compose -f docker-compose.prod.yml up -d

    info "恢复完成！"
}

# 列出备份
list_backups() {
    info "现有备份:"
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        echo "  无备份"
        return
    fi

    for f in ${BACKUP_DIR}/new-api-backup-*.tar.gz; do
        [ -f "$f" ] || continue
        local size=$(du -sh "$f" | cut -f1)
        local name=$(basename "$f")
        echo "  ${name} (${size})"
    done
}

# 清理旧备份
cleanup_old_backups() {
    local count=$(find "$BACKUP_DIR" -name "new-api-backup-*.tar.gz" -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        info "清理 ${RETENTION_DAYS} 天前的旧备份..."
        find "$BACKUP_DIR" -name "new-api-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null
        info "已清理 ${count} 个旧备份"
    fi
}

# 主入口
mkdir -p "$BACKUP_DIR"

case "${1:-backup}" in
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    cleanup)
        cleanup_old_backups
        ;;
    *)
        echo "用法: $0 {backup|restore <文件>|list|cleanup}"
        exit 1
        ;;
esac
