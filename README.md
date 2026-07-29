# Komari Dockerfile for Choreo

# Version

1.3.1

# Releases

## 主要更新内容

- 备份恢复改为分块上传，支持大文件恢复 ([#618](https://github.com/komari-monitor/komari/pull/618))
- 度量存储重构：精确样本仅保留 10 分钟内存窗口，不再持久化原始点，改用分钟级热卷起 + 规范化 schema
- 新增数据库结构升级引导，取代旧版单次升级脚本，支持旧格式度量库自动迁移
- 移除低资源模式（`low_resource_mode` 配置项及相关逻辑）
- SQLite 内存使用优化：调整缓存、WAL checkpoint、页面大小等参数
- 新增 pprof 性能分析视图，方便调试
- 安装脚本不再自动获取初始密码，引导用户通过 Web 向导创建管理员账号
- 文档：简化安装说明，移除重复语言文档，中文文档移至根目录 README_zh-cn.md

## Bug修复

- 修复纯 IPv6 环境下通知发送失败的问题 ([#605](https://github.com/komari-monitor/komari/issues/605))
- 修复离线通知状态初始化遗漏 ([#608](https://github.com/komari-monitor/komari/issues/608))
- 修复 metricstore compaction 写饥饿问题
- 修复精确 upsert 窗口的热卷起刷新时序问题
- 修复备份恢复过程中临时文件残留及上下文取消时清理

## 其他

- 数据库迁移改为循环检测，自动处理结构升级后重启
- 公开 ping 任务响应中新增 `weight` 字段

## What's Changed
* feat(admin): 备份恢复改为分块上传 by @mogumc in https://github.com/komari-monitor/komari/pull/618


### Commits

- refactor: remove automatic password retrieval, guide user to web setup ([045f24e](https://github.com/komari-monitor/komari/commit/045f24ef85c9b0593322b92ba699e596f9f24fea)) @Akizon77
- fix(metricstore): avoid compaction write starvation ([17aa37c](https://github.com/komari-monitor/komari/commit/17aa37c64fa568956921f874e8e0f1a6200529a1)) @Akizon77
- feat: add weight field to public ping task response ([c7819cd](https://github.com/komari-monitor/komari/commit/c7819cd96eb4605b78fc8d6e8d9b69a0c6cb3853)) @Akizon77
- refactor: replace legacy upgrade with database migration loop ([b8c1008](https://github.com/komari-monitor/komari/commit/b8c100823fab8fa93dcff8162eb918733f6410bc)) @Akizon77
- fix(metric): defer hot rollup flush for exact upsert window ([0103b99](https://github.com/komari-monitor/komari/commit/0103b9965194b1fd3cc01b4f1b08eb2791a8c63b)) @Akizon77
- feat(metricstore): extend raw retention to 10 min, block reload if upgrade needed ([c3c3ed8](https://github.com/komari-monitor/komari/commit/c3c3ed8ecfe7e8aafa9774227620fbb776c12314)) @Akizon77
- remove low resource mode ([1ffe413](https://github.com/komari-monitor/komari/commit/1ffe413eb7b963a8c0ea86c1dba2c9724da5d3e3)) @Akizon77
- optimize sqlite memory usage ([0d69995](https://github.com/komari-monitor/komari/commit/0d699951b7d86b7b387df1eee550983deb552aa6)) @Akizon77
- feat: auto restart after reload a old metric database ([8c849aa](https://github.com/komari-monitor/komari/commit/8c849aa42348e65f8c3f69d8c844f4bdb0fde289)) @Akizon77
- docs: simplify installation instructions and update sponsor credits ([a1ae821](https://github.com/komari-monitor/komari/commit/a1ae82169c204ab456a8bbe5d95a1ea53f01e11f)) @Akizon77
- feat: pprof view ([abc53b3](https://github.com/komari-monitor/komari/commit/abc53b3cc056f7cc7e3d9c12040b9451ca6d8bf1)) @Akizon77
- fix: #605 纯 IPv6 通知发送 #608 离线通知状态初始化遗漏 ([16d6f26](https://github.com/komari-monitor/komari/commit/16d6f2670d66aa4784804aef382b9e476ea558ad)) @Akizon77
- feat(admin): 备份恢复改为分块上传 (#618) ([ebe5278](https://github.com/komari-monitor/komari/commit/ebe5278183c937cb705bd3be822bfa157966d62e)) @mogumc
- fix: skip temporary staging files and cleanup on context cancel ([d69effe](https://github.com/komari-monitor/komari/commit/d69effee7a30fa7dffd1ce35171f809626f23310)) @Akizon77

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.3.0...1.3.1