# Komari Dockerfile for Choreo

# Version

1.5.1-fix1

# Releases

## 主要更新内容
- 新增 `/admin` 路由，重定向到 `/admin/dashboard`。
- Linux 构建启用 `--strip-all`，减小二进制体积。

## Bug修复
- 固定 `1.5.1` 与 `1.5.1-rc1` 的前端版本/发布来源为 `1.5.0-fix1`。

## 其他
- 更新多个 CI/CD 工作流的 Go 构建参数。

### Commits

- 重定向旧版本的主题接口？ ([6e70263](https://github.com/komari-monitor/komari/commit/6e70263c50119aded55841cb5b7b5db2d8d78dd9)) @Akizon77
- 裁剪1下 ([f089b08](https://github.com/komari-monitor/komari/commit/f089b08b3ab9ed01a779c2a54b99ef65ee0d176e)) @Akizon77
- fix: pin 1.5.1-rc1 frontend version ([1d972c4](https://github.com/komari-monitor/komari/commit/1d972c42dcb750c7fa39a453830a8782c049088a)) @Akizon77
- fix: pin 1.5.1 frontend release source ([f0cc0fb](https://github.com/komari-monitor/komari/commit/f0cc0fba38ce161935372633cae5248c934e2b23)) @Akizon77

**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.5.0-fix1...1.5.1