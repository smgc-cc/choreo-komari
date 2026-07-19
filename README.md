# Komari Dockerfile for Choreo

镜像基于 `ghcr.io/komari-monitor/komari:latest`，经 Cloudflare Worker / Snippet 反代后部署在 Choreo。

## 当前上游版本说明

上游 1.2.6 / 1.2.7 是**破坏性升级**：

1. 监控数据从旧表（`records` / `gpu_records` / `ping_records`）迁移到独立 metric store（默认 `./data/metrics.db`）
2. 若库里还有未迁移的历史监控数据，启动时会进入**受限升级向导模式**，只提供登录 + 升级 API，正常 Agent / RPC / WebSocket 全部关闭
3. 该模式下前端 WS 与 Agent 会反复重连，混合部署里 Worker 请求数会爆表

本仓库适配点：

- `/app/data` → `/tmp` 软链（Choreo 只读文件系统）
- `backup.sh` 同时备份 / 恢复 `komari.db` 与 `metrics.db`
- Cloudflare 代理文档见 [readme.worker.md](./readme.worker.md)

## 1.2.7 升级向导（必做）

升级后若出现「连不上、后台登不上、Worker 请求暴涨」，优先按此处理：

1. **先降负**：临时停掉外部 Agent，或暂停 Worker（避免重连打满额度）
2. 浏览器打开站点主域名，应被重定向到 `/admin/update/1.2.7`
3. 用管理员账号登录（升级模式仅保留 `/api/login`、`/api/me`、OAuth 与升级 API）
4. 若历史数据量大 / Choreo 磁盘紧张：先在向导里清理较旧监控数据，再迁移
5. 目标库选 SQLite，DSN 保持默认 `./data/metrics.db`（本镜像下实际写到 `/tmp/metrics.db`）
6. 迁移完成后服务会自动切回正常模式；确认面板、Agent 恢复后再重新启用 Worker / Agent
7. 迁移成功后立刻触发一次备份（确保 `metrics.db` 进 R2）

> Choreo 容器重启会丢 `/tmp`。迁移完成后若没备份 `metrics.db`，历史指标会丢；主库若已写迁移完成标记，服务仍可正常启动，只是监控历史为空。

## Cloudflare 代理

见 [readme.worker.md](./readme.worker.md)。混合模式（Snippet + Worker）或独立 Worker 均可。