# Komari Dockerfile for Choreo

# Version

1.3.0

# Releases

## 主要更新内容

- 新增首次安装向导：通过 Web 页面创建管理员账号、配置站点信息与监控数据库，并支持在首次安装阶段恢复备份。
- 全面升级 Metric Store：
  - 首次启动自动识别低资源环境，并应用更适合 SQLite 的配置。
  - 指标写入、Ping 记录批处理、非百分位查询和维护任务均有性能优化。
  - 指标库连接失败时进入数据库恢复模式，可在保留登录能力的情况下修正监控数据库配置。
  - 切换监控数据库后的历史数据迁移改为由管理员手动发起，可查看进度或取消。
- 新增主题市场源管理与主题包校验。
- 改进磁盘写入测速，使用对齐的无缓冲 I/O，结果更贴近实际磁盘性能。
- 重构服务启动生命周期、日志系统与定时任务结构，提升启动、维护和故障诊断的可靠性。

## Bug 修复

- 修复指标清理中孤立数据未被移除的问题，并拒绝未知指标。
- 修复单个指标压缩失败时中断后续压缩的问题，并为压缩操作增加独立并发保护。(`#609`、`#612`)
- 修复内存总量读取可能溢出的问题。
- 修复事件时间以 UTC 显示而非本地时区的问题。
- 修复维护版本 Docker 镜像可能使用不匹配前端，以及 `latest` 标签提升逻辑不准确的问题。

## 升级注意事项

- 从 `1.2.7` 及更早版本升级时，旧监控数据会按“每小时、每个指标序列”的 P95 值聚合迁移；原始明细数据会被删除，无法恢复。**升级前请务必备份数据库。**
- 更换 Metric Store 数据库后，历史指标数据不再在启动时自动复制。请在 WebUI 中手动启动指标库迁移。
- 新安装实例不再从启动日志或 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 环境变量获取初始账号，改为访问站点后完成安装向导。

## 其他

- 新增已有 Release 的重新构建工作流。
- 调整构建与发布流程，确保维护版本使用对应前端，并仅由最新正式版本更新 Docker `latest` 标签。

## What's Changed

### Commits

- `6ab9c67` refactor: use GetAllPingTasks in ReloadPingSchedule and add ordering test
- `6efc72c` refactor: remove automatic metric store startup migration; mandate manual migration
- `1f6bd13` refactor: relocate config/migrations to internal, rename corn to scheduler
- `5b93181` feat(metric): add metric store recovery mode with retry and temporary HTTP server
- `f07bd74` fix: format event time in local timezone instead of UTC
- `887381a` feat(metricstore): batch ping records for improved performance
- `11617b4` perf(metric): skip digests for non-percentile rollup queries
- `5a84889` feat: first-run installation guide
- `db2ed8e` refactor: replace stdlib log with custom logger, enforce gin release mode
- `312834f` feat: add theme market source management and archive validation
- `9d149ab` ci: add workflow to rebuild existing releases
- `9d7e24a` fix(ci): promote Docker latest explicitly
- `99c684e` fix(ci): build maintenance releases with matching frontend
- `a402cc6` fix(ci): only tag Docker latest for latest release
- `0bac110` feat: use aligned, unbuffered I/O for disk write benchmark
- `7a95546` feat: migrate legacy monitoring to hourly P95 aggregation
- `eb7ecc6` fix(resourceprobe): cast Totalram to uint64 to avoid overflow
- `f59e0e8` feat: add automatic low resource mode detection and SQLite tuning
- `b4d3977` feat: make metric deletion async and add UpdateMetricRetention
- `b554368` feat: drop obsolete builtin metrics and expose definition creation
- `cdfd5bd` fix: remove orphaned metric data before space reclaim and reject unknown metrics
- `5a66f28` fix: #609 #612 continue compaction on per-metric errors and add separate compaction gate

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.7...1.3.0