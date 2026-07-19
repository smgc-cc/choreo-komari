# Cloudflare 代理部署指南

Komari 部署在 Choreo 平台后，需要通过 Cloudflare 代理来处理路径前缀映射和 WebSocket 转发。本项目提供两种部署模式，按需选择。

## 架构概览

```
Choreo 平台内部:
  Komari (8080) ← HTTP 端点 (/default/komari/v1.0/*)
  Caddy  (8081) → Komari ← WS 端点 (/default/komari/komari_ws/v1.0/*)

Cloudflare 代理层 (本文件覆盖的部分):
  浏览器/Agent → Cloudflare → Choreo
```

Choreo 为每个端点强制添加路径前缀（如 `/default/komari/v1.0/`），而 Komari 前端使用绝对路径（`/api/rpc2`、`/assets/...`），两者不匹配。代理层负责在中间做路径改写。

---

## 模式一：Worker 独立部署（推荐）

**文件：`_worker_standalone.js`**

所有流量（HTTP + WebSocket）由一个 Worker 处理。最简单，功能最完整。

### 适用场景

- 日均请求量在 Workers Free 额度内（10 万次/天）
- 不想维护多个组件

### 额度评估

WebSocket 连接建立后，后续消息走 WS 帧**不消耗请求额度**。实际消耗主要来自页面加载和 API 调用：

| 来源 | 日请求量 |
|---|---|
| 1 个浏览器标签页（WS 连接成功） | ~几百次（页面+资源+API） |
| 1 个外部 Agent（WS 连接成功） | ~几百次（basicInfo 等） |
| 总计 | 远低于 10 万/天 |

### 部署步骤

1. Cloudflare Dashboard → **Workers & Pages** → Create Worker
2. 粘贴 `_worker_standalone.js` 内容并部署
3. Worker Settings → **Domains & Routes** → 添加自定义域名（如 `komari.example.com`）
4. 确保该域名的 DNS 记录开启 Cloudflare 代理（橙色云朵）

### 外部 Agent 配置

```bash
komari-agent -e https://komari.example.com -t "YOUR_TOKEN"
```

---

## 模式二：Snippet + Worker 混合部署

**文件：`_snippet.js` + `_worker.js`**

HTTP 流量走 Snippet（免费无限额度），WebSocket 走 Worker（极少请求量）。适合追求零成本的场景。

### 适用场景

- 希望尽可能减少 Worker 请求消耗
- 已有 Cloudflare Snippet 基础设施

### 工作原理

```
浏览器访问 komari.example.com
  ├─ HTTP (页面/API/资源) → Snippet → Choreo HTTP 端点      [免费无限]
  └─ WebSocket            → ws.komari.example.com (Worker)
                            → Choreo WS 端点                [每连接 1 次请求]

外部 Agent (-e https://ws.komari.example.com)
  ├─ WS 上报/终端         → Worker → Choreo WS 端点
  └─ HTTP 上报 (basicInfo) → Worker → Choreo HTTP 端点
```

Snippet 在返回 HTML 时注入脚本，自动将前端 WebSocket 连接从 `komari.example.com` 重定向到 `ws.komari.example.com`。域名从 `location.host` 自动推导，不硬编码。

### 关键设计

| 问题 | 解决方案 |
|---|---|
| Snippet 不支持 WebSocket | WS 由 Worker 在 `ws.` 子域名处理 |
| 跨子域名 Cookie | Snippet 改写 `Set-Cookie` 加 `Domain=.{host}`，使 `session_token` 对 `ws.` 子域名生效 |
| Gin 301 丢路径前缀 | `redirect: "manual"` + 重新拼接 Choreo 前缀 |
| Worker 域名暴露 | Worker 对非 WebSocket、非 Agent API 的请求返回 426 |
| 外部 Agent HTTP 上报 | Worker 放行 `/api/clients/*` 的 HTTP 请求 |

### 部署步骤

#### 1. 部署 Worker

1. Workers & Pages → Create Worker
2. 粘贴 `_worker.js` 内容并部署
3. Worker Settings → **Domains & Routes** → Add → **Custom Domain**（不是 Route）
4. 填入 `ws.komari.example.com`
5. Cloudflare 会自动创建 DNS 记录

> ⚠️ 必须用 **Custom Domain**，不能用 Route。Route 在优选 IP / SaaS 架构下可能不生效。

#### 2. 部署 Snippet

1. 进入域名的 **Rules → Snippets**
2. 创建 Snippet，粘贴 `_snippet.js` 内容
3. 匹配规则设为目标域名（如 `komari.example.com`）

#### 3. 配置外部 Agent

```bash
# 外部 Agent 必须指向 ws. 子域名（主域名的 WS 被 Snippet 跳过会失败）
komari-agent -e https://ws.komari.example.com -t "YOUR_TOKEN"
```

### 额度消耗

| 来源 | 走 Snippet (免费) | 走 Worker (计额度) |
|---|---|---|
| 页面/资源加载 | ✅ | |
| API 调用 (RPC2 POST) | ✅ | |
| 前端 WebSocket | | ✅ 建连 1 次 |
| 外部 Agent WS | | ✅ 建连 1 次 |
| 外部 Agent HTTP (basicInfo) | | ✅ 每 5 分钟 1 次 |

日均 Worker 请求量 ≈ **几十次**（WS 建连 + Agent basicInfo），远低于 10 万/天限额。

---

## 配置区域

三份脚本的配置区域相同，部署前按你的 Choreo 环境修改：

```javascript
const CHOREO_ORIGIN = "xxxxx-dev.e1-us-east-azure.choreoapis.dev";  // Choreo 应用域名
const HTTP_PATH_PREFIX = "/default/komari/v1.0";                     // HTTP 端点路径前缀
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";             // WS 端点路径前缀
```

这些值来自 Choreo Dashboard → Component → Endpoints 页面。

---

## 文件清单

| 文件 | 用途 | 部署位置 |
|---|---|---|
| `_worker_standalone.js` | 独立模式：全功能 Worker | Cloudflare Worker |
| `_worker.js` | 混合模式：WS + Agent HTTP 代理 | Cloudflare Worker |
| `_snippet.js` | 混合模式：HTTP 代理 + WS 注入 | Cloudflare Snippet |

---

## 故障排查

### WebSocket 连接失败 (1006)

- **独立模式**：检查 Worker 是否绑定了自定义域名（不能用 `*.workers.dev` 代理 WS 到需要特定 Host 的后端）
- **混合模式**：确认 `ws.` 子域名是用 **Custom Domain** 绑定的（不是 Route）；检查浏览器 DevTools → Network → WS 连接的实际 URL 是否是 `wss://ws.{host}/api/rpc2`

### Admin 页面 404

Gin 对 `/api/admin/settings` 返回 301 到 `/api/admin/settings/`，但 Location 不带 Choreo 路径前缀。确认代理使用 `redirect: "manual"` 并手动跟随重定向时重新拼接前缀。

### 外部 Agent 连不上

- **独立模式**：`-e` 指向 Worker 自定义域名
- **混合模式**：`-e` 必须指向 `ws.` 子域名（主域名的 Snippet 会跳过 WS 请求）

### Cookie / 登录态丢失

混合模式下，Snippet 会改写 `session_token` 的 `Set-Cookie` 加 `Domain=.{host}`。如果切换过部署模式，需要**清除浏览器 Cookie 并重新登录**。

### 上游升级到 1.2.6/1.2.7 后：连不上 / 登不上 / Worker 请求爆表

这通常**不是** Cloudflare 代理坏了，而是 Komari 进入了 **1.2.7 受限升级向导模式**。

触发条件：主库里仍有未迁移的旧监控表数据（`records` / `gpu_records` / `ping_records`），且配置键 `migration_legacy_monitoring_to_metric_store_done` 未完成。

升级模式下后端行为：

| 路径 | 行为 |
|---|---|
| `/api/login`、`/api/me`、OAuth | 可用 |
| `/api/admin/update/1.2.7/*` | 升级 API |
| 页面路由 | 307 重定向到 `/admin/update/1.2.7` |
| `/api/rpc2`、`/api/clients/*`、Agent 上报、普通 Admin API | **不存在**（404 / Not found in upgrade mode） |

后果：

- 前端 WebSocket（`/api/rpc2`、`/api/clients`）建连失败 → 注入脚本把 WS 打到 `ws.` 子域名 → Worker 反复收到失败升级请求
- 外部 Agent 的 WS / HTTP 上报全部失败并重试 → Worker 请求数暴涨
- 后台“像登不上”：登录可能成功，但正常管理 API 不存在，页面功能全挂

处理步骤：

1. 临时停外部 Agent / 暂停 Worker，止血请求额度
2. 浏览器打开主域名，完成 `/admin/update/1.2.7` 向导（登录管理员 → 可选清理旧数据 → 迁移到 `./data/metrics.db`）
3. 迁移完成后服务自动恢复正常路由；再启 Agent 与 Worker
4. 立刻跑一次备份，确认 R2 包内同时有 `komari.db` 与 `metrics.db`

Choreo 注意：`./data` 被软链到 `/tmp`，容器重启会丢未备份数据。`backup.sh` 已支持 `metrics.db`。
