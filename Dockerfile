# ==========================================
# 基于上游 Komari 镜像进行 Choreo 适配
# ==========================================
FROM ghcr.io/komari-monitor/komari:latest

USER root

# 安装工具
RUN apk add --no-cache \
    caddy \
    aws-cli \
    tar \
    gzip \
    sqlite \
    tzdata \
    curl \
    && rm -rf /var/cache/apk/*

# 安装 supercronic (容器友好的 cron 替代品)
RUN curl -fsSL "https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64" -o /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

# 安装二进制文件
COPY --from=ghcr.io/komari-monitor/komari-agent:latest /app/komari-agent /app/komari-agent

WORKDIR /app

# --- 关键修复：解决只读文件系统 ---
# Choreo 上 /app 只读，可写目录只有 /tmp
# 1. ./data  -> /tmp           （主库/metrics/theme 等）
# 2. ./backup -> /tmp/komari-upgrade-backup
#    上游版本升级会 mkdir ./backup 并打包 upgrade-*.zip；不链到可写目录会报:
#    [ERROR/DBCORE] [upgrade-backup] failed to create backup dir: mkdir ./backup: read-only file system
RUN rm -rf /app/data /app/backup \
    && ln -s /tmp /app/data \
    && ln -s /tmp/komari-upgrade-backup /app/backup

# 设置环境变量
ENV TZ=Asia/Shanghai
ENV GIN_MODE=release
ENV KOMARI_DB_TYPE=sqlite
# 数据库路径现在通过软链接等同于 /app/data/komari.db
ENV KOMARI_DB_FILE=/tmp/komari.db
ENV KOMARI_LISTEN=0.0.0.0:8080
# 禁用 WebSocket Origin 检查（因为请求经过 Cloudflare / 自定义域名代理，Origin 和 Host 可能不匹配）
ENV KOMARI_WS_DISABLE_ORIGIN=true

# 复制 Choreo 适配脚本与配置
COPY script/Caddyfile /app/Caddyfile
COPY script/backup.sh /app/backup.sh
COPY script/entrypoint.sh /app/entrypoint.sh
COPY script/crontab /app/crontab
RUN chmod +x /app/*.sh

# 切换到 Choreo 指定用户
USER 10014

EXPOSE 8080 8081

CMD ["/app/entrypoint.sh"]
