# Komari Dockerfile for Choreo

# Version

1.4.0

# Releases

# Komari 1.4.0 正式发布

**Komari 1.4.0** 正式发布——这是 Komari 有史以来最具里程碑意义的一次版本更新！**插件系统横空出世**，**管理后台仪表盘焕然一新**，**数据库占用再度降低**。Komari 不再只是一个出色的服务器监控工具，而是一个真正开放、可编程、属于你的监控平台。

**隆重登场：插件系统。** 从这一版本开始，任何人都可以像安装 App 一样，从**官方插件市场**一键安装插件，或用 ZIP 包本地安装。插件可以注册 HTTP 路由、调用系统 RPC、编写定时任务、托管静态页面、拦截 HTTP 与 WebSocket 数据流，甚至向页面注入自定义 HTML。

**全新仪表盘。** 管理后台首页仪表盘正式上线，**Top CPU / 内存 / 延迟排行**尽收眼底；新增 pprof 性能分析视图与可访问性优化，一切尽在掌握。

**数据库再优化。** 读写 IO 大幅优化；磁盘占用显著下降；保留期可配置，存储策略尽在掌握。

---

## 更新日志

### 主要更新内容

- 新增插件系统：支持 ZIP 安装、插件市场源管理、权限审批（HTML 注入、`server` 模块等权限门控）、持久化插件数据目录（`data/plugin-data/`）
- 插件运行时新增 `server` 模块：注册路由、调用系统 RPC、`server.cron` 定时任务、`server.static` 静态文件服务、WebSocket / HTTP 请求响应钩子
- 插件市场默认源设为官方市场；管理后台新增插件页面：市场浏览、更新、卸载，第三方插件加载警告
- 重构并扩展 JavaScript 运行时：内置模块拆分，新增 `node:stream` 与 `crypto` 模块，补充 API 与兼容性文档
- 仪表盘升级：管理后台新增首页仪表盘（Top CPU / 内存 / 延迟排行）；新增 `km-*` class 钩子与 ARIA 可访问性标注
- 再次优化数据库占用：指标存储迁移至 `internal/metricstore` 并拆分组件；指标数据 zstd 压缩；Rollup 保留期可配置；优化指标库读写 IO
- 消息通知支持任意负载字段，新增 `SendNotification` 方法
- 新增 pprof 性能分析视图；OAuth 登录后跳转管理后台首页
- 移除旧版兼容代码及冗余数据库查询函数

### Bug修复

- 修复 Ping 任务排序与顺序更新：按权重和 ID 排序；更新权重时避免误报记录不存在

### 相关文档

- 插件开发指南：https://komari-document.pages.dev/dev/plugin/
- 插件清单（manifest）规范：https://komari-document.pages.dev/dev/plugin/manifest
- 插件运行时与沙箱：https://komari-document.pages.dev/dev/plugin/runtime
- 插件 RPC 调用：https://komari-document.pages.dev/dev/plugin/rpc
- 插件 `server` API：https://komari-document.pages.dev/dev/plugin/server-api
- 插件市场接入：https://komari-document.pages.dev/dev/plugin/market
- 主题开发（`km-*` class 钩子）：https://komari-document.pages.dev/dev/theme
- 插件 SDK：https://www.npmjs.com/package/@komari-monitor/plugin-sdk


### Commits

- style: 移除没有使用的旧版本兼容代码，移动 database/metricstore 到 internal/metricstore 并拆分组件 ([4077201](https://github.com/komari-monitor/komari/commit/4077201f098774511eaf504f220c5f6be009346b)) @Akizon77
- refactor: javascript runtime ([df6ffba](https://github.com/komari-monitor/komari/commit/df6ffba18c3475c44ff6021f020db33b0ad8601f)) @Akizon77
- refactor(jsruntime): modularize built-ins ([3c58382](https://github.com/komari-monitor/komari/commit/3c5838283eaf51c6cf1ae3997fcf1adaa54f17f8)) @Akizon77
- docs(jsruntime): add API and compatibility documentation ([54851bd](https://github.com/komari-monitor/komari/commit/54851bd1cf9fcf651393b8f20e71ded0a46fe1e3)) @Akizon77
- docs(jsruntime): clarify unsupported methods throw instead of no-op ([91ae9ed](https://github.com/komari-monitor/komari/commit/91ae9eda1a84841a39c930588ee297ab5b88dd47)) @Akizon77
- fix(jsruntime): treat process.exit(0) as normal termination and improve error reporting ([91cbeb3](https://github.com/komari-monitor/komari/commit/91cbeb3f829e8044f37083d1105d9c66e0cd7c10)) @Akizon77
- feat: add plugin system and refactor jsruntime deadline handling ([8985adc](https://github.com/komari-monitor/komari/commit/8985adcf672b35a91e2a97c81caee15ca4087e05)) @Akizon77
- feat(plugin): enforce server module permission gates ([68bf4ed](https://github.com/komari-monitor/komari/commit/68bf4ed148e53f8c09745ec94e56ce17cf65cb4c)) @Akizon77
- feat(jsruntime): add node:stream module and embed nexttick JS ([965afb3](https://github.com/komari-monitor/komari/commit/965afb3f77a1c507ca2b011f55ffd5fbbc338410)) @Akizon77
- feat: crypto module support ([91d5f92](https://github.com/komari-monitor/komari/commit/91d5f92c5534c03c41b9ae22da64f7768beaef57)) @Akizon77
- feat(plugin): set official plugin market as default source ([f967ba0](https://github.com/komari-monitor/komari/commit/f967ba07f9edd0b361ec69e92df6c27ef5189a0d)) @Akizon77
- fix(plugin): limit response hook buffering and safely reinstall ([c27c21d](https://github.com/komari-monitor/komari/commit/c27c21d5c99eb3f8cbe00e59be04ddf25b8c2d4b)) @Akizon77
- feat(plugin): add persistent storage dir for plugins ([01c4816](https://github.com/komari-monitor/komari/commit/01c4816d1ca5b5951173d930b7b36e7ac4428895)) @Akizon77
- feat: add plugin data storage and remove preview field ([4040a5d](https://github.com/komari-monitor/komari/commit/4040a5d9c7c512c74a1461f561f07734df70552f)) @Akizon77
- feat: add HTML injection permission and support for plugins ([1f139ba](https://github.com/komari-monitor/komari/commit/1f139ba3bfc1ad98120890a7f5e4d112f17ae18b)) @Akizon77
- feat(plugin): add server.static for serving plugin static folders ([eab03a1](https://github.com/komari-monitor/komari/commit/eab03a1da5a636dfda30fdde1a28424e9d023edc)) @Akizon77
- fix:  hook 过滤 + 按插件 body 上限 ([d9713aa](https://github.com/komari-monitor/komari/commit/d9713aa696da8cfe7a5a1db3f2899b332ad72ddd)) @Akizon77
- feat(plugin): add server.cron scheduled task support ([5488189](https://github.com/komari-monitor/komari/commit/5488189e5f9560876c30f791777ad6b73f6e8854)) @Akizon77
- fix(rpc): make registered methods discoverable via rpc.help ([28abafb](https://github.com/komari-monitor/komari/commit/28abafb5b2f7bf34a39c7178b9b269d5bc59128a)) @Akizon77
- feat: add SendNotification and support any event payload fields ([996dd90](https://github.com/komari-monitor/komari/commit/996dd90386fa581d099301b95f4ac49c2c47bddd)) @Akizon77
- fix(jsruntime/fs): allow no-follow operations on confined root ([956b933](https://github.com/komari-monitor/komari/commit/956b9334d0545d9c3dde71ba70c1499bb9dd3120)) @Akizon77
- fix(notifier): skip load notification when no clients to notify ([a714637](https://github.com/komari-monitor/komari/commit/a714637feeae5386ff90c004a2d6225d12b1260c)) @Akizon77
- pref: metrics db IO Read/Write ([08067bc](https://github.com/komari-monitor/komari/commit/08067bc8f8f3c6e40fdf4c2ba593adfe7ad8a920)) @Akizon77
- feat:metrics zstd compress & fix pingtask order ([cba8153](https://github.com/komari-monitor/komari/commit/cba8153d4a19e3405100bf5cc460dd8014a7f0e3)) @Akizon77
- fix(oauth): redirect to admin dashboard after OAuth login ([d92f60f](https://github.com/komari-monitor/komari/commit/d92f60f7576a20498d690555db094e05a3aeeecd)) @Akizon77
- feat(metricstore): make rollup retention configurable ([9646252](https://github.com/komari-monitor/komari/commit/96462528c8d9ad794a3b885316d53d8e3eaf6eb4)) @Akizon77
- feat(plugin): add WebSocket hook support to server.hook ([e5d6768](https://github.com/komari-monitor/komari/commit/e5d67686dbeadc83f9d3fd640b29b0e5589eb0d2)) @Akizon77

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.3.2...1.4.0