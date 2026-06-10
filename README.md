# Komari Dockerfile for Choreo

# Version

1.2.2

# Releases

## 修复
- 修复 1.2.1 中 v2 `agent.basicInfo` 路径未触发 GeoIP 补全的问题：新增服务器通过 v2 上报 basic info 时，现在会和 v1 一样根据 IPv4/IPv6 写入 `region`，区域旗帜可正常显示。


## 测试
- `go test ./...`

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.1...1.2.2