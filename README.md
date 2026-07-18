# Komari Dockerfile for Choreo

# Version

1.2.7

# Releases

## 主要更新内容

- 新增公开访客审计事件 RPC 端点 (`public:recordVisitorEvent`)，支持主题记录访客操作并写入审计日志（需管理员启用 `visitor_audit_enabled`）
- 移除 Nezha 兼容层及相关配置选项
- 移除自定义 `LocalTime` 类型，全部模型时间字段统一使用 `time.Time` 并采用 UTC 时区
- Metric 存储重构：保留策略由指标定义控制（`RetentionDays=0` 禁用持久化并清除已有数据），移除全局默认保留天数；默认关闭降采样；添加 compaction 水位线表确保滚动压缩边界正确
- 添加 metric 报告批处理写入器，批量报告在单个事务中持久化，提升吞吐
- 数据库连接参数（`--db-host`、`--db-port` 等）和对应环境变量已移除，仅保留 `--db-type`/`--database`
- Dockerfile 移除冗余数据库环境变量默认值
- 支持 Linux loong64 架构（龙芯）
- Cockpit/gap 自适应显示；移除废弃的 `FillEmpty` 聚合选项

## Bug修复

- 修复删除客户端或 Ping 任务时未清理独立 metric 存储的问题
- 修复 visitor audit 日志写入的加固处理（限流、字段校验）
- 修复 `zero-retention` 指标定义在 upsert 时未正确保留并删除历史数据
- 修复 cron 调度器基于本地时区而非系统时区运行的问题
- 修复 metric 存储迁移时零保留指标跳过数据迁移
- 修复内置指标默认保留天数过长的测试问题

## 其他

- CI/CD：添加 loong64 构建矩阵；移除 release notes 的 web 发布触发和定时调度
- 升级 gorm 配置使用 `NowFunc` 返回 UTC 时间
- 移除大量未使用的数据库辅助函数和配置文件

## What's Changed
* feat(rpc): add public visitor audit event endpoint by @sanrokamlan-prog in https://github.com/komari-monitor/komari/pull/597
* fix: harden visitor audit logging by @sanrokamlan-prog in https://github.com/komari-monitor/komari/pull/602

### Commits

- disable downsampling by default ([724dd3b](https://github.com/komari-monitor/komari/commit/724dd3b666b236d16dfac876e5bec31b90245c6c)) @Akizon77
- feat: add visitor audit rpc endpoint ([7679430](https://github.com/komari-monitor/komari/commit/76794305c86fadd7e16936cbeb513dc89ce59b2f)) @sanrokamlan-prog
- Update generate-release-notes.yml ([5c73eba](https://github.com/komari-monitor/komari/commit/5c73eba475a5d83164aacd7b5b1a71b8f20858fd)) @Akizon77
- Merge pull request #597 from sanrokamlan-prog/visitor-audit-rpc ([1eb3549](https://github.com/komari-monitor/komari/commit/1eb3549ed9deedd061dcb5d652790605ec5375bf)) @Akizon77
- fix: harden visitor audit logging ([0c80f0f](https://github.com/komari-monitor/komari/commit/0c80f0f23a986edb08f0f44e075dec12427dec44)) @sanrokamlan-prog
- Merge pull request #602 from sanrokamlan-prog/fix/visitor-audit-hardening ([5fa59ab](https://github.com/komari-monitor/komari/commit/5fa59ab7de430e95c3f9b3773e40ecfd376fe425)) @Akizon77
- refactor: replace static retention config with dynamic retention summary ([7f36881](https://github.com/komari-monitor/komari/commit/7f368817e069f4adcf0c2e2010d32afd68ea76f9)) @Akizon77
- fix: preserve zero-retention metric definitions across operations ([66b7691](https://github.com/komari-monitor/komari/commit/66b7691e016168b9588eb63e6fb7b7a5903e154f)) @Akizon77
- refactor(metrics): remove DefaultRetentionDays config option and enforce explicit retention ([7baf2ed](https://github.com/komari-monitor/komari/commit/7baf2edf26764809312a46a7b7367917ff5ea833)) @Akizon77
- fix: reduce default built-in metric retention to 1 day for testing ([c1178eb](https://github.com/komari-monitor/komari/commit/c1178ebfe1e7f7ff7526a3dba4df6eed95ccc0bd)) @Akizon77
- fix(metricstore): use Series to read ping records for rollup support ([e2a8284](https://github.com/komari-monitor/komari/commit/e2a8284c0335aeb4e2940623e655be8e4caf0138)) @Akizon77
- feat: clean metric store before deleting client or ping task ([43547b9](https://github.com/komari-monitor/komari/commit/43547b947ff82b4b899452ead7ba7b1517ba1f84)) @Akizon77
- feat(metric): add compaction watermark upsert and update storage queries ([5b90804](https://github.com/komari-monitor/komari/commit/5b90804a1300cc24eae11efbe5618ba5de9a2e35)) @Akizon77
- feat: #414 add support for loong64 architecture ([fc3febc](https://github.com/komari-monitor/komari/commit/fc3febc3bec33fb5b908c76323d906a4e14b433d)) @Akizon77
- refactor: remove unused database functions for sessions, clients, and metric store ([0f6f2f4](https://github.com/komari-monitor/komari/commit/0f6f2f42944d04bcb425bfe99ebeb7478213d5ac)) @Akizon77
- refactor: remove Nezha compatibility ([f42cfe7](https://github.com/komari-monitor/komari/commit/f42cfe7ddc210685c5430c8062f6dd41b64503bf)) @Akizon77
- Make metric chart gaps adaptive ([73c3c43](https://github.com/komari-monitor/komari/commit/73c3c436a4e86f1a20ceb881ac4be7fc8c28d035)) @Akizon77
- refactor: remove deprecated WriteRecord/WriteGPURecord and refactor cron jobs ([312e320](https://github.com/komari-monitor/komari/commit/312e320c8fe0202abd1a15de0ab0beccd6480063)) @Akizon77
- feat(metricstore): batch metric report writes in single transactions ([a78ef87](https://github.com/komari-monitor/komari/commit/a78ef878eb8d75ea1d769128d5f975cded84edf1)) @Akizon77
- refactor(jsonrpc): remove deprecated Tag field from public metric types ([d853a83](https://github.com/komari-monitor/komari/commit/d853a83ec60070dfb5225ccbf8a7da7e48f25311)) @Akizon77
- feat: add legacy upgrade server and refactor OAuth initialization ([3c27823](https://github.com/komari-monitor/komari/commit/3c278230f4e5389cfae4ad94337830df0a41c129)) @Akizon77
- feat(admin): add database compression inspection and configuration endpoints ([fee8c86](https://github.com/komari-monitor/komari/commit/fee8c860d795b9c0a8c027812c4faab26b716ba5)) @Akizon77
- Revert "feat(admin): add database compression inspection and configuration endpoints" ([7f12850](https://github.com/komari-monitor/komari/commit/7f128509e91e9320251a2af2fa4f487bd23b229a)) @Akizon77
- refactor: clean up metric constants and refactor record downsampling ([99fda6b](https://github.com/komari-monitor/komari/commit/99fda6b023c696c1def0519870370900c89ebfa6)) @Akizon77
- refactor: standardize time fields ([42b290f](https://github.com/komari-monitor/komari/commit/42b290f16959cb54d2718e5a035e8a0b81f751cb)) @Akizon77
- remove unused database connection parameters ([be3daa4](https://github.com/komari-monitor/komari/commit/be3daa42fc82b9239c7026957fcbc400e3f03f82)) @Akizon77

## New Contributors
* @sanrokamlan-prog made their first contribution in https://github.com/komari-monitor/komari/pull/597

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.6...1.2.7