#!/bin/sh

# Komari backup/restore for Choreo (/tmp 可写)
# 后端: BACKUP_BACKEND=r2 | webdav | none
# 对齐上游 web/api/admin/backup_whitelist.go：
#   komari.db（单独 VACUUM）+ metrics.db + theme/ + favicon.ico + font.ttf
# 额外：plugin/ + plugin-data/（1.3+ 插件系统，上游 bootstrap 已建目录）

BACKUP_BACKEND=$(printf '%s' "${BACKUP_BACKEND:-r2}" | tr '[:upper:]' '[:lower:]')

R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID:-""}
R2_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY:-""}
R2_ENDPOINT_URL=${R2_ENDPOINT_URL:-""}
R2_BUCKET_NAME=${R2_BUCKET_NAME:-""}

WEBDAV_URL=${WEBDAV_URL:-""}
WEBDAV_USERNAME=${WEBDAV_USERNAME:-${WEBDAV_USER:-""}}
WEBDAV_PASSWORD=${WEBDAV_PASSWORD:-${WEBDAV_PASS:-""}}

# 运行时数据目录（Choreo 只读根文件系统，可写在 /tmp）
# /app/data -> /tmp，故 ./data/theme 实际为 /tmp/theme
RUNTIME_DATA_DIR="/tmp"
DB_FILE_NAME="komari.db"
METRICS_DB_FILE_NAME="metrics.db"
BACKUP_PREFIX="komari_backup_"
# R2 仍放在 bucket/backups/ 下；WebDAV 使用 WEBDAV_URL 指向的目录本身
R2_BACKUP_PREFIX="backups/"

# 目录型数据：整目录备份/还原。还原时必须先删目标再 cp，
# 否则若 entrypoint 已 mkdir 出空目录，`cp -a src dst/` 会嵌套成 dst/src。
DATA_DIRS="theme plugin plugin-data"

# 文件型数据（与上游 backupWhitelist 对齐）
DATA_FILES="favicon.ico font.ttf"

check_backend() {
    case "$BACKUP_BACKEND" in
        r2)
            if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
                echo "Warning: R2 environment variables are not set, skipping backup/restore"
                exit 0
            fi
            export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
            export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
            export AWS_DEFAULT_REGION="auto"
            export AWS_ENDPOINT_URL="$R2_ENDPOINT_URL"
            export BUCKET_NAME="$R2_BUCKET_NAME"
            ;;
        webdav)
            if [ -z "$WEBDAV_URL" ] || [ -z "$WEBDAV_USERNAME" ] || [ -z "$WEBDAV_PASSWORD" ]; then
                echo "Warning: WebDAV environment variables are not set, skipping backup/restore"
                exit 0
            fi
            WEBDAV_URL=${WEBDAV_URL%/}
            ;;
        none|off|disabled)
            echo "Backup backend disabled, skipping backup/restore"
            exit 0
            ;;
        *)
            echo "Error: unsupported BACKUP_BACKEND: $BACKUP_BACKEND. Use r2, webdav, or none."
            exit 1
            ;;
    esac
}

list_backups() {
    case "$BACKUP_BACKEND" in
        r2)
            aws s3 ls "s3://${BUCKET_NAME}/${R2_BACKUP_PREFIX}${BACKUP_PREFIX}" | awk '{print $NF}'
            ;;
        webdav)
            curl -fsS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                -X PROPFIND \
                -H "Depth: 1" \
                "$WEBDAV_URL/" \
                | tr '<' '\n' \
                | sed -n "s|.*href>\([^<]*${BACKUP_PREFIX}[^<]*\.tar\.gz\).*|\1|p" \
                | while read -r href; do
                    basename "$href" | sed 's/%5F/_/g; s/%2E/./g; s/%2D/-/g'
                done
            ;;
    esac
}

download_backup() {
    backup_file="$1"
    case "$BACKUP_BACKEND" in
        r2)
            aws s3 cp "s3://${BUCKET_NAME}/${R2_BACKUP_PREFIX}${backup_file}" "/tmp/${backup_file}"
            ;;
        webdav)
            curl -fsS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                -o "/tmp/${backup_file}" \
                "$WEBDAV_URL/${backup_file}"
            ;;
    esac
}

upload_backup() {
    local_file="$1"
    backup_file="$2"
    case "$BACKUP_BACKEND" in
        r2)
            aws s3 cp "$local_file" "s3://${BUCKET_NAME}/${R2_BACKUP_PREFIX}${backup_file}"
            ;;
        webdav)
            # 目录已存在时 MKCOL 可能非 2xx，忽略
            curl -fsS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                -X MKCOL \
                "$WEBDAV_URL/" >/dev/null 2>&1 || true
            curl -fsS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                -T "$local_file" \
                "$WEBDAV_URL/${backup_file}"
            ;;
    esac
}

delete_backup() {
    backup_file="$1"
    case "$BACKUP_BACKEND" in
        r2)
            aws s3 rm "s3://${BUCKET_NAME}/${R2_BACKUP_PREFIX}${backup_file}"
            ;;
        webdav)
            curl -fsS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                -X DELETE \
                "$WEBDAV_URL/${backup_file}"
            ;;
    esac
}

# 将备份包里的目录还原到 RUNTIME_DATA_DIR/<name>
# 兼容两种历史形态：
#   1) 正常：data/theme/<short>/...
#   2) 旧 bug 二次备份：data/theme/theme/<short>/...（仅一层同名嵌套）
#
# 必须先 rm -rf 目标再 cp -a：若目标目录已存在，BusyBox `cp -a src dst/`
# 会嵌套成 dst/src/（旧 entrypoint 先 mkdir 空 theme 时必现）。
restore_data_dir() {
    name="$1"
    src="${RESTORE_TEMP}/data/${name}"
    dst="${RUNTIME_DATA_DIR}/${name}"

    if [ ! -d "$src" ]; then
        return 0
    fi

    # 旧 bug：备份里只有 name/name/ 且同层无其他条目时，展开一层
    if [ -d "${src}/${name}" ]; then
        entry_count=$(find "$src" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        if [ "$entry_count" = "1" ]; then
            echo "Info: detected nested ${name}/${name}/ from older restore bug, flattening"
            src="${src}/${name}"
        fi
    fi

    rm -rf "$dst"
    cp -a "$src" "$dst"
    echo "Restored ${name}/"
}

restore_data_file() {
    name="$1"
    src="${RESTORE_TEMP}/data/${name}"
    dst="${RUNTIME_DATA_DIR}/${name}"
    if [ -f "$src" ]; then
        cp -f "$src" "$dst"
        echo "Restored ${name}"
    fi
}

restore_backup() {
    check_backend

    echo "Checking for latest backup via ${BACKUP_BACKEND}..."
    LATEST_BACKUP=$(list_backups | sort | tail -n 1)

    if [ -n "$LATEST_BACKUP" ]; then
        echo "Found backup: ${LATEST_BACKUP}"

        if download_backup "$LATEST_BACKUP"; then
            echo "Backup downloaded. Restoring to ${RUNTIME_DATA_DIR}..."

            RESTORE_TEMP="/tmp/restore_temp"
            rm -rf "$RESTORE_TEMP"
            mkdir -p "$RESTORE_TEMP"

            if tar -xzf "/tmp/${LATEST_BACKUP}" -C "$RESTORE_TEMP"; then
                if [ -f "${RESTORE_TEMP}/data/${DB_FILE_NAME}" ]; then
                    cp -f "${RESTORE_TEMP}/data/${DB_FILE_NAME}" "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}"
                    echo "Restored ${DB_FILE_NAME}"
                fi

                if [ -f "${RESTORE_TEMP}/data/${METRICS_DB_FILE_NAME}" ]; then
                    cp -f "${RESTORE_TEMP}/data/${METRICS_DB_FILE_NAME}" "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}"
                    echo "Restored ${METRICS_DB_FILE_NAME}"
                fi

                for d in $DATA_DIRS; do
                    restore_data_dir "$d"
                done

                for f in $DATA_FILES; do
                    restore_data_file "$f"
                done

                rm -rf "$RESTORE_TEMP"
                rm -f "/tmp/${LATEST_BACKUP}"
                echo "Backup restored successfully to ${RUNTIME_DATA_DIR}"
            else
                echo "Error: Backup archive is corrupted!"
                rm -rf "$RESTORE_TEMP"
                exit 1
            fi
        else
            echo "Error: Failed to download backup ${LATEST_BACKUP}"
            exit 1
        fi
    else
        echo "No backup found via ${BACKUP_BACKEND}, starting fresh."
    fi
}

# 目录是否包含至少一个条目（不依赖 find -quit，兼容精简 BusyBox）
dir_has_entries() {
    dir="$1"
    [ -d "$dir" ] || return 1
    # 含隐藏文件；无匹配时壳层会留下字面量，需用 -e/-L 判断
    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        if [ -e "$entry" ] || [ -L "$entry" ]; then
            return 0
        fi
    done
    return 1
}

backup_data_dir() {
    name="$1"
    src="${RUNTIME_DATA_DIR}/${name}"
    if [ -d "$src" ]; then
        if dir_has_entries "$src"; then
            cp -a "$src" "${BACKUP_DIR}/data/"
            echo "Directory backed up: ${name}/"
        else
            echo "Info: ${name}/ is empty, skip"
        fi
    fi
}

backup_data_file() {
    name="$1"
    src="${RUNTIME_DATA_DIR}/${name}"
    if [ -f "$src" ]; then
        cp -f "$src" "${BACKUP_DIR}/data/"
        echo "File backed up: ${name}"
    fi
}

create_backup() {
    check_backend

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_PREFIX}${TIMESTAMP}.tar.gz"
    BACKUP_DIR="/tmp/komari_backup_dir_${TIMESTAMP}"

    mkdir -p "${BACKUP_DIR}/data"

    # 1. 主库（含 configs.theme、theme_configurations、theme_market_sources 等）
    echo "Backing up SQLite database from ${RUNTIME_DATA_DIR}..."
    if [ -f "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}" ]; then
        if ! sqlite3 "${RUNTIME_DATA_DIR}/${DB_FILE_NAME}" "VACUUM INTO '${BACKUP_DIR}/data/${DB_FILE_NAME}'"; then
            echo "Error: SQLite vacuum failed for ${DB_FILE_NAME}!"
            rm -rf "$BACKUP_DIR"
            return 1
        fi
        echo "Database backed up: ${DB_FILE_NAME}"
    else
        echo "Warning: No main database file found to backup."
    fi

    # 2. metrics.db (1.2.6+)
    if [ -f "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" ]; then
        echo "Backing up metrics database..."
        if ! sqlite3 "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" "VACUUM INTO '${BACKUP_DIR}/data/${METRICS_DB_FILE_NAME}'"; then
            echo "Warning: SQLite vacuum failed for ${METRICS_DB_FILE_NAME}, falling back to copy."
            cp -f "${RUNTIME_DATA_DIR}/${METRICS_DB_FILE_NAME}" "${BACKUP_DIR}/data/${METRICS_DB_FILE_NAME}" || true
        else
            echo "Metrics database backed up: ${METRICS_DB_FILE_NAME}"
        fi
    else
        echo "Info: No metrics database found (ok if pre-1.2.6 or migration not finished)."
    fi

    # 3. 目录：theme / plugin / plugin-data
    for d in $DATA_DIRS; do
        backup_data_dir "$d"
    done

    # 4. 文件：favicon.ico / font.ttf（上游 backupWhitelist）
    for f in $DATA_FILES; do
        backup_data_file "$f"
    done

    # 5. 压缩并上传
    echo "Compressing backup..."
    tar -czf "/tmp/${BACKUP_FILE}" -C "$BACKUP_DIR" .

    echo "Uploading to ${BACKUP_BACKEND}..."
    if upload_backup "/tmp/${BACKUP_FILE}" "$BACKUP_FILE"; then
        echo "Upload successful: ${BACKUP_FILE}"
    else
        echo "Error: Upload failed!"
        rm -rf "$BACKUP_DIR" "/tmp/${BACKUP_FILE}"
        return 1
    fi

    rm -rf "$BACKUP_DIR" "/tmp/${BACKUP_FILE}"

    # 6. 清理 7 天前备份（兼容 BusyBox / GNU date）
    echo "Cleaning up old backups..."
    OLD_DATE=$(date -d "@$(($(date +%s) - 7*86400))" +%Y%m%d 2>/dev/null || date -v-7d +%Y%m%d)
    list_backups | while read -r filename; do
        [ -z "$filename" ] && continue
        file_date=$(printf '%s' "$filename" | sed -n 's/.*\([0-9]\{8\}\).*/\1/p')
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            echo "Deleting old backup: $filename"
            delete_backup "$filename" || true
        fi
    done

    echo "Backup completed successfully"
}

case "$1" in
    "restore") restore_backup ;;
    "backup") create_backup ;;
    *) echo "Usage: $0 {backup|restore}"; exit 1 ;;
esac
