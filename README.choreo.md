# Komari - Choreo 部署版本

这是 Komari 监控面板的 Choreo 平台适配版本。目标是在 Choreo 的限制下尽量少改上游：

- Dashboard 直接基于 `ghcr.io/komari-monitor/komari:latest`
- 运行时可写数据全部放到 `/tmp`
- 通过 R2/S3 定时备份 `/tmp` 数据（`komari.db` + `metrics.db` + theme）
- REST 与 WebSocket 拆分到不同端口，符合 Choreo endpoint 限制
- Cloudflare：主域 Snippet 处理 HTTP；`ws.` 子域直绑 Choreo WS（推荐不经 Worker）
- 外部 Agent 通过最小 patch 支持 `-e https://主域` 自动拼 `ws.` + Choreo WS 前缀
- 容器内可选内置官方 `komari-agent`，直连 `localhost:8080`

## 主要特性

- 支持 Choreo 只读文件系统：`/app/data -> /tmp`
- 支持 R2/S3 备份后端（`script/backup.sh`）
- 容器启动时自动恢复最新备份
- 定时备份，默认保留 7 天
- 备份主库、metric store（1.2.6+）、theme
- Dashboard REST endpoint 与 WebSocket endpoint 分端口暴露
- Cloudflare Snippet 处理 Choreo Public URL 路径前缀 + Cookie Domain
- Snippet 注入前端 WebSocket：`ws.{host}` + `/default/komari/komari_ws/v1.0`
- 可选启动内置 `komari-agent`

## 架构

### 模式一：Snippet + Choreo WS 直绑（推荐）

HTTP 走 Snippet（免费无限），WebSocket 直连 `ws.` 子域上的 Choreo WS 自定义域名（不经 Worker）。

```text
komari.example.com (Snippet)
├── 浏览器/Agent HTTP → Snippet → Choreo REST :8080 → Komari
└── HTML 注入 WebSocket:
      host → ws.{host}
      path → /default/komari/komari_ws/v1.0 + 原 path

ws.komari.example.com
└── 绑定 Choreo WS 自定义域名（保留网关前缀，不挂 Worker）
    wss://ws.../default/komari/komari_ws/v1.0/api/...

外部 Agent（patched）
  -e https://komari.example.com
  ├─ HTTP → 主域 Snippet
  └─ WS   → 自动 wss://ws.{host}/default/komari/komari_ws/v1.0/api/clients/...

内置 Agent（可选）
  -> /app/komari-agent -> http://localhost:8080
```

**原理：**

- Snippet 在返回 HTML 时注入脚本，monkey-patch `window.WebSocket`
- Snippet 改写 `Set-Cookie` 的 `session_token`，添加 `Domain=.{host}`
- patched Agent 与前端使用同一套 `ws.` + 路径前缀约定
- HTTP 前缀 `/default/komari/v1.0` 由 Snippet 服务端补齐
- WS 前缀 `/default/komari/komari_ws/v1.0` 由客户端（注入脚本 / agent patch）补齐，**无需 Cloudflare URL Rewrite**

### 模式二：独立 Worker（备选）

所有流量（HTTP + WebSocket）都走 Worker。

```text
komari.example.com (Worker)
├── 浏览器 HTTP → Worker → Choreo REST :8080
├── 浏览器 WebSocket → Worker → Choreo WS :8081
└── 外部 Agent → Worker（官方 agent 即可；见下方注意）
```

> patched agent 默认会把公网 `-e` 改成 `ws.{host}+前缀`。若使用独立 Worker 主域名，请改用官方 agent，或加  
> `--ws-endpoint https://komari.example.com`。

### 模式三：Snippet + Worker 混合（旧方案）

WS 走 Worker。功能完整，但重连时容易打满 Workers 额度（429 / error 1027）。仅在无法给 `ws.` 绑 Choreo 域名时使用。

## 文件结构

```text
choreo-komari/
├── Dockerfile                        # Choreo 专用 Dockerfile
├── README.md                         # 上游版本追踪（CI update-version 使用）
├── README.choreo.md                  # 本文档（部署说明）
├── AGENT.choreo.md                   # 外部 patched Agent 说明
├── worker/
│   ├── _snippet.js                   # Cloudflare Snippet (推荐 HTTP)
│   ├── _worker.js                    # Cloudflare Worker  (旧混合模式 WS)
│   ├── _worker_standalone.js         # Cloudflare Worker  (独立模式)
│   └── cloudflare-worker.js          # 同 _worker_standalone.js (兼容旧引用)
├── .choreo/
│   └── component.yaml                # Choreo endpoint 配置
├── script/
│   ├── backup.sh                     # R2 备份与恢复
│   ├── entrypoint.sh                 # 容器启动脚本
│   ├── crontab                       # 定时备份任务
│   └── Caddyfile                     # WS 端口反代到 Komari
├── agent/
│   └── apply-choreo-endpoint.sh      # 上游 agent 最小 patch
└── .github/workflows/
    ├── update-version.yml            # 同步上游 release 到 README.md
    └── build-choreo-agent.yml        # 构建 patched agent
```

## 部署到 Choreo

### 1. 创建 Service Component

在 Choreo Console 创建 Service Component，并连接本仓库。

构建配置：

```text
Build Preset: Docker
Dockerfile Path: Dockerfile
Component Directory: /
```

### 2. 配置 endpoint

仓库已包含 `.choreo/component.yaml`。需要保留两个 Public endpoint：

| endpoint | 端口 | 类型 | 用途 |
|---|---|---|---|
| `komari` | `8080` | `REST` | Dashboard HTTP 页面和 API |
| `komari_ws` | `8081` | `WS` | 前端 WebSocket 与 Agent WS（经 Caddy） |

> Choreo 不支持同一个 Public endpoint 同时承载 REST 与 WebSocket。Komari 在 8080 上虽可多路复用，但在 Choreo 上必须拆分；8081 由 Caddy 反代回 8080。

### 3. 环境变量（常用）

| 变量 | 说明 |
|---|---|
| `KOMARI_SECRET` | 内置 agent token；设置后启动本地 agent |
| `KOMARI_AGENT_UUID` | 可选，内置 agent UUID |
| `KOMARI_AGENT_NAME` | 可选，默认 `Local Agent` |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT_URL` / `R2_BUCKET_NAME` | 备份 |

### 4. Cloudflare

#### 推荐：Snippet + `ws.` 直绑

1. **Rules → Snippets**：粘贴 `worker/_snippet.js`  
   修改配置区 `CHOREO_ORIGIN` / 前缀后，匹配主域名
2. 在 Choreo 为 **WS endpoint** 绑定 `ws.komari.example.com`  
   确认路径保留 `/default/komari/komari_ws/v1.0/...`
3. **不要**把 `ws.` 绑到 Worker
4. Zone **Network → WebSockets** = On

配置区示例：

```javascript
const CHOREO_ORIGIN = "xxxxx-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";
```

值来自 Choreo Dashboard → Component → Endpoints。

#### 外部 Agent

详见 [AGENT.choreo.md](./AGENT.choreo.md)。

```bash
komari-agent \
  -e "https://komari.example.com" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

## 上游 1.2.6 / 1.2.7 注意

这是破坏性升级（监控数据迁到独立 metric store）：

1. 若库中仍有旧监控表数据，启动会进入**受限升级向导**（`/admin/update/1.2.7`）
2. 升级模式下普通 API / Agent / WS 关闭，重连可能打满 Worker 额度
3. 迁移完成后勿再停留在升级页（升级 API 会返回 HTML，前端报 JSON 解析错误）
4. `script/backup.sh` 已同时备份 / 恢复 `metrics.db`
5. Choreo 容器重启会丢 `/tmp`，迁移成功后立刻备份

处理步骤：

1. 临时停外部 Agent / 暂停 Worker
2. 打开主域完成升级向导（或确认已不在升级模式）
3. 恢复 Snippet + `ws.` 直绑架构
4. 使用 patched agent 重新上线

## 故障排查

### WebSocket 失败

浏览器 DevTools → Network → WS 期望：

```text
wss://ws.{host}/default/komari/komari_ws/v1.0/api/rpc2
```

- 若无前缀：Snippet 未更新到 `worker/_snippet.js`
- 若 `429` / `error code: 1027`：`ws.` 仍挂在被打满的 Worker 上

### Agent 离线

- 外部节点必须用 **patched** agent，`-e` 为主域
- 日志 WS URL 应含 `/default/komari/komari_ws/v1.0/api/clients/`
- 建议 `--disable-auto-update`

### 登录 / Cookie

- Snippet 会给 `session_token` 加 `Domain=.{host}`
- 切换部署模式后清 Cookie 再登录

## 相关文档

- [AGENT.choreo.md](./AGENT.choreo.md) — 外部 patched Agent
- [worker/_snippet.js](./worker/_snippet.js) — Snippet 源码
- [script/backup.sh](./script/backup.sh) — 备份 / 恢复
- [`.choreo/component.yaml`](./.choreo/component.yaml) — Choreo endpoints
