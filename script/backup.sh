#!/bin/sh

# 设置默认值
R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID:-""}
R2_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY:-""}
R2_ENDPOINT_URL=${R2_ENDPOINT_URL:-""}
R2_BUCKET_NAME=${R2_BUCKET_NAME:-""}

# 关键：定义运行时数据目录，Choreo 下必须是 /tmp
RUNTIME_DATA_DIR="/tmp"
# 数据库文件名需与 Dockerfile/entrypoint 一致
DB_FILE_NAME="komari.db"
# 1.2.6+ metric store（默认 SQLite）
METRICS_DB_FILE_NAME="metrics.db"

# 检查必要的环境变量
if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "Warning: R2 environment variables are not set, skipping backup/restore"
    exit 0
fi

# R2 配置
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
export AWS_ENDPOINT_URL="$R2_ENDPOINT_URL"
export BUCKET_NAME="$R2_BUCKET_NAME"

# 恢复功能
restore_backup() {
    echo "Checking for latest backup in R2..."
    LATEST_BACKUP=$(aws s3 ls "s3://${BUCKET_NAME}/backups/komari_backup_" | awk '{print $NF}' | sort | tail -n 1)
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "Found backup: ${LATEST_BACKUP}"
        
        if aws s3 cp "s3://${BUCKET_NAME}/backups/${LATEST_BACKUP}" "/tmp/${LATEST_BACKUP}"; then
            echo "Backup downloaded. Restoring to ${RUNTIME_DATA_DIR}..."
            
            RESTORE_TEMP="/tmp/restore_temp"
            mkdir -p "$RESTORE_TEMP"
            
            if tar -xzf "/tmp/${LATEST_BACKUP}" -C "$RESTORE_TEMP"; then
                # 适配 Choreo：仅操作 /tmp 下的内容
                # 假设压缩包内结构是 ./data/komari.db
                if [ -f "${RESTORE_TEMP}/data/${DB_FILE_NAME}" ]; then
                    cp -f "${RESTORE_TEMP}/data/${DB_FILE_NAME}" "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}"
                    echo "Restored ${DB_FILE_NAME}"
                fi

                # 1.2.6+ metric store
                if [ -f "${RESTORE_TEMP}/data/${METRICS_DB_FILE_NAME}" ]; then
                    cp -f "${RESTORE_TEMP}/data/${METRICS_DB_FILE_NAME}" "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}"
                    echo "Restored ${METRICS_DB_FILE_NAME}"
                fi

                # 如果有 theme 目录也恢复到 /tmp
                if [ -d "${RESTORE_TEMP}/data/theme" ]; then
                    cp -af "${RESTORE_TEMP}/data/theme" "${RUNTIME_DATA_DIR}/"
                fi

                rm -rf "$RESTORE_TEMP"
                rm "/tmp/${LATEST_BACKUP}"
                echo "Backup restored successfully to ${RUNTIME_DATA_DIR}"
            else
                echo "Error: Backup archive is corrupted!"
                rm -rf "$RESTORE_TEMP"
                exit 1
            fi
        fi
    else
        echo "No backup found in R2, starting fresh."
    fi
}

# 备份功能
create_backup() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="komari_backup_${TIMESTAMP}.tar.gz"
    BACKUP_DIR="/tmp/komari_backup_dir_${TIMESTAMP}"

    mkdir -p "${BACKUP_DIR}/data"

    # 1. 备份主库 SQLite (源文件在 /tmp/komari.db)
    echo "Backing up SQLite database from ${RUNTIME_DATA_DIR}..."
    if [ -f "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}" ]; then
        if ! sqlite3 "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}" "VACUUM INTO '${BACKUP_DIR}/data/${DB_FILE_NAME}'"; then
            echo "Error: SQLite vacuum failed for ${DB_FILE_NAME}!"
            rm -rf "$BACKUP_DIR"
            return 1
        fi
    else
        echo "Warning: No main database file found to backup."
    fi

    # 2. 备份 metric store (1.2.6+，默认 ./data/metrics.db → /tmp/metrics.db)
    if [ -f "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" ]; then
        echo "Backing up metrics database..."
        if ! sqlite3 "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" "VACUUM INTO '${BACKUP_DIR}/data/${METRICS_DB_FILE_NAME}'"; then
            # 指标库失败不阻断主库备份，但给出明确警告
            echo "Warning: SQLite vacuum failed for ${METRICS_DB_FILE_NAME}, falling back to copy."
            cp -f "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" "${BACKUP_DIR}/data/${METRICS_DB_FILE_NAME}" || true
        fi
    else
        echo "Info: No metrics database found (ok if still on pre-1.2.6 data or migration not finished)."
    fi

    # 3. 备份 theme 目录
    if [ -d "${RUNTIME_DATA_DIR}/theme" ]; then
        cp -a "${RUNTIME_DATA_DIR}/theme" "${BACKUP_DIR}/data/"
    fi

    # 4. 压缩并上传
    tar -czf "/tmp/${BACKUP_FILE}" -C "$BACKUP_DIR" .
    if aws s3 cp "/tmp/${BACKUP_FILE}" "s3://${BUCKET_NAME}/backups/${BACKUP_FILE}"; then
        echo "Upload successful: ${BACKUP_FILE}"
    else
        echo "Error: Upload failed!"
    fi

    # 清理
    rm -rf "$BACKUP_DIR" "/tmp/${BACKUP_FILE}"

    # 5. 清理旧备份 (保留7天)
    # 使用时间戳计算，兼容 BusyBox date (Alpine)
    OLD_DATE=$(date -d "@$(($(date +%s) - 7*86400))" +%Y%m%d)
    aws s3 ls "s3://${BUCKET_NAME}/backups/komari_backup_" | while read -r _ _ _ filename; do
        file_date=$(echo "$filename" | grep -oE "[0-9]{8}" | head -1)
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            aws s3 rm "s3://${BUCKET_NAME}/backups/$filename"
        fi
    done
}

case "$1" in
    "restore") restore_backup ;;
    "backup") create_backup ;;
    *) echo "Usage: $0 {backup|restore}"; exit 1 ;;
esac
