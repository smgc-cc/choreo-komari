# ==========================================
# 阶段 1: 构建 Komari Server
# 固定上游版本；前端使用 komari-web release artifact，避免在 Choreo 内跑 npm/Vite。
# ==========================================
FROM golang:alpine AS komari-builder

ARG KOMARI_VERSION=1.2.5
ARG KOMARI_WEB_VERSION=1.2.5

WORKDIR /src

RUN apk add --no-cache git build-base curl unzip python3

RUN git clone https://github.com/komari-monitor/komari.git .

RUN git fetch --tags && git checkout "$KOMARI_VERSION"

COPY patch/apply-komari-readwait-env.sh /tmp/apply-komari-readwait-env.sh
RUN sh /tmp/apply-komari-readwait-env.sh

RUN curl -fsSL "https://github.com/komari-monitor/komari-web/releases/download/${KOMARI_WEB_VERSION}/dist-release.zip" -o /tmp/komari-web-dist.zip && \
    unzip -q /tmp/komari-web-dist.zip -d /tmp/komari-web-release && \
    mkdir -p web/public/defaultTheme/dist && \
    rm -rf web/public/defaultTheme/dist/* && \
    cp -r /tmp/komari-web-release/dist/* web/public/defaultTheme/dist/ && \
    cp -f /tmp/komari-web-release/komari-theme.json web/public/defaultTheme/ && \
    if [ -f /tmp/komari-web-release/preview.png ]; then cp -f /tmp/komari-web-release/preview.png web/public/defaultTheme/; fi && \
    if [ -f /tmp/komari-web-release/perview.png ]; then cp -f /tmp/komari-web-release/perview.png web/public/defaultTheme/; fi && \
    if [ -f web/public/defaultTheme/preview.png ] && [ ! -f web/public/defaultTheme/perview.png ]; then cp -f web/public/defaultTheme/preview.png web/public/defaultTheme/perview.png; fi && \
    if [ -f web/public/defaultTheme/perview.png ] && [ ! -f web/public/defaultTheme/preview.png ]; then cp -f web/public/defaultTheme/perview.png web/public/defaultTheme/preview.png; fi

RUN VERSION=$(git describe --tags --always) && \
    HASH=$(git rev-parse --short HEAD) && \
    go mod download && \
    CGO_ENABLED=1 go build \
    -trimpath \
    -ldflags="-s -w -X github.com/komari-monitor/komari/utils.CurrentVersion=${VERSION} -X github.com/komari-monitor/komari/utils.VersionHash=${HASH}" \
    -o komari .

# ==========================================
# 阶段 2: 获取 Komari Agent
# 使用上游 release binary，避免在 Choreo 内重复编译 agent。
# ==========================================
FROM golang:alpine AS agent-builder

ARG KOMARI_AGENT_VERSION=1.2.13
ARG TARGETARCH

WORKDIR /src

RUN apk add --no-cache curl

RUN set -eux; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
        case "$(uname -m)" in \
            x86_64) arch=amd64 ;; \
            aarch64) arch=arm64 ;; \
            armv7l) arch=arm ;; \
            i386|i686) arch=386 ;; \
            *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
        esac; \
    fi; \
    curl -fsSL "https://github.com/komari-monitor/komari-agent/releases/download/${KOMARI_AGENT_VERSION}/komari-agent-linux-${arch}" -o komari-agent; \
    chmod +x komari-agent

# ==========================================
# 第三阶段：运行环境 (Final Image)
# 基于 Alpine
# ==========================================
FROM alpine:3.21

ARG SUPERCRONIC_VERSION=v0.2.46
ARG TARGETARCH

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
RUN set -eux; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
        case "$(uname -m)" in \
            x86_64) arch=amd64 ;; \
            aarch64) arch=arm64 ;; \
            armv7l) arch=arm ;; \
            i386|i686) arch=386 ;; \
            *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
        esac; \
    fi; \
    curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${arch}" -o /usr/local/bin/supercronic; \
    chmod +x /usr/local/bin/supercronic

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
ENV HOME=/tmp
ENV XDG_CONFIG_HOME=/tmp/.config
ENV XDG_DATA_HOME=/tmp/.local/share
ENV KOMARI_DB_TYPE=sqlite
# 数据库路径现在通过软链接等同于 /app/data/komari.db
ENV KOMARI_DB_FILE=/tmp/komari.db
ENV KOMARI_LISTEN=0.0.0.0:8080
# Agent WebSocket 在线判定超时，可在 Choreo 环境变量中覆盖（例如 60s、120s 或纯数字秒）
ENV KOMARI_AGENT_READ_WAIT=60s
# 禁用 WebSocket Origin 检查（因为请求经过 Cloudflare Worker 代理，Origin 和 Host 不匹配）
ENV KOMARI_WS_DISABLE_ORIGIN=true

# 复制 Caddy 配置文件
COPY script/Caddyfile /app/Caddyfile

# 复制并授权脚本
COPY script/backup.sh /app/backup.sh
COPY script/entrypoint.sh /app/entrypoint.sh
COPY script/crontab /app/crontab
RUN chmod +x /app/*.sh

# 切换到 Choreo 指定用户
USER 10014

EXPOSE 8080 8081

CMD ["/app/entrypoint.sh"]
