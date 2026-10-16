# Komari Dockerfile for Choreo

# Version

1.6.0-fix1

# Releases

## 重大更改 BREAKING CHANGES
- 移除剪贴板功能，`/admin/clipboard` 路由及对应 RPC 不再可用。
- 移除 xterm.js 全局终端设置，`/admin/settings/xtermjs` 路由及 `admin:getXtermjsSettings`、`admin:setXtermjsSettings` 不再可用。
- 移除负载告警规则，`/admin/notification/load` 路由及对应 RPC 不再可用。
- 通知配置改为插件式通知渠道。旧消息发送器配置接口（`/admin/settings/message-sender`、`admin:getMessageSenderProvider`、`admin:setMessageSenderProvider`）以及内置 Bark、Email、JavaScript、Server酱³、Server酱 Turbo、Telegram 渠道已移除；Webhook 渠道保留。请安装并启用所需的通知渠道插件，通过 `/admin/notification/channels` 和 `/admin/notification/channel/configuration` 重新配置。
- 移除访客审计 RPC `public:recordVisitorEvent`。


## 主要更新内容

- **通知系统全面重写**：移除旧的 `messageSender` 工厂模式（bark、email、Server酱³、Server酱Turbo、Telegram 等内置通道），替换为统一的 `NotificationChannel` 注册表。内置通道保留 Webhook 和 JavaScript，新增插件可通过 `server.registerNotificationChannel()` 注册自定义通知通道。JavaScript 通道现支持 `sendEvent(event)` 函数（回退到 `sendMessage`）。
- **Agent 协议 v2 扩展**：新增 `agent.startupConfig` / `agent.startupConfig.result` 方法，管理员可在线获取 Agent 完整启动参数（含凭据）；新增 `agent.switchVersion` 方法，支持远程请求 Agent 切换版本。对应新增 `admin:getAgentStartupConfig` 和 `admin:switchAgentVersion` RPC 接口。
- **WebSocket 压缩与心跳**：所有 WebSocket 连接（终端、客户端 v2、公共推送）现与浏览器协商压缩算法；v2 客户端连接引入 75 秒读超时 + Ping/Pong 心跳机制，替代原先 11 秒的固定读等待。
- **JS 运行时增强**：`URL` 和 `URLSearchParams` 注入为全局变量；新增 `tls` 模块（`tls.connect` / `tls.createConnection`），支持 STARTTLS 升级；`net` 模块新增 `AttachSocket` / `DetachSocket` 以配合 TLS 握手。
- **前端静态资源改为磁盘缓存**：启动时将内嵌 dist 解压至 `./cache/dist` 目录，不再全量驻留内存。

## Bug修复

- 修复流量上报重试时可能将历史累计值误计为增量流量的问题（引入 `maxTrafficReportGap` 15 分钟上限及写锁串行化基线读写）。
- 优化长时间断报的识别逻辑，减少误判。

## 其他

- 移除剪贴板功能（数据库表、API 路由、RPC 方法全部删除）。
- 移除负载通知（LoadNotification）功能及相关定时任务。
- 移除未落地的访客审计（Visitor Audit）配置项。
- 移除 xtermjs 独立设置接口。
- Linux 构建添加 `-extldflags=-Wl,--strip-all` 减小二进制体积；zstd 编码器降低并发与内存占用；上报批处理队列从 4096 缩减至 512。
- Docker 及 systemd 服务新增 `GODEBUG=disablethp=1` 环境变量。
- 新增 `admin:getLastRunVersion` 接口，返回本次启动前记录的版本号。
- `/admin` 路径现 302 重定向至 `/admin/dashboard`。

### Commits

- 重定向旧版本的主题接口？ ([4ec22ed](https://github.com/komari-monitor/komari/commit/4ec22edf1f7de4374356c8b886ec73a25b619e17)) @Akizon77
- 重写1下通知 ([d15f051](https://github.com/komari-monitor/komari/commit/d15f0512c753c7dd62ce9b873a7661726ccabe4d)) @Akizon77
- 裁剪1下 ([f57461f](https://github.com/komari-monitor/komari/commit/f57461f87f6d14d09df89f927c30ad8e676a5c4e)) @Akizon77
- 优化内存的分配喵，再压1点！ ([7e91794](https://github.com/komari-monitor/komari/commit/7e91794f246869991d566a9f75a777e4322c1664)) @Akizon77
- 1点点小参数优化内存 ([2c3f228](https://github.com/komari-monitor/komari/commit/2c3f2281fad28299f01d91c6fb9ecdcd43976522)) @Akizon77
- 添加1个小参数优化内存 ([154d2b8](https://github.com/komari-monitor/komari/commit/154d2b8af2bc177ad313194b794861c38ada52ce)) @Akizon77
- 没有落地的访客审计功能先删掉吧 ([14bc87d](https://github.com/komari-monitor/komari/commit/14bc87d1e9ca39205102b5f8bdea8c86bcc6ab9c)) @Akizon77
- xterm设置适用面有1点太少了 ([68c284d](https://github.com/komari-monitor/komari/commit/68c284d043de436ce2da70674d67a92b79fa209c)) @Akizon77
- 剪切板也是1个用的比较少的功能，移除了喵 ([7d692d2](https://github.com/komari-monitor/komari/commit/7d692d2faf276a7c12520faaa8c41c38584bb484)) @Akizon77
- 支持拿到Agent的运行参数了 ([29d309f](https://github.com/komari-monitor/komari/commit/29d309f4a11af20e11463b9a8d512ad077a7baec)) @Akizon77
- 对于#675，有一个更简洁的方案可以试1下 ([70df320](https://github.com/komari-monitor/komari/commit/70df32096f5dcd3247c6ca6463b829f52b402c1c)) @Akizon77
- Agent支持切换版本协议 ([9812acf](https://github.com/komari-monitor/komari/commit/9812acfd1106f29fa2f6d193207b005396bc78e0)) @Akizon77
- 识别长时间断报优化一下 ([39cb3f5](https://github.com/komari-monitor/komari/commit/39cb3f59b2837e8d052203bfbbf3187888e5fa4c)) @Akizon77
- js通知先加回来 ([a68704a](https://github.com/komari-monitor/komari/commit/a68704a42560b5297343a4f99d0143c34add3de5)) @Akizon77
- 加1个通知升级提醒 ([e48aa1e](https://github.com/komari-monitor/komari/commit/e48aa1e76931132fb5dc93ce53763dd59df83d9f)) @Akizon77
- 和浏览器1起协商ws压缩算法 ([13cbdca](https://github.com/komari-monitor/komari/commit/13cbdca545e3427f720cfe55a0db787048a0a3be)) @Akizon77
- js通知沿用旧版本的逻辑 ([1b76b7a](https://github.com/komari-monitor/komari/commit/1b76b7ad5bc3de6529bb7f0577069b4ac241fec3)) @Akizon77

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.5.1...1.6.0