# Komari - Choreo 部署版本

这是 Komari 监控面板的 Choreo 平台适配版本。目标是在 Choreo 的限制下尽量少改上游：

- 从上游 Komari 与 komari-web 最新 tag 构建 Server 与前端
- 容器内同时构建并运行一个可选的 `komari-agent`
- 运行时可写数据全部放到 `/tmp`
- 通过 R2/S3 或 WebDAV 定时备份 `/tmp` 数据
- REST 与 WebSocket 拆分到不同端口，符合 Choreo endpoint 限制
- Cloudflare Worker 处理 Choreo Public URL 路径前缀与 WebSocket 路由

## 主要特性

- 支持 Choreo 只读文件系统：`/app/data -> /tmp`
- SQLite 数据库固定为 `/tmp/komari.db`
- 支持 R2/S3 或 WebDAV 备份后端
- 容器启动时自动恢复最新备份
- 每 2 小时自动备份，默认保留 7 天
- 备份 SQLite 数据库与 `theme/` 目录
- Komari HTTP endpoint 与 WebSocket endpoint 分端口暴露
- Caddy 将 Choreo WS endpoint 反向代理到 Komari 主服务
- 可选启动内置 `komari-agent`，直接连接本机 `localhost:8080`

## 当前架构

```text
浏览器 HTTP
  -> Cloudflare Worker
  -> Choreo REST endpoint :8080
  -> Komari Server

浏览器 / Agent WebSocket
  -> Cloudflare Worker
  -> Choreo WS endpoint :8081
  -> Caddy
  -> Komari Server :8080

内置 Agent（可选）
  -> /app/komari-agent
  -> http://localhost:8080
```

Choreo endpoint 配置见 `.choreo/component.yaml`：

```yaml
endpoints:
  - name: komari
    port: 8080
    type: REST
    networkVisibilities:
      - Public

  - name: komari_ws
    port: 8081
    type: WS
    networkVisibilities:
      - Public
```

> Choreo Public URL 会带 `/default/.../v1.0` 这类路径前缀。Komari 前端与 API 更适合从根路径访问，因此推荐使用 Cloudflare Worker 绑定自定义域名做路径转发。

## 文件结构

```text
choreo-komari/
├── Dockerfile                       # Choreo 专用 Dockerfile
├── README.md                        # 上游版本更新记录
├── README.choreo.md                 # 本文档
├── .choreo/
│   └── component.yaml               # Choreo endpoint 配置
├── patch/
│   └── apply-komari-readwait-env.sh # Agent WebSocket read wait 环境变量补丁脚本
├── script/
│   ├── backup.sh                    # R2/WebDAV 备份与恢复
│   ├── entrypoint.sh                # 容器启动脚本
│   ├── crontab                      # 定时备份任务
│   └── Caddyfile                    # WS 代理配置
└── worker/
    └── cloudflare-worker.js         # Cloudflare Worker 代理脚本
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
|---|---:|---|---|
| `komari` | `8080` | `REST` | Komari 页面和 HTTP API |
| `komari_ws` | `8081` | `WS` | Agent 上报、终端等 WebSocket 请求 |

### 3. 配置环境变量

最小推荐配置：

```bash
KOMARI_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
KOMARI_AGENT_UUID=11111111-1111-1111-1111-111111111111
KOMARI_AGENT_NAME=Choreo Komari
```

`KOMARI_SECRET` 为空时，容器不会启动内置 `komari-agent`。

如果使用 R2：

```bash
BACKUP_BACKEND=r2
R2_ACCESS_KEY_ID=your_r2_access_key_id
R2_SECRET_ACCESS_KEY=your_r2_secret_access_key
R2_ENDPOINT_URL=https://your-account-id.r2.cloudflarestorage.com
R2_BUCKET_NAME=komari-backup
```

如果使用 WebDAV：

```bash
BACKUP_BACKEND=webdav
WEBDAV_URL=https://dav.example.com/remote.php/dav/files/your-user/komari/backups
WEBDAV_USERNAME=your-user
WEBDAV_PASSWORD=your-app-password
```

### 4. 部署

1. 在 Choreo 点击 **Build Latest**
2. 构建成功后部署到 Development 或 Production 环境
3. 记录 Choreo 生成的 Public URL，例如：

```text
https://xxxx-dev.e1-us-east-azure.choreoapis.dev/default/komari/v1.0
```

### 5. 部署 Cloudflare Worker

Choreo Public URL 会强制带路径前缀，例如 `/default/komari/v1.0`。使用仓库里的 `worker/cloudflare-worker.js`，修改顶部配置：

```js
const CHOREO_ORIGIN = "xxxx-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";
```

然后在 Cloudflare Worker 绑定自定义域名，例如：

```text
https://komari.example.com
```

浏览器访问和外部 Agent 都建议使用这个自定义域名。

## 环境变量说明

### choreo-komari 封装变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `KOMARI_SECRET` | 空 | 内置 Agent token；为空时跳过内置 Agent |
| `KOMARI_AGENT_UUID` | 自动生成 | 初始化数据库为空时注入的内置 Agent UUID，建议固定 |
| `KOMARI_AGENT_NAME` | `Local Agent` | 初始化数据库为空时注入的内置 Agent 名称 |
| `BACKUP_BACKEND` | `r2` | 备份后端：`r2`、`webdav`、`none` |

推荐固定：

```bash
KOMARI_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
KOMARI_AGENT_UUID=11111111-1111-1111-1111-111111111111
KOMARI_AGENT_NAME=Choreo Komari
```

如果不固定 `KOMARI_AGENT_UUID`，当 `/tmp` 丢失且没有恢复到旧数据库时，内置 Agent 可能会以新机器身份注册。

### Komari 运行变量

Dockerfile 已设置：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `TZ` | `Asia/Shanghai` | 容器时区 |
| `GIN_MODE` | `release` | Gin 运行模式 |
| `KOMARI_DB_TYPE` | `sqlite` | 数据库类型 |
| `KOMARI_DB_FILE` | `/tmp/komari.db` | SQLite 数据库路径 |
| `KOMARI_LISTEN` | `0.0.0.0:8080` | Komari HTTP 监听地址 |
| `KOMARI_AGENT_READ_WAIT` | `60s` | Agent WebSocket 在线判定 read wait，可覆盖 |
| `KOMARI_WS_DISABLE_ORIGIN` | `true` | 禁用 WebSocket Origin 检查，适配 Worker 代理 |

`KOMARI_AGENT_READ_WAIT` 支持类似 `60s`、`120s` 的 duration，也可设置为纯数字秒，具体由补丁逻辑处理。Choreo/Cloudflare 链路下建议保持在 `60s` 或更高，避免 Agent 上报间隔抖动时被过早判定离线。

## 备份与恢复

备份脚本：

```text
/app/backup.sh
```

定时任务：

```cron
0 */2 * * * /app/backup.sh backup >> /tmp/backup.log 2>&1
```

容器启动时会先执行：

```bash
/app/backup.sh restore
```

### 备份内容

```text
/tmp/komari.db
/tmp/theme/
```

SQLite 使用 `VACUUM INTO` 做在线备份。

### R2 模式

```bash
BACKUP_BACKEND=r2
R2_ACCESS_KEY_ID=xxx
R2_SECRET_ACCESS_KEY=xxx
R2_ENDPOINT_URL=https://xxx.r2.cloudflarestorage.com
R2_BUCKET_NAME=komari-backup
```

备份路径：

```text
s3://$R2_BUCKET_NAME/backups/komari_backup_YYYYMMDD_HHMMSS.tar.gz
```

### WebDAV 模式

```bash
BACKUP_BACKEND=webdav
WEBDAV_URL=https://dav.example.com/remote.php/dav/files/your-user/komari/backups
WEBDAV_USERNAME=your-user
WEBDAV_PASSWORD=your-app-password
```

也支持别名：

```bash
WEBDAV_USER=your-user
WEBDAV_PASS=your-app-password
```

备份路径：

```text
$WEBDAV_URL/komari_backup_YYYYMMDD_HHMMSS.tar.gz
```

`WEBDAV_URL` 应该直接指向存放备份文件的目录。脚本会尝试 `MKCOL`，目录已存在时不会中断。

### 禁用备份

```bash
BACKUP_BACKEND=none
```

也支持：

```bash
BACKUP_BACKEND=off
BACKUP_BACKEND=disabled
```

### 手动备份/恢复

进入容器后执行：

```bash
/app/backup.sh backup
/app/backup.sh restore
```

查看日志：

```bash
cat /tmp/backup.log
```

## 内置 Agent

`Dockerfile` 会从 `https://github.com/komari-monitor/komari-agent.git` 拉取最新 tag，构建上游 `komari-agent`，并注入版本号：

```dockerfile
-X github.com/komari-monitor/komari-agent/update.CurrentVersion=${VERSION}
```

启用内置 Agent：

```bash
KOMARI_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
KOMARI_AGENT_UUID=11111111-1111-1111-1111-111111111111
KOMARI_AGENT_NAME=Choreo Komari
```

启动流程：

1. `/app/entrypoint.sh` 恢复备份
2. 后台等待 Komari Server 在 `localhost:8080` 就绪
3. 如果 `/tmp/komari.db` 的 `clients` 表为空，注入一条内置 Agent 记录
4. 启动：

```bash
/app/komari-agent -e http://localhost:8080 -t "$KOMARI_SECRET" --disable-auto-update
```

注意：

- 内置 Agent 不走 Worker、不走 Choreo Public URL
- `KOMARI_SECRET` 为空时不会启动内置 Agent
- `KOMARI_AGENT_UUID` 建议固定，避免数据库丢失后重复注册
- 如果恢复出的数据库已有 `clients` 数据，entrypoint 不会再次注入内置 Agent

## 运行时数据路径

```text
/app/data -> /tmp

/tmp/
├── komari.db
├── theme/
└── backup.log
```

Choreo 容器重启或重新部署时 `/tmp` 可能丢失，因此建议启用 R2/WebDAV 恢复。

## 故障排查

### 页面 404

通常是 Choreo 路径前缀问题。确认 Cloudflare Worker 中：

```js
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
```

与 Choreo REST Public URL 的路径一致。

### WebSocket 连接失败

确认：

```js
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";
```

并确认 `.choreo/component.yaml` 中 `komari_ws` endpoint 是：

```yaml
type: WS
port: 8081
```

### 管理终端 WebSocket 失败

Worker 会把：

```text
/api/admin/client/{uuid}/terminal
```

改写为：

```text
/api/clients/admin-terminal/{uuid}
```

Caddy 再改写回原始路径后代理到 `localhost:8080`。如果终端不可用，检查：

- `worker/cloudflare-worker.js` 是否部署为最新版本
- `script/Caddyfile` 是否被 Dockerfile 复制到 `/app/Caddyfile`
- Choreo `komari_ws` endpoint 是否为 Public WS

### 内置 Agent 没出现

检查环境变量：

```bash
KOMARI_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
KOMARI_AGENT_UUID=11111111-1111-1111-1111-111111111111
```

检查日志中是否有：

```text
Starting komari-agent setup process...
Komari Server is ready. Checking database...
Starting komari-agent...
```

如果数据库中已有 `clients` 数据，entrypoint 会跳过注入。

### 备份未执行

检查：

```bash
cat /tmp/backup.log
```

R2 模式检查：

```bash
echo $BACKUP_BACKEND
echo $R2_ENDPOINT_URL
echo $R2_BUCKET_NAME
```

WebDAV 模式检查：

```bash
echo $BACKUP_BACKEND
echo $WEBDAV_URL
echo $WEBDAV_USERNAME
```

### 恢复后没有旧数据

确认备份后端中存在文件名类似：

```text
komari_backup_YYYYMMDD_HHMMSS.tar.gz
```

并确认压缩包内结构包含：

```text
./data/komari.db
./data/theme/
```

## 限制与注意事项

- `/tmp` 非持久化，最多可能丢失两次备份之间的数据
- WebDAV 上传速度与稳定性取决于服务端实现
- Choreo REST 与 WS endpoint 需要分开配置
- 建议通过 Cloudflare Worker 自定义域名访问，不建议直接访问带路径前缀的 Choreo URL
- 建议固定 `KOMARI_SECRET` 与 `KOMARI_AGENT_UUID`
- 如果备份恢复了已有数据库，`KOMARI_SECRET` 不会自动覆盖数据库中已有 Agent token

## 相关文档

- `.choreo/component.yaml`：Choreo endpoint 配置
- `worker/cloudflare-worker.js`：Cloudflare Worker 代理脚本
- `script/backup.sh`：R2/WebDAV 备份脚本
- `script/entrypoint.sh`：容器启动脚本
- `script/Caddyfile`：WebSocket 代理与路径改写配置
