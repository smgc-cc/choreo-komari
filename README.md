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

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.6...1.2.7

---

## 部署文档

- **[README.choreo.md](./README.choreo.md)** — 部署说明  
  - **模式一（推荐）**：Snippet + 官方 agent 长基址  
  - **模式二**：全流量 Worker  
  - 附录：多域名特例（可选）  
- **[AGENT.choreo.md](./AGENT.choreo.md)** — 外部 Agent 配置（官方二进制）
