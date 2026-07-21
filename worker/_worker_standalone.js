/**
 * Cloudflare Worker for Komari on Choreo — 模式二：全流量 Worker
 *
 * 适用：Snippet 套餐不可用。
 * 绑定自定义域名（如 komari.example.com）后，HTTP + WebSocket 均由本 Worker 代理。
 *
 * 架构:
 * - HTTP → Worker → CHOREO_ORIGIN + REST 前缀 → Komari :8080
 * - WS   → Worker → CHOREO_ORIGIN + WS 前缀 → Caddy :8081 → Komari
 *
 * 官方 agent — 短基址即可:
 *   -e "https://你的Worker域名"
 *   HTTP /api/clients/... → 自动加 REST 前缀
 *   WS   /api/clients/... → 自动加 WS 前缀
 *   （若误用长基址 .../komari_ws/v1.0，HTTP 会改写成 REST，WS 不重复加前缀）
 *
 * 浏览器:
 *   同源 WS；Worker 自动补 WS 前缀；终端 session 走 Cookie（同源，无需 query 注入）
 *
 * 部署:
 * 1. Workers & Pages → Create Worker → 粘贴本文件
 * 2. Settings → Domains & Routes → 添加自定义域名
 * 3. 注意 Workers 日请求额度（页面资源也计费）
 *
 * 推荐生产：模式一 Snippet（见 _snippet.js / README.choreo.md）
 */

// ============ 配置区域 ============

const CHOREO_ORIGIN =
  "uuid-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";

// ============ 代码区域 ============

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "*",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    const upgrade = request.headers.get("Upgrade");
    if (upgrade && upgrade.toLowerCase() === "websocket") {
      return handleWebSocket(request, path, url.search);
    }

    return handleHTTP(request, url, path);
  },
};

function stripTrailingSlash(s) {
  return (s || "").replace(/\/+$/, "");
}

/** 与 Snippet 一致：裸 path / 误带 WS 前缀 → REST 前缀 */
function toChoreoHttpPath(path) {
  const http = stripTrailingSlash(HTTP_PATH_PREFIX);
  const ws = stripTrailingSlash(WS_PATH_PREFIX);
  let p = path || "/";
  if (!p.startsWith("/")) p = "/" + p;

  if (http && (p === http || p.startsWith(http + "/"))) return p;
  if (ws && (p === ws || p.startsWith(ws + "/"))) {
    const rest = p.slice(ws.length) || "/";
    return http + (rest.startsWith("/") ? rest : "/" + rest);
  }
  return http + p;
}

/** WS 上游 path：已有前缀则保留；终端改 admin-terminal 捷径 */
function toChoreoWsPath(path) {
  const ws = stripTrailingSlash(WS_PATH_PREFIX);
  let p = path || "/";
  if (!p.startsWith("/")) p = "/" + p;

  // 剥已有前缀再处理
  if (ws && (p === ws || p.startsWith(ws + "/"))) {
    p = p.slice(ws.length) || "/";
  }

  const m = p.match(/^\/api\/admin\/client\/([^/]+)\/terminal\/?$/);
  if (m) {
    p = `/api/clients/admin-terminal/${m[1]}`;
  }

  return ws + (p.startsWith("/") ? p : "/" + p);
}

async function handleWebSocket(request, path, search) {
  const upstreamPath = toChoreoWsPath(path);
  const upstreamUrl = `https://${CHOREO_ORIGIN}${upstreamPath}${search}`;

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
    return new Response(`WebSocket proxy error: ${error.message}`, {
      status: 502,
    });
  }
}

async function handleHTTP(request, url, path) {
  let method = request.method;

  if (method === "HEAD" && isSPARoute(path)) {
    method = "GET";
  }

  const upstreamPath = toChoreoHttpPath(path);
  const upstreamUrl = `https://${CHOREO_ORIGIN}${upstreamPath}${url.search}`;
  const headers = cloneHeaders(request.headers);

  let body = null;
  if (method !== "GET" && method !== "HEAD") {
    try {
      body = await request.arrayBuffer();
    } catch (e) {
      body = request.body;
    }
  }

  try {
    let response = await fetch(upstreamUrl, {
      method,
      headers,
      body,
      redirect: "manual",
    });

    let redirects = 0;
    while (response.status >= 300 && response.status < 400 && redirects < 5) {
      const location = response.headers.get("Location");
      if (!location) break;

      let redirectUrl;
      if (location.startsWith("/")) {
        redirectUrl = `https://${CHOREO_ORIGIN}${toChoreoHttpPath(location)}`;
      } else if (location.startsWith("http")) {
        redirectUrl = location;
      } else {
        redirectUrl = new URL(location, upstreamUrl).href;
      }

      response = await fetch(redirectUrl, {
        method,
        headers,
        body,
        redirect: "manual",
      });
      redirects++;
    }

    const responseBody = await response.arrayBuffer();

    const newHeaders = new Headers(response.headers);
    newHeaders.set("Access-Control-Allow-Origin", "*");
    newHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    newHeaders.set("Access-Control-Allow-Headers", "*");

    return new Response(responseBody, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders,
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        status: "error",
        message: `Proxy error: ${error.message}`,
      }),
      {
        status: 502,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
}

function cloneHeaders(originalHeaders) {
  const headers = new Headers();
  for (const [key, value] of originalHeaders.entries()) {
    const lk = key.toLowerCase();
    if (lk !== "host" && lk !== "origin") {
      headers.set(key, value);
    }
  }
  headers.set("Host", CHOREO_ORIGIN);
  return headers;
}

function isSPARoute(path) {
  if (path.startsWith("/api/")) return false;
  if (/\.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|avif)$/i.test(path))
    return false;
  if (path === "/favicon.ico" || path === "/manifest.json" || path.startsWith("/themes/"))
    return false;
  return true;
}
