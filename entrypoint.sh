#!/bin/sh

# ==============================
# 环境变量配置与默认值
# ==============================
KOMARI_SECRET=${KOMARI_SECRET:-""}
KOMARI_AGENT_UUID=${KOMARI_AGENT_UUID:-""}
KOMARI_AGENT_NAME=${KOMARI_AGENT_NAME:-"Local Agent"}

# 数据库文件路径（必须在 /tmp）
DB_FILE="/tmp/komari.db"

# 如果未提供 UUID，自动生成一个
if [ -z "$KOMARI_AGENT_UUID" ]; then
    KOMARI_AGENT_UUID=$(date +%s%N | md5sum | head -c 36)
    echo "Info: KOMARI_AGENT_UUID not set, generated random UUID: ${KOMARI_AGENT_UUID}"
fi

# ==============================
# 1. 初始化 /tmp 目录结构
# ==============================
echo "Initializing directory structure in /tmp..."
mkdir -p /tmp/theme

# ==============================
# 2. 模拟定时备份任务 (替代 crond)
# ==============================
# 由于无法使用 crond，我们用一个后台循环来执行备份
start_backup_loop() {
    while true; do
        sleep 7200
        echo "Starting scheduled backup..."
        /app/backup.sh backup >> /tmp/backup.log 2>&1
    done
}
start_backup_loop &

# ==============================
# 3. 尝试恢复备份
# ==============================
echo "Restoring backup if available..."
# 注意：你的 backup.sh 内部也需要确保恢复的目标是 /tmp/komari.db
/app/backup.sh restore

# ==============================
# 4. 启动 komari-agent
# ==============================
if [ -n "$KOMARI_SECRET" ]; then
    echo "Starting komari-agent setup process..."
    (
        # --- 步骤 4.1: 等待 Server 端口就绪 ---
        count=0
        while ! nc -z localhost 25774 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count+1))
        done

        if ! nc -z localhost 25774 2>/dev/null; then
             echo "Error: Komari Server failed to start within 30s. Agent skipped."
             exit 1
        fi
        
        echo "Komari Server is ready. Checking database..."

        # --- 步骤 4.2: 检查并注入 clients 数据 ---
        if [ -f "$DB_FILE" ]; then
            # 确保使用 /tmp/komari.db
            ROW_COUNT=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM clients;" 2>/dev/null || echo "0")
            ROW_COUNT=$(echo "$ROW_COUNT" | tr -d '[:space:]')

            if [ "$ROW_COUNT" = "0" ]; then
                echo "Database check: 'clients' table is empty. Injecting initial agent..."
                SQL_CMD="INSERT INTO clients (uuid, token, name, created_at) VALUES ('${KOMARI_AGENT_UUID}', '${KOMARI_SECRET}', '${KOMARI_AGENT_NAME}', datetime('now', 'localtime'));"
                
                if sqlite3 "$DB_FILE" "$SQL_CMD"; then
                    echo "Successfully injected agent: ${KOMARI_AGENT_NAME} (UUID: ${KOMARI_AGENT_UUID})"
                else
                    echo "Error: Failed to inject agent into database."
                fi
            else
                echo "Database check: 'clients' table already has data ($ROW_COUNT rows). Skipping injection."
            fi
        else
            echo "Warning: Database file not found at $DB_FILE, skipping injection."
        fi

        # --- 步骤 4.3: 启动 Agent ---
        echo "Starting komari-agent..."
        /app/komari-agent -e http://localhost:25774 -t "${KOMARI_SECRET}" --disable-auto-update
    ) &
else
    echo "Warning: KOMARI_SECRET is not set, skipping komari-agent"
fi

# ==============================
# 4. 启动主应用
# ==============================
echo "Starting app..."
# 确保主应用也读取 /tmp/komari.db (通过 Dockerfile 中的 ENV 已经指定)
exec /app/komari server
