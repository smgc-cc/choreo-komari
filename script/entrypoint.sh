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
# 注意: `md5sum` 读 stdin 时输出是 "hash  -"，| head -c 36 会吃进尾部 "  -"，
# 得到非法 UUID（如 "abc...def  -"），导致终端路径含空格、鉴权/路由异常。
if [ -z "$KOMARI_AGENT_UUID" ]; then
    if command -v uuidgen >/dev/null 2>&1; then
        KOMARI_AGENT_UUID=$(uuidgen | tr 'A-F' 'a-f')
    else
        # 32 位 hex（md5 一行的第一列），不要用 head -c 截断整行
        KOMARI_AGENT_UUID=$(printf '%s' "$(date +%s%N)-$$-$RANDOM" | md5sum | awk '{print $1}')
    fi
    echo "Info: KOMARI_AGENT_UUID not set, generated random UUID: ${KOMARI_AGENT_UUID}"
fi

# ==============================
# 1. 初始化 /tmp 目录结构
# ==============================
echo "Initializing directory structure in /tmp..."
# komari-upgrade-backup: 对应 /app/backup 软链，供上游版本升级打包 ./data
# theme / plugin 等数据目录在 restore 之后再创建，避免 BusyBox `cp -a`
# 在目标已存在时嵌套成 /tmp/theme/theme/（主题市场安装包「备份了却还原丢」）。
mkdir -p /tmp/komari-upgrade-backup

# ==============================
# 2. 启动定时备份任务 (supercronic)
# ==============================
echo "Starting supercronic for scheduled backups..."
supercronic /app/crontab &

# ==============================
# 3. 尝试恢复备份
# ==============================
echo "Restoring backup if available..."
# 恢复目标：/tmp（= /app/data）下的 komari.db / metrics.db / theme / plugin 等
/app/backup.sh restore

# 与上游 internal/server/bootstrap.go 对齐；备份没有对应项或全新安装时补齐空目录
mkdir -p /tmp/theme /tmp/plugin /tmp/plugin-data /tmp/komari-upgrade-backup

# ==============================
# 4. 启动 komari-agent
# ==============================
if [ -n "$KOMARI_SECRET" ]; then
    echo "Starting komari-agent setup process..."
    (
        # --- 步骤 4.1: 等待 Server 端口就绪 ---
        count=0
        while ! nc -z localhost 8080 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count+1))
        done

        if ! nc -z localhost 8080 2>/dev/null; then
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
        /app/komari-agent -e http://localhost:8080 -t "${KOMARI_SECRET}" --disable-auto-update
    ) &
else
    echo "Warning: KOMARI_SECRET is not set, skipping komari-agent"
fi

# ==============================
# 4. 启动 Caddy 作为后台进程
# ==============================
echo "Starting Caddy on port 8081..."
caddy run --config /app/Caddyfile --adapter caddyfile &

# ==============================
# 5. 启动主应用
# ==============================
echo "Starting app..."
# 确保主应用也读取 /tmp/komari.db (通过 Dockerfile 中的 ENV 已经指定)
exec /app/komari server
