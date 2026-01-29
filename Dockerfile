FROM ghcr.io/komari-monitor/komari:latest

# 1. 安装必要工具
# 注意：Choreo 环境中运行不需要 root，但构建镜像时需要 root 安装软件
USER root

RUN apk add --no-cache \
    aws-cli \
    tar \
    gzip \
    sqlite \
    tzdata \
    && rm -rf /var/cache/apk/*

# 2. 复制二进制文件
COPY --from=ghcr.io/komari-monitor/komari-agent:latest /app/komari-agent /app/komari-agent

# 3. 设置工作目录并调整权限
WORKDIR /app
# 预先创建可能需要的目录，并确保 10014 用户有权访问 /app 目录下的脚本
RUN mkdir -p /app/data && chmod -R 777 /app

# 4. 关键环境变量修改
ENV TZ=Asia/Shanghai
ENV GIN_MODE=release
ENV KOMARI_DB_TYPE=sqlite
# 将数据库文件指向 Choreo 唯一允许写入的 /tmp 目录
ENV KOMARI_DB_FILE=/tmp/komari.db
ENV KOMARI_LISTEN=0.0.0.0:25774

# 5. 复制脚本并设置权限
COPY backup.sh /app/backup.sh
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/*.sh

# 6. 切换到 Choreo 指定的用户
USER 10014

# 暴露端口
EXPOSE 25774

# 启动命令
CMD ["/app/entrypoint.sh"]
