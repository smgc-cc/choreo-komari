# Komari Dockerfile for Choreo

# Version

1.3.2

# Releases

## 主要更新内容
- 新增 `GetRecordMetricMaxByClientAndTime` 接口，支持查询单项监控指标在指定时间桶内的最大值，避免加载完整记录，降低开销
- 优化 drain 函数中切片的预分配策略：根据队列当前长度动态计算容量，减少内存分配与 GC 压力
- 改进 Rollup 查询的 SQL 写法：将多个 JOIN 改为子查询，减少中间结果集大小，提升查询效率
- 通知模块中负载检查不再获取完整记录，仅查询所需指标的聚合最大值，降低 CPU 与 IO 消耗

## Bug修复
- 修复因内存分配不合理导致 CPU 占用过高的问题（#626）

## 其他
- 调整通知模块中 RAM/Swap 百分比计算时使用的总容量来源，改用客户端信息中的 `MemTotal`/`SwapTotal`，消除对记录内字段的依赖

### Commits

- perf: preallocate slice capacity based on queue length in drain functions ([1c75cb8](https://github.com/komari-monitor/komari/commit/1c75cb8be0fc3e301a12bc968418d63ddd45e007)) @Akizon77
- fix: #626 CPU占用过大 ([05a91ad](https://github.com/komari-monitor/komari/commit/05a91adc53280767fb2f9ce062adc8c901ea31df)) @Akizon77

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.3.1...1.3.2