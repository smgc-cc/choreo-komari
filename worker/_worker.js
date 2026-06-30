/**
 * Cloudflare Worker for Komari on Choreo
 *
 * 主要处理 WebSocket 代理，同时放行 Agent 的 HTTP API 请求。
 * 配合 _snippet.js (Cloudflare Snippet) 使用：
 * - Snippet 处理主站 HTTP 流量并注入脚本将 WS 重定向到本 Worker
 * - Worker 处理 WebSocket + Agent HTTP 上报
 * - 非 Agent API 的 HTTP 访问返回 426 (防止暴露)
 *
 * 架构:
 * - Choreo HTTP 端点 (8080) → Komari
 * - Choreo WS 端点 (8081) → Caddy → Komari (8080)
 */

// ============ 配置区域 ============

const CHOREO_ORIGIN = "uuid-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";

// ============ 代码区域 ============

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // WebSocket → 代理到 Choreo WS 端点
    const upgradeHeader = request.headers.get("Upgrade");
    if (upgradeHeader && upgradeHeader.toLowerCase() === "websocket") {
      return handleWebSocket(request, path, url.search);
    }

    // Agent HTTP API → 代理到 Choreo HTTP 端点
    // Agent 的 -e 指向 ws. 域名时，basicInfo/report/task 等 POST 走这里
    if (path.startsWith("/api/clients/")) {
      return handleAgentHTTP(request, url, path);
    }

    // 其他 HTTP → 426 拒绝（防暴露）
    return new Response(null, { status: 426, headers: { "Upgrade": "websocket" } });
  },
};

/**
 * WebSocket 代理
 */
async function handleWebSocket(request, path, search) {
  const upstreamUrl = `https://${CHOREO_ORIGIN}${WS_PATH_PREFIX}${path}${search}`;

  try {
    const upstreamRequest = new Request(upstreamUrl, request);
    upstreamRequest.headers.set("Host", CHOREO_ORIGIN);
    upstreamRequest.headers.delete("Origin");

    const response = await fetch(upstreamRequest);

    if (response.status >= 400) {
      const body = await response.text();
      return new Response(body, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      });
    }

    return response;
  } catch (error) {
    return new Response(`WebSocket proxy error: ${error.message}`, { status: 502 });
  }
}

/**
 * Agent HTTP 代理 (basicInfo/report/task/register 等)
 */
async function handleAgentHTTP(request, url, path) {
  const upstreamUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${path}${url.search}`;

  const headers = new Headers();
  for (const [key, value] of request.headers.entries()) {
    const lk = key.toLowerCase();
    if (lk !== "host" && lk !== "origin") {
      headers.set(key, value);
    }
  }
  headers.set("Host", CHOREO_ORIGIN);

  let body = null;
  if (request.method !== "GET" && request.method !== "HEAD") {
    try {
      body = await request.arrayBuffer();
    } catch (e) {
      body = request.body;
    }
  }

  try {
    // 手动处理重定向（Gin 尾斜杠 301 会丢 Choreo 路径前缀）
    let response = await fetch(upstreamUrl, {
      method: request.method,
      headers: headers,
      body: body,
      redirect: "manual",
    });

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("Location");
      if (location && location.startsWith("/")) {
        response = await fetch(`https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${location}`, {
          method: request.method,
          headers: headers,
          body: body,
          redirect: "follow",
        });
      }
    }

    const responseBody = await response.arrayBuffer();
    const newHeaders = new Headers(response.headers);
    newHeaders.set("Access-Control-Allow-Origin", "*");

    return new Response(responseBody, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders,
    });
  } catch (error) {
    return new Response(`Proxy error: ${error.message}`, { status: 502 });
  }
}
