# Komari Dockerfile for Choreo

# Version

1.2.6

# Releases

## 主要更新内容

- 新增数据库 vacuum 与存储大小查询 API，支持手动回收 SQLite 及外部数据库空间。
- 监控数据读写全面迁移至 metric store（默认 SQLite `./data/metrics.db`），旧 `records`、`ping_records` 表只作为一次性迁移源，运行期不再使用。
- 支持 MySQL/PostgreSQL 作为 metrics 存储后端，可在设置中动态切换并热重载，切换时自动搬运历史数据。
- 引入指标保留策略管理（默认 90 天）与基于 rollup 的层级压缩，降低存储开销。
- RPC 权限模型重构为基于主客体（Principal）的能力集，取代单一角色字符串，隔离 agent 与 admin 权限。
- 移除内置 Cloudflare Tunnel 与 Cloudflare Access OAuth 支持；移除旧的 `record_enabled` / `record_preserve_time` 配置项（已合并至 metric store 保留天数）。
- 安装脚本（`install-komari.sh`）新增稳定版/快照版发布通道选择与 TUI 交互支持。
- 构建流水线重构：前端构建提取为独立 Job 并缓存产物，CI/CD 工作流适配快照版本发布。

## Bug修复

- 【安全】RPC 边界强制对敏感操作进行双因素认证（2FA）。
- 【安全】阻止路径遍历漏洞：主题名称（DeleteTheme/UpdateTheme/SetTheme）中过滤 `../`。
- 【RPC】修复 `common:getNodes` 返回节点顺序不稳定的问题（改为按原序输出）。
- 【Telegram】非 200 响应时返回 API 错误描述，而非仅 HTTP 状态码。
- 修复 SQLite 数据库锁冲突导致监控记录写入失败的问题。
- 修复 metrics 迁移时表锁问题及恢复迁移时进度计数归零的问题。
- 修复临时分享链接访问私有站点时被错误拦截的问题。

## 其他

- 服务启动生命周期重构为显式阶段（Bootstrap → InitStores → InitProviders → StartBackground → BuildRouter → Run → Shutdown），提升初始化可靠性。
- 热重载管理器统一收敛配置变更分发，隔离 handler panic。
- 移除 `go-oidc`、`go-jose` 等不再使用的依赖。
- 数据库备份：版本升级时自动打包 `./data` 目录到 `./backup/`。
- SQLite WAL 模式优化：启动时执行 checkpoint 保证数据完整性。

## What's Changed
* fix(rpc): 在 RPC 边界强制对敏感操作进行双因素认证（2FA） by @carbofish in https://github.com/komari-monitor/komari/pull/571
* fix: preserve node order in common:getNodes RPC by @yuanhhs in https://github.com/komari-monitor/komari/pull/566
* feat: add database vacuum and size API endpoints by @Akizon77 in https://github.com/komari-monitor/komari/pull/578
* fix(security): prevent path traversal in theme name (DeleteTheme/UpdateTheme/SetTheme) by @guocn in https://github.com/komari-monitor/komari/pull/584
* fix(telegram): 非 200 响应时返回 API 错误描述而非仅状态码 by @Torther in https://github.com/komari-monitor/komari/pull/583

### Commits

- Preserve RPC node order ([144efdc](https://github.com/komari-monitor/komari/commit/144efdc8ad1f416dffdfd44f996efb69f3cbf340)) @yuanhhs
- fix(rpc): enforce sensitive-operation 2FA at the RPC boundary ([50fe286](https://github.com/komari-monitor/komari/commit/50fe2865282a499329f5bbee6e9df394636e37a9)) @carbofish
- Merge PR #571: fix(rpc): enforce sensitive-operation 2FA at the RPC boundary ([50ba831](https://github.com/komari-monitor/komari/commit/50ba8310ca41302a465621775564bd05c4bc6029)) @Akizon77
- Preserve RPC node order (#566) ([dd05393](https://github.com/komari-monitor/komari/commit/dd0539392ba234949872704c415c85ea47b4f867)) @Akizon77
- refactor(rpc): unify identity into Principal model ([036121c](https://github.com/komari-monitor/komari/commit/036121c1483076f874dcb7dbb9bbc97393a51f11)) @Akizon77
- refactor(rpc): migrate ACL to capability-based Principal model ([ce41745](https://github.com/komari-monitor/komari/commit/ce41745edb06e2815dbf93cce460adad2e696bc8)) @Akizon77
- fix(rpc): allow login-page endpoints in private-site mode ([11d3ba8](https://github.com/komari-monitor/komari/commit/11d3ba8236cf594b003938e467daa3ebbc9dff47)) @Akizon77
- feat: add database vacuum and size API endpoints ([074958f](https://github.com/komari-monitor/komari/commit/074958fad7dd6f42100eb9389e00030d36a54ef3)) @Akizon77
- feat(install): add stable/snapshot channel selection for binary install and upgrade ([e740bf2](https://github.com/komari-monitor/komari/commit/e740bf2797fa61b3a5b27a131e0813417561e74e)) @Akizon77
- feat(install): add TUI support with whiptail/dialog and text fallback ([20c865e](https://github.com/komari-monitor/komari/commit/20c865ed20586946d42e7e135679130c54d13443)) @Akizon77
- Merge pull request #578 from komari-monitor/feat/vacuum-database ([0a4cd6b](https://github.com/komari-monitor/komari/commit/0a4cd6bd8c3549cb8484f630432d5a02b58227c5)) @Akizon77
- ci: limit build workflow to PRs and fix snapshot release creation ([9db4daa](https://github.com/komari-monitor/komari/commit/9db4daac1060a1283b439f6974d1facb59673b59)) @Akizon77
- fix: allow temp-share guests to bypass private site block ([7e19909](https://github.com/komari-monitor/komari/commit/7e19909dd692f872d2b504fed667a5b77aa7cb23)) @Akizon77
- Merge branch 'fix/temp-share-private-site' ([5f50d1b](https://github.com/komari-monitor/komari/commit/5f50d1ba0002bdde094366919470a1ea06985f48)) @Akizon77
- feat: route metric reads and writes to dedicated store ([f2c46db](https://github.com/komari-monitor/komari/commit/f2c46dbfb1b47a95614d8e58dccf55976fcce66b)) @Akizon77
- fix(database): use FromTime() for time queries and improve cache cleanup ([f0877d6](https://github.com/komari-monitor/komari/commit/f0877d6d32aae988de8171c8e13050724d84e502)) @Akizon77
- fix(telegram): include API error description in non-200 responses ([da047cf](https://github.com/komari-monitor/komari/commit/da047cf6120d09980da56d1534285ddd7f1d1cba)) @Torther
- refactor(metrics): route all storage through metric store when enabled ([6a5f3ef](https://github.com/komari-monitor/komari/commit/6a5f3ef04d6bca16b10f17ea2d549170d0549883)) @Akizon77
- fix(rpc): common:getNodes returns uuid-keyed map instead of array ([ff6daa6](https://github.com/komari-monitor/komari/commit/ff6daa6ce32dee5ee3fd87b6567714cff1a14d03)) @Akizon77
- Merge branch 'refactor/metrics-unify-storage': unify storage through metric store + getNodes map ([0132d1c](https://github.com/komari-monitor/komari/commit/0132d1cbd8cdd5f1780847ed28b2a97c7e34cdc7)) @Akizon77
- fix(theme): prevent path traversal in theme operations ([404d97d](https://github.com/komari-monitor/komari/commit/404d97d8468b6cdbc4ccd778a0ee60c33c6af7db)) @guocn
- fix(theme): prevent path traversal in theme operations (#584) ([92ec774](https://github.com/komari-monitor/komari/commit/92ec774249e31728980109d48b78f07d9789c0f5)) @Akizon77
- Merge pull request #583 from Torther/main ([b6fcdd3](https://github.com/komari-monitor/komari/commit/b6fcdd396df8da1e15a739170e83afc6d6aad8a8)) @Akizon77
- fix: avoid sqlite database is locked failures for record writes ([332053d](https://github.com/komari-monitor/komari/commit/332053d8ec123147c79ee028007edc6c1d81727b)) @Akizon77
- feat(metrics): hot-reload metrics DB config with connection test before save ([9e5b6df](https://github.com/komari-monitor/komari/commit/9e5b6df196c6431b741ad576ef86714360258156)) @Akizon77
- fix: avoid sqlite table locks during metric migration ([64998b5](https://github.com/komari-monitor/komari/commit/64998b527caa075be02194aca4a9828bd6b9e38d)) @Akizon77
- feat(metrics): infer DB driver from DSN automatically ([d02d934](https://github.com/komari-monitor/komari/commit/d02d9347dc6682b65f45ca3bfe78b16aa5bd9561)) @Akizon77
- merge: metrics DSN autodetect ([be6af33](https://github.com/komari-monitor/komari/commit/be6af33d85079394161b4101614004c5b8003d27)) @Akizon77
- perf: 优化 metrics 迁移性能 - 批量写入 + keyset 分页 ([5c2bd4e](https://github.com/komari-monitor/komari/commit/5c2bd4ec744d013034f15851b83a7eb67bcea345)) @Akizon77
- feat(metrics): 支持迁移暂停/恢复，进度持久化与重启后孤儿状态修复 ([416ea87](https://github.com/komari-monitor/komari/commit/416ea871be25e370675ee0b3048adfe4e4accd7b)) @Akizon77
- fix(migration): 恢复迁移时保留已迁移进度计数，避免从0重新累计 ([43c80d2](https://github.com/komari-monitor/komari/commit/43c80d238b2e0925c948ede7628a45c409988df3)) @Akizon77
- ci: align snapshot workflow behavior ([eb4ca83](https://github.com/komari-monitor/komari/commit/eb4ca83a131b51514c494a8848816278aef92522)) @airium
- refactor: split startup into app lifecycle stages ([6ddb143](https://github.com/komari-monitor/komari/commit/6ddb143365c8d72d47ec794eb8923e8e8a1a19fe)) @Akizon77
- feat(metrics): always enable metric store with startup migration and version-based backup ([4ad190a](https://github.com/komari-monitor/komari/commit/4ad190a7f4d12a4a43a0951dc887feb373229dd3)) @Akizon77
- refactor: remove built-in Cloudflare tunnel support ([73071ff](https://github.com/komari-monitor/komari/commit/73071ff1e8a5ff167767e245ed8a51774467aa87)) @Akizon77
- refactor(oauth): remove Cloudflare Access provider support ([ab31fc6](https://github.com/komari-monitor/komari/commit/ab31fc69fe429d3bac21c53713dfc594570330af)) @Akizon77
- Use UTC+8 for snapshot versions ([e009444](https://github.com/komari-monitor/komari/commit/e0094447a65fc94ec5aa41dbd02d48e69029dac1)) @Akizon77
- fix: run metric store migrations before startup migration ([84130df](https://github.com/komari-monitor/komari/commit/84130dfff5bb253189956d197c17b0e7d8da7181)) @Akizon77
- refactor(metrics): use metric retention for cleanup settings ([7e0d542](https://github.com/komari-monitor/komari/commit/7e0d542694e79e7adb250bddb8c6bccea16b253a)) @Akizon77
- feat: add metric retention policy management ([7d95240](https://github.com/komari-monitor/komari/commit/7d95240bc1824b7a470edc68bb84ec748a5bb2a8)) @Akizon77
- fix(metric): preserve series identity during aggregation ([8911c08](https://github.com/komari-monitor/komari/commit/8911c08a5b7afa9348417374843ce19c478a5946)) @Akizon77
- feat(metricstore): add scheduled rollup compaction ([5ad791f](https://github.com/komari-monitor/komari/commit/5ad791fe50573b62feae06e03f4f802cacd0d837)) @Akizon77
- fix(metricstore): rotate compaction cursor per metric ([46b4e37](https://github.com/komari-monitor/komari/commit/46b4e37178d71c137056911c8d8fb35f6821a8f5)) @Akizon77
- ci: reuse frontend and toolchain actions in workflows ([8a529b4](https://github.com/komari-monitor/komari/commit/8a529b4eb04e5b961fc0a2ecab7916c0da1f4673)) @Akizon77
- feat(metricstore): aggregate record queries via series rollups ([b2fe9ab](https://github.com/komari-monitor/komari/commit/b2fe9ab0687f17f90005767127224133121c43a8)) @Akizon77
- ci: generate AI-assisted release notes from stable tags ([8910c2e](https://github.com/komari-monitor/komari/commit/8910c2e9c77bb75c11fc35ed8e3a05c1ed48391c)) @Akizon77
- feat(metricstore): track ping packet loss in metrics ([855ff82](https://github.com/komari-monitor/komari/commit/855ff82f974ab0d404c2dff4f7608708b4bffaf5)) @Akizon77
- Improve release notes generation ([5ade710](https://github.com/komari-monitor/komari/commit/5ade710f328e7a82062fc84d6dc4973260606c6a)) @Akizon77
- Read release note workflow inputs ([0660ee7](https://github.com/komari-monitor/komari/commit/0660ee74d466840578092d3fff54eb244d83ef51)) @Akizon77
- Use stable release base for snapshot notes ([29eecf5](https://github.com/komari-monitor/komari/commit/29eecf55f7c63e909910a376eaee6aaa86363fe9)) @Akizon77
- feat(metric): preserve series identity in rollup queries ([9831df0](https://github.com/komari-monitor/komari/commit/9831df0af8ffff2e9b876cf15052383bc8c568f8)) @Akizon77
- Include commits in release notes ([39c5f7b](https://github.com/komari-monitor/komari/commit/39c5f7bb69851b3d9336937091df916bb339b2aa)) @Akizon77
- feat(metricstore): add downsampling toggle, raise default retention to 90d, and cleanup expired data on compact ([42ef993](https://github.com/komari-monitor/komari/commit/42ef993cd65e24c7da119a190066503de956be74)) @Akizon77
- fix(metrics): select compatible rollup intervals ([3b48339](https://github.com/komari-monitor/komari/commit/3b48339209a6697166a7e9c145415a8aad82f90b)) @Akizon77
- Fix metric rollup compaction and retention ([ff358ed](https://github.com/komari-monitor/komari/commit/ff358edd8bca5f9f544ad9d695c9977ecd9f2041)) @Akizon77
- refactor: improve metric store lifecycle management with context-aware close and operation gate ([c828653](https://github.com/komari-monitor/komari/commit/c828653d200786e165f9e678533a925e0cc60325)) @Akizon77

## New Contributors
* @carbofish made their first contribution in https://github.com/komari-monitor/komari/pull/571
* @yuanhhs made their first contribution in https://github.com/komari-monitor/komari/pull/566
* @guocn made their first contribution in https://github.com/komari-monitor/komari/pull/584
* @Torther made their first contribution in https://github.com/komari-monitor/komari/pull/583

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.5...1.2.6