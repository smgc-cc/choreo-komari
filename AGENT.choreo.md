# Komari Agent（Choreo）

外部节点使用 **官方** `komari-agent` 即可。

---

## 模式一（推荐）：长基址

面板域名与 Choreo 绑定域为 **同一主机**（默认）：

```bash
# https:// + WS 网关前缀（不要写 wss://）
komari-agent \
  -e "https://komari.example.com/default/komari/komari_ws/v1.0" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

| 流量 | agent 请求 | 边缘 |
|---|---|---|
| **WS** | `wss://.../default/komari/komari_ws/v1.0/api/clients/...` | 原生穿透 |
| **HTTP** | `https://.../default/komari/komari_ws/v1.0/api/clients/...` | Snippet 将 `komari_ws` 改写成 REST `v1.0` |

要求：Snippet 匹配该域名；Choreo 自定义域已绑定；WebSockets On。  
容器内置 agent 仍用 `http://localhost:8080`，与公网无关。

### 验证

```bash
HOST=komari.example.com

curl -sS -D- -o /dev/null -X POST \
  "https://${HOST}/default/komari/komari_ws/v1.0/api/clients/uploadBasicInfo?token=x" \
  -H "Content-Type: application/json" -d '{}' | head -15

curl --http1.1 -sS -D- -o /dev/null -m 12 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "https://${HOST}/default/komari/komari_ws/v1.0/api/clients/v2/rpc?token=x" | head -15
```

多域名特例时，把 `HOST` 换成 **基建域**（与 `WS_PUBLIC_HOST` / Choreo 绑定一致），见 README 附录。

---

## 模式二：全流量 Worker

短 `-e` 即可：

```bash
komari-agent \
  -e "https://komari.example.com" \
  -t "YOUR_TOKEN" \
  --disable-auto-update
```

Worker 按协议分别补 REST / WS 前缀。

---

## 不要

| 写法 | 原因 |
|---|---|
| `-e wss://...` | 会变成 `wswss://` |
| 模式一 `-e https://host` 无前缀 | Snippet 补不了 WS 路径 |
| 模式一只填 REST 前缀 `.../v1.0` | WS 前缀错误 |

完整部署见 [README.choreo.md](./README.choreo.md)。

后台「Agent 连接地址」（`script_domain`）只影响安装命令文案，**不能**代替这里的 `-e`；说明见 README「站点设置：CORS / WebSocket Origin / Agent 连接地址」。
