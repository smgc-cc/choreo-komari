# ==========================================
# 阶段 1: 构建 Komari Server
# ==========================================
FROM golang:alpine AS komari-builder

WORKDIR /src

RUN apk add --no-cache git build-base nodejs npm

RUN git clone https://github.com/komari-monitor/komari.git .

RUN git fetch --tags && \
    LATEST_TAG=$(git describe --tags --abbrev=0) && \
    git checkout $LATEST_TAG

RUN git clone https://github.com/komari-monitor/komari-web.git web && \
    cd web && \
    npm install && \
    npm run build && \
    cd .. && \
    mkdir -p public/defaultTheme/dist && \
    rm -rf public/defaultTheme/dist/* && \
    cp -r web/dist/* public/defaultTheme/dist/ && \
    cp -f web/komari-theme.json public/defaultTheme/ && \
    if [ -f web/preview.png ]; then cp -f web/preview.png public/defaultTheme/; fi && \
    if [ -f web/perview.png ]; then cp -f web/perview.png public/defaultTheme/; fi && \
    if [ -f public/defaultTheme/preview.png ] && [ ! -f public/defaultTheme/perview.png ]; then cp -f public/defaultTheme/preview.png public/defaultTheme/perview.png; fi && \
    if [ -f public/defaultTheme/perview.png ] && [ ! -f public/defaultTheme/preview.png ]; then cp -f public/defaultTheme/perview.png public/defaultTheme/preview.png; fi

RUN VERSION=$(git describe --tags --always) && \
    HASH=$(git rev-parse --short HEAD) && \
    go get google.golang.org/grpc@v1.79.3 && \
    go mod tidy && \
    go mod download && \
    CGO_ENABLED=1 go build \
    -trimpath \
    -ldflags="-s -w -X github.com/komari-monitor/komari/utils.CurrentVersion=${VERSION} -X github.com/komari-monitor/komari/utils.VersionHash=${HASH}" \
    -o komari .

# ==========================================
# 阶段 2: 构建 Komari Agent
# ==========================================
FROM golang:alpine AS agent-builder

WORKDIR /src

# 安装 git
RUN apk add --no-cache git

# 1. 拉取源码
RUN git clone https://github.com/komari-monitor/komari-agent.git .

# 2. 检出最新的 Tag
RUN git fetch --tags && \
    LATEST_TAG=$(git describe --tags --abbrev=0) && \
    git checkout $LATEST_TAG

# 3. 编译并注入版本号
RUN VERSION=$(git describe --tags --always) && \
    echo "--------------------------------------" && \
    echo "正在构建版本: $VERSION" && \
    echo "--------------------------------------" && \
    go mod download && \
    CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w -X github.com/komari-monitor/komari-agent/update.CurrentVersion=${VERSION}" \
    -o komari-agent .

# ==========================================
# 第三阶段：运行环境 (Final Image)
# 基于 Alpine
# ==========================================
FROM alpine:3.21

USER root

# 升级基础镜像中的 OpenSSL 包，修复 libcrypto3/libssl3 漏洞
RUN apk upgrade --no-cache libcrypto3 libssl3

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

# 复制二进制文件
COPY --from=komari-builder /src/komari /app/komari
COPY --from=agent-builder /src/komari-agent /app/komari-agent

WORKDIR /app

# --- 关键修复：解决只读文件系统 ---
# 1. 删除原有的 data 目录
# 2. 建立软链接，将 data 指向 /tmp，这样程序读写 ./data/ 时实际在读写 /tmp/
RUN rm -rf /app/data && ln -s /tmp /app/data

# 设置环境变量
ENV TZ=Asia/Shanghai
ENV GIN_MODE=release
ENV KOMARI_DB_TYPE=sqlite
# 数据库路径现在通过软链接等同于 /app/data/komari.db
ENV KOMARI_DB_FILE=/tmp/komari.db
ENV KOMARI_LISTEN=0.0.0.0:8080
# 禁用 WebSocket Origin 检查（因为请求经过 Cloudflare Worker 代理，Origin 和 Host 不匹配）
ENV KOMARI_WS_DISABLE_ORIGIN=true

# 复制 Caddy 配置文件
COPY Caddyfile /app/Caddyfile

# 复制并授权脚本
COPY backup.sh /app/backup.sh
COPY entrypoint.sh /app/entrypoint.sh
COPY crontab /app/crontab
RUN chmod +x /app/*.sh

# 切换到 Choreo 指定用户
USER 10014

EXPOSE 8080 8081

CMD ["/app/entrypoint.sh"]
