# Komari Dockerfile for Choreo

# Version

1.4.1

# Releases

## 主要更新内容

- **设置页面新增顶部分类 TAB 页签**：插件配置、主题管理等设置页支持按分类页签导航，滚动时自动高亮当前分组（[#629](https://github.com/komari-monitor/komari/issues/629)）
- **仪表盘性能优化**：流量汇总与 TOP 排行（CPU / 内存 / 延迟）统一由单次指标查询结果派生，避免重复请求；续期节点数据过滤不再需要重新拉取
- **CPU 排行改为加权平均值**：仪表盘 CPU 排行不再使用 P95，改为按计数加权的平均值计算，数值更贴近真实占用水平
- **登录表单改进**：改用原生 `<form>` 提交，支持浏览器自动填充（用户名 / 密码 / 2FA 验证码），修复回车提交相关问题（[#630](https://github.com/komari-monitor/komari/issues/630)）
- **降低 SQLite 默认内存占用**：缓存大小默认从 16MB 调整为 4MB，WAL journal 大小限制从 16MB 调整为 4MB
- **SQLite mmap 改为默认关闭**。

## Bug修复

- 修复管理后台服务器节点列表账单到期时间显示问题（[#637](https://github.com/komari-monitor/komari/issues/637)）
- 修复统计图表 Y 轴标签溢出问题
- 修复登录提交与指标统计有效性判断：指标数据无效时不再展示 p99/p50 比值（[#630](https://github.com/komari-monitor/komari/issues/630)）

## 其他

- 更新测试，使其匹配新的默认 journal 大小限制

### Commits

**Komari Web (komari-web)**

- fix: CPU排行榜数值偏高 ([f625b34](https://github.com/komari-monitor/komari-web/commit/f625b34)) @Akizon77
- fix: 统计图表y标签溢出 ([b29b932](https://github.com/komari-monitor/komari-web/commit/b29b932)) @Akizon77
- feat: 设置增加顶部分类TAB页签 [#629](https://github.com/komari-monitor/komari/issues/629) ([2341abc](https://github.com/komari-monitor/komari-web/commit/2341abc)) @Akizon77
- fix: 后台服务器节点列表账单到期时间问题 [#637](https://github.com/komari-monitor/komari/issues/637) ([1eaf927](https://github.com/komari-monitor/komari-web/commit/1eaf927)) @Akizon77
- fix: improve login form submission and metric stat validity [#630](https://github.com/komari-monitor/komari/issues/630) ([912bde3](https://github.com/komari-monitor/komari-web/commit/912bde3)) @Akizon77
- perf: filter out renewed nodes without refetching ([254a72c](https://github.com/komari-monitor/komari-web/commit/254a72c)) @Akizon77
- feat(admin): derive traffic summary and top p95 metrics ([009f6eb](https://github.com/komari-monitor/komari-web/commit/009f6eb)) @Akizon77

**Komari Server (komari)**

- perf(metric): reduce SQLite memory usage and make mmap opt-in ([61bd0c8](https://github.com/komari-monitor/komari/commit/61bd0c8)) @Akizon77

**Full Changelog**: [1.4.0...1.4.1](https://github.com/komari-monitor/komari/compare/1.4.0...1.4.1)