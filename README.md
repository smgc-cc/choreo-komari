# Komari Dockerfile for Choreo

# Version

1.2.5

# Releases

## What's Changed
* refactor(rpc): 统一 RPC2 管道并全量迁移 REST 接口 by @Akizon77 in https://github.com/komari-monitor/komari/pull/550
* fix(router): 修复 RPC2 迁移引入的接口契约回归 by @Akizon77 in https://github.com/komari-monitor/komari/pull/551
* fix: 修复流量报告为 0 B 问题 by @airium in https://github.com/komari-monitor/komari/pull/555


**Full Changelog**: https://github.com/komari-monitor/komari/compare/1.2.3...1.2.5

## Commits

- refactor(rpc): 统一 RPC2 管道并全量迁移 REST 接口 ([0abd9ff](https://github.com/komari-monitor/komari/commit/0abd9ff9bcca5615fdc15aad69facdc4ba4a1949)) @Akizon77
- Merge pull request #550 from komari-monitor/refactor/rpc2-unified-pipeline ([cbe6655](https://github.com/komari-monitor/komari/commit/cbe665591f21c68caa7065bf306bf418317d7874)) @Akizon77
- fix(router): 修复 RPC2 迁移引入的接口契约回归 ([091eafa](https://github.com/komari-monitor/komari/commit/091eafa74304a5fb58a2e8457a7fc3366eb41bf7)) @Akizon77
- Merge pull request #551 from komari-monitor/fix/rpc2-route-contract-regressions ([25f3e1d](https://github.com/komari-monitor/komari/commit/25f3e1d2bd655b0fc4979b83e1b666701c215315)) @Akizon77
- Merge pull request #555 from airium/fix-traffic-report ([b6e36ee](https://github.com/komari-monitor/komari/commit/b6e36ee0c4d28c47945a5f14a76994b2c8f4398d)) @airium
- docs: add abuse warning and remote control disclosure ([95cc65e](https://github.com/komari-monitor/komari/commit/95cc65e28df93662d6b45aa137310a0ee0d1be62)) @Akizon77
- chore(deps): upgrade Go and add SQL database drivers ([771a192](https://github.com/komari-monitor/komari/commit/771a192a3d0402908479c79cfafd17bd8cbf52d4)) @Akizon77
- feat(metric): support arbitrary percentile aggregations ([2e0c598](https://github.com/komari-monitor/komari/commit/2e0c598daea5b584c776f67894d0c0dd37b7f246)) @Akizon77
- fix(metric): isolate compaction scan and delete to prevent data loss ([a980bef](https://github.com/komari-monitor/komari/commit/a980befd6098ca647cced1c92e2e05a410c1e2b3)) @Akizon77
- ci: expand release notes ([e446bee](https://github.com/komari-monitor/komari/commit/e446bee90055a0bd7471debb98d0b71b1b66f855)) @Akizon77

## Komari Web Release Notes

Source: [komari-web 1.2.5](https://github.com/komari-monitor/komari-web/releases/tag/1.2.5)

### What's Changed
* fix(build): force @xterm/xterm to CJS to fix ReferenceError in vi by @Akizon77 in https://github.com/komari-monitor/komari-web/pull/75
* fix(remote-exec): 修复远程执行命令输入框输入时高度持续缩小 by @airium in https://github.com/komari-monitor/komari-web/pull/76
* Fix/xterm requestmode referenceerror by @Akizon77 in https://github.com/komari-monitor/komari-web/pull/77
* ci: expand release notes by @Akizon77 in https://github.com/komari-monitor/komari-web/pull/78


**Full Changelog**: https://github.com/komari-monitor/komari-web/compare/1.2.3...1.2.5

### Commits

- fix(build): force @xterm/xterm to CJS to fix ReferenceError in vi ([6cd2a29](https://github.com/komari-monitor/komari-web/commit/6cd2a296405c2d4f5ff6fa6f3e2f113fa59c4adc)) @Akizon77
- fix(build): force @xterm/xterm to CJS to fix ReferenceError in vi (#75) ([64967be](https://github.com/komari-monitor/komari-web/commit/64967beef7fcbf6cd16776f55f2c68508ffe89ff)) @Akizon77
- fix(remote-exec): stabilize multiline command editor height ([73a7b9e](https://github.com/komari-monitor/komari-web/commit/73a7b9ec449cc4009d78a4991e490a271ab56e51)) @airium
- fix(remote-exec): stabilize multiline command editor height (#76) ([05be773](https://github.com/komari-monitor/komari-web/commit/05be773c65a884aeeb7bc1319305afd08df429f0)) @Akizon77
- feat: add auto discovery and onboarding setup UI ([c665779](https://github.com/komari-monitor/komari-web/commit/c66577950f318f16f26e931d0fb51876db4fb228)) @Akizon77
- chore(i18n): sync locales [skip ci] ([21b3cb3](https://github.com/komari-monitor/komari-web/commit/21b3cb306b7447f5946ed9d43f0f387ea51ac2a8)) @github-actions[bot]
- Merge pull request #77 from komari-monitor/fix/xterm-requestmode-referenceerror ([af7135b](https://github.com/komari-monitor/komari-web/commit/af7135b189f03f5bb789aa4e36861736f2421a7a)) @Akizon77
- ci: expand release notes ([7e91f68](https://github.com/komari-monitor/komari-web/commit/7e91f680ba7c9d22fe4c1a28d6856af540842d43)) @Akizon77
- Merge pull request #78 from komari-monitor/fix/xterm-requestmode-referenceerror ([55a8e9b](https://github.com/komari-monitor/komari-web/commit/55a8e9b610503a927e40da7a613c1c89e06693d3)) @Akizon77