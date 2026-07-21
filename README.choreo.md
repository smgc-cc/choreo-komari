# Komari - Choreo 部署说明

两套部署方式：

1. **模式一（推荐）**：Cloudflare Snippet + 官方 agent 长基址
2. **模式二（备选）**：全流量 Cloudflare Worker

---

## 模式一：Snippet（推荐）

### 架构

```text
komari.example.com（本 zone 橙云）
├── HTTP  → Snippet → CHOREO_ORIGIN + /default/komari/v1.0/...
└── WebSocket
      注入补路径前缀（WS_PUBLIC_HOST 为空 = 同源）
      wss://komari.example.com/default/komari/komari_ws/v1.0/...
      → 原生穿透 → Choreo WS → Caddy :8081 → Komari

官方 Agent
  -e https://komari.example.com/default/komari/komari_ws/v1.0
  ├─ WSS  原生穿透（路径已是 komari_ws 前缀）
  └─ HTTP Snippet 将 .../komari_ws/v1.0/api/... 改写为 REST .../v1.0/api/...

Choreo（自定义域绑 komari.example.com）
  REST :8080  /default/komari/v1.0
  WS   :8081  /default/komari/komari_ws/v1.0
```

同源时 cookie 为 **host-only**，终端可直接带登录态；**不必** `session_token` query（Caddy 仍兼容有 query 的情况）。

### 前提

| 项 | 说明 |
|---|---|
| DNS | 域名在 **本 Cloudflare zone** 橙云（不要灰云直连错误源站） |
| Choreo | 自定义域名绑到组件（一服务通常一个自定义域） |
| Network | **WebSockets = On** |
| SSL 回源 | 源站为 `*.choreoapis.dev` 时建议 **Full**（非 Full Strict） |

### Snippet

文件：`worker/_snippet.js`

```javascript
const CHOREO_ORIGIN = "xxxxx-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";
// 单域名：留空 = WebSocket 与页面同 host（推荐）
const WS_PUBLIC_HOST = "";
// 一般保持空（host-only cookie）
const COOKIE_DOMAIN = "";
```

匹配：你的面板域名（如 `komari.example.com`）。

要点：

- `toChoreoHttpPath`：官方 agent 长基址 HTTP 的 `komari_ws` → REST `v1.0`
- `WS_PUBLIC_HOST === ""` 时注入只补路径前缀，不改 host
- HTML：`Cache-Control: no-store`；首页不注入登录态；仅 `/admin*` `/terminal*` 在有 cookie 时注入 `T`（多域名跨站终端用）

### Caddy（容器 8081）

文件：`script/Caddyfile`

- 剥网关前缀（若有）
- `admin-terminal` → `/api/admin/client/{uuid}/terminal`
- 终端路径上可选 `?session_token=` → `Cookie`（单域名通常不需要 query）

### Agent

见 [AGENT.choreo.md](./AGENT.choreo.md)。

```bash
komari-agent \
  -e "https://komari.example.com/default/komari/komari_ws/v1.0" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

**不要**写 `wss://` 作 `-e`。

### 验证（单域名）

```bash
# 注入（应看到 WebSocket 脚本与 komari_ws 前缀）
curl -sS "https://komari.example.com/" | grep -o "window.WebSocket" | head -1

# HTTP
curl -sS "https://komari.example.com/api/version"

# 公开 WS（期望 101 或 401 JSON，不要 530 HTML）
curl --http1.1 -sS -D- -o /dev/null -m 12 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "https://komari.example.com/default/komari/komari_ws/v1.0/api/rpc2" | head -12

# 官方 agent HTTP 长路径
curl -sS -D- -o /dev/null -X POST \
  "https://komari.example.com/default/komari/komari_ws/v1.0/api/clients/uploadBasicInfo?token=x" \
  -H "Content-Type: application/json" -d '{}' | head -12
```

浏览器 DevTools → WS：

```text
wss://komari.example.com/default/komari/komari_ws/v1.0/api/rpc2
wss://komari.example.com/default/komari/komari_ws/v1.0/api/admin/client/{uuid}/terminal
# 或 admin-terminal 捷径（注入会改写终端路径）
```

---

## 模式二：全流量 Worker（备选）

文件：`worker/_worker_standalone.js`

```text
komari.example.com（Worker 自定义域）
├── HTTP → Worker → Choreo REST 前缀
└── WS   → Worker → Choreo WS 前缀 → Caddy
```

### 何时用

- 没有 Snippet 
- 可接受 Workers **日请求额度**（页面、静态资源也计次）

### 部署

1. Create Worker，粘贴 `_worker_standalone.js`，改 `CHOREO_ORIGIN`
2. 绑定自定义域名

### Agent

短 `-e` 即可（Worker 按协议分别补前缀）：

```bash
komari-agent \
  -e "https://komari.example.com" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

浏览器同源；终端用 Cookie，无需 session query。

生产更推荐模式一（HTTP 走 Snippet，WS 穿透不计 Worker 请求）。

---

## 备份（R2 / WebDAV）

`script/backup.sh`，启动 restore、每 2 小时 backup。

| `BACKUP_BACKEND` | 变量 |
|---|---|
| `r2`（默认） | `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT_URL` / `R2_BUCKET_NAME` |
| `webdav` | `WEBDAV_URL` / `WEBDAV_USERNAME` / `WEBDAV_PASSWORD`（或 `WEBDAV_USER`/`PASS`） |
| `none` | 关闭 |

内容：`komari.db` + `metrics.db` + `theme/`；约保留 7 天。

```bash
/app/backup.sh backup
/app/backup.sh restore
```

---

## Choreo 组件

`.choreo/component.yaml`：

| endpoint | 端口 | 类型 |
|---|---|---|
| `komari` | 8080 | REST |
| `komari_ws` | 8081 | WS（Caddy） |

常见环境变量：`KOMARI_SECRET`（内置 agent）、备份相关变量。

---

## 站点设置：CORS / WebSocket Origin / Agent 连接地址

这三项由 **Komari 管理后台** 写入配置库（`configs` 表），**不是** Docker 环境变量，部署后登录面板配置即可（热更新，一般无需重启）。

入口：**管理后台 → 设置 → 站点**（路径多为 `/admin/settings/site`）。

| 界面名称 | 配置键 | 作用 |
|---|---|---|
| API CORS 允许列表 | `cors_allowed_origins` | 跨域浏览器请求 `/api/*` 时允许的 `Origin` |
| WebSocket Origin 允许列表 | `ws_allowed_origins` | 校验 WebSocket 握手 `Origin` 时的允许列表 |
| Agent 连接地址 | `script_domain` | 后台生成一键安装命令时填入的面板地址（**不**覆盖 agent 自己的 `-e`） |

### 填写格式

允许列表支持：

- 完整 Origin：`https://komari.example.com`
- 仅 host：`komari.example.com`
- 多条：换行或英文逗号分隔
- 可选：`*`（放行所有 Origin，谨慎使用）

示例：

```text
https://komari.example.com
https://other.example.com
```

### 与本部署的关系

| 场景 | 是否必须改这三项 |
|---|---|
| 单域名、浏览器同源访问 | 通常 **不用改**；同源即放行 |
| 模式一 Snippet，页面与 API 同源 | CORS 列表一般用不到 |
| 模式一跨域调 API / 自定义前端 | 在 CORS 列表加入前端 Origin |
| WebSocket Origin 校验 | 本镜像默认 `KOMARI_WS_DISABLE_ORIGIN=true`，**关闭**服务端 Origin 检查；若改为 `false`，则需在「WebSocket Origin 允许列表」写入页面 Origin，或保持同源 |
| 安装脚本里的面板 URL | 在「Agent 连接地址」填用户应使用的地址；公网 agent 仍以实际 `-e` 为准（见 [AGENT.choreo.md](./AGENT.choreo.md)） |

### 相关开关

| 设置 | 默认 | 说明 |
|---|---|---|
| CORS 跨域请求校验（`cors_origin_check_enabled`） | 开启 | 关闭后不再校验 API CORS |
| WebSocket Origin 校验（`ws_origin_check_enabled`） | 开启 | 关闭后不校验 WS Origin；**环境变量** `KOMARI_WS_DISABLE_ORIGIN=true` 可在进程级强制关闭（本 Dockerfile 默认已设） |

### 注意

- 修改后一般立即生效，无需重建镜像。
- 配置保存在 `komari.db`，会随 [备份](#备份r2--webdav) 一起备份/恢复。
- 「Agent 连接地址」只影响**面板生成的安装命令文案**；已部署节点不会因改此项自动换 endpoint。

---

## 文件结构

```text
choreo-komari/
├── Dockerfile
├── README.md / README.choreo.md / AGENT.choreo.md
├── .choreo/component.yaml
├── script/
│   ├── backup.sh / Caddyfile / entrypoint.sh / crontab
└── worker/
    ├── _snippet.js              # 模式一
    └── _worker_standalone.js    # 模式二
```

---

## 故障速查

| 现象 | 处理 |
|---|---|
| 无 WebSocket 注入 | Snippet 未匹配域名 / 未部署 |
| WS 无 `komari_ws` 前缀 | 注入未生效 |
| 官方 agent HTTP 404 | Snippet 未匹配 agent 所连域名 |
| `-e` 写成 `wss://` | 改为 `https://` |
| WS 530 HTML | 域名未橙云 / 未绑 Choreo / 源站不对 |
| 终端 401 | 未登录；或跨域场景下未注入 `session_token` 且 Caddy 未处理 |
| Worker 额度打满 | 改回模式一 |

---

## 对比

| | 模式一 Snippet | 模式二 Worker |
|---|---|---|
| Agent | 官方 + **长基址** | 官方 + **短 `-e`** |
| 边缘费用 | HTTP≈免费；WS 穿透 | 全流量计 Workers |
| 终端 cookie | 同源即可 | 同源 Cookie |
| 推荐 | **生产默认** | 无 Snippet |

---

## 附录：Snippets 多域名特例（可选，非必须）

仅当 **面板入口域名** 与 **Choreo 绑定域名** 不是同一个时使用（例如品牌域经 SaaS、Snippets 基建域在另一 zone）。

示例：

| 角色 | 主机 |
|---|---|
| 浏览器入口 | `komari.example.com` |
| Choreo 绑定 + Agent + WS | `komari.snippets.com` |

此时 Snippet：

```javascript
const WS_PUBLIC_HOST = "komari.snippets.com"; // 浏览器 WS 改到基建域
const COOKIE_DOMAIN = ""; // 跨注册域无法共享 cookie，保持空
```

匹配规则加上 **入口域 + 基建域** 两个 host。

影响：

- 浏览器 WS 在基建域；**终端** cookie 带不过去 → 注入 `?session_token=` + Caddy 转 Cookie  
- Agent 仍建议：  
  `-e https://komari.snippets.com/default/komari/komari_ws/v1.0`  
- 日常从入口域登录并打开终端；勿混用未登录的基建域页面

**默认部署不必多域名。** 能单域名绑 Choreo 时，优先单域名（`WS_PUBLIC_HOST = ""`）。
