# Choreo Komari Agent

外部 Agent 的最小改造：在上游 `komari-monitor/komari-agent` 上增加 Choreo 友好的 WebSocket 基址推导。

**不改协议**，只改 URL 拼接。HTTP 仍走主域 Snippet；WS 自动走 `ws.{host}` 并带上 Choreo 网关前缀。

## 为什么要 patch

Choreo 上 HTTP / WS 是两套路径前缀：

| 协议 | 前缀 |
|---|---|
| HTTP | `/default/komari/v1.0` |
| WebSocket | `/default/komari/komari_ws/v1.0` |

官方 agent 只有一个 `-e`，会把 HTTP 和 WS 都拼到同一基址。  
本 patch 让：

```bash
komari-agent -e https://komari.sfun.cc -t "TOKEN"
```

自动变成：

| 流量 | 实际 URL |
|---|---|
| HTTP | `https://komari.sfun.cc/api/clients/...` → Snippet → Choreo HTTP |
| WS | `wss://ws.komari.sfun.cc/default/komari/komari_ws/v1.0/api/clients/...` → Choreo WS |

`localhost` / 容器内置 agent **不会**加 `ws.` 前缀，继续直连本机。

## 改造内容

脚本：`agent/apply-choreo-endpoint.sh`（在上游源码树根目录执行）

1. `cmd/flags/flag.go`：新增 `WsEndpoint`、`WsPathPrefix`
2. `cmd/root.go`：注册 `--ws-endpoint`、`--ws-path-prefix`
3. `server/websocket.go`：
   - `wsBase()`：默认 `https://ws.{host}/default/komari/komari_ws/v1.0`
   - WS 建连 / 终端走 `wsBase()`
   - v2 HTTP POST fallback 仍走 `-e`（主域 Snippet）
4. `server/basicInfo.go`：HTTP 上报明确走 `httpBase()`（`-e`）

## 配置

### 推荐（自动推导）

```bash
./komari-agent \
  -e "https://komari.sfun.cc" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

环境变量：

```bash
export AGENT_ENDPOINT="https://komari.sfun.cc"
export AGENT_TOKEN="YOUR_TOKEN"
export AGENT_DISABLE_AUTO_UPDATE=true
./komari-agent
```

### 可选覆盖

```bash
# 完整覆盖 WS 基址（含前缀）
--ws-endpoint "https://ws.komari.sfun.cc/default/komari/komari_ws/v1.0"

# 只改路径前缀（仍自动 ws.{host}）
--ws-path-prefix "/default/komari/komari_ws/v1.0"

# 环境变量
AGENT_WS_ENDPOINT=...
AGENT_WS_PATH_PREFIX=...
```

> 基址请写 **`https://`**，不要写 `wss://`。agent 内部仍用 `http→ws` 转换。

## 与面板侧配套

1. **主域** `komari.sfun.cc`：Cloudflare Snippet（`worker/_snippet.js`）反代 HTTP，并注入：
   - host → `ws.{host}`
   - pathname 前加 `/default/komari/komari_ws/v1.0`
2. **`ws.komari.sfun.cc`**：绑定 Choreo WS 自定义域名  
   路径保留 `/default/komari/komari_ws/v1.0/...`  
   **推荐不要挂 Worker**，避免额度被 WS 重连打爆
3. Cookie：Snippet 仍把 `session_token` 加上 `Domain=.{host}`，终端 WS 可带登录态

## 构建

### 本地

```bash
git clone https://github.com/komari-monitor/komari-agent.git
cd komari-agent
git checkout <upstream-tag>   # 例如 1.2.60
bash /path/to/choreo-komari/agent/apply-choreo-endpoint.sh
bash build_all.sh
# 产物在 ./build/komari-agent-*
```

### GitHub Actions

仓库工作流：`.github/workflows/build-choreo-agent.yml`

- 手动触发或每日拉取上游最新 release
- 打 tag：`v{upstream}-choreo.1`
- 产物命名与上游一致：`komari-agent-{os}-{arch}`

> 若本仓库尚未推到 GitHub，workflow 不会自动跑；本地 `apply + build_all` 即可先用。

## 安装示例

```bash
# 下载你构建的 linux-amd64 二进制后：
install -m 755 komari-agent-linux-amd64 /usr/local/bin/komari-agent

komari-agent \
  -e "https://komari.sfun.cc" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

systemd 可参考上游 install 脚本，把 `ExecStart` 换成上述参数。建议 **`--disable-auto-update`**，避免被官方无前缀版本覆盖。

## 验证

```bash
# 1) HTTP 上报应走主域（Snippet）
curl -sS -o /dev/null -w "%{http_code}\n" \
  -X POST "https://komari.sfun.cc/api/clients/uploadBasicInfo?token=TOKEN" \
  -H "Content-Type: application/json" -d '{}'

# 2) WS 握手应走 ws 子域 + Choreo 前缀
# 期望路径：/default/komari/komari_ws/v1.0/api/clients/v2/rpc
```

Agent 日志中 WebSocket URL 应包含：

```text
wss://ws.komari.sfun.cc/default/komari/komari_ws/v1.0/api/clients/
```

## 注意

- 本 patch **只服务外部 Agent**。镜像内 `localhost:8080` 的内置 agent 继续用官方二进制即可。
- 自动更新默认仍指向上游仓库；生产请加 `--disable-auto-update`，或自行改 `update.Repo` 后发版。
- 面板浏览器实时数据依赖 `worker/_snippet.js` 的 WS 注入；只装 patched agent 不会修前端。
- 完整部署说明见 [README.choreo.md](./README.choreo.md)。
