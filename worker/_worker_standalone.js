/**
 * Cloudflare Worker for Komari on Choreo (完整独立版)
 *
 * 不依赖 Snippet，独立处理所有 HTTP 和 WebSocket 流量。
 * 绑定自定义域名后即可完整运行 Komari。
 *
 * 部署:
 * 1. Workers & Pages → Create Worker → 粘贴此代码
 * 2. Settings → Domains & Routes → 添加自定义域名
 *
 * 架构:
 * - HTTP  → Worker → Choreo HTTP 端点 (8080) → Komari
 * - WS    → Worker → Choreo WS 端点 (8081) → Caddy → Komari
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

    // CORS 预检
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

    // WebSocket
    const upgrade = request.headers.get("Upgrade");
    if (upgrade && upgrade.toLowerCase() === "websocket") {
      return handleWebSocket(request, path, url.search);
    }

    // HTTP
    return handleHTTP(request, url, path);
  },
};

// ==================== WebSocket ====================

async function handleWebSocket(request, path, search) {
  const upstreamUrl = `https://${CHOREO_ORIGIN}${WS_PATH_PREFIX}${path}${search}`;

  try {
    // 从原始请求派生，保留 WebSocket 升级语义
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

// ==================== HTTP ====================

async function handleHTTP(request, url, path) {
  let method = request.method;

  // Safari HEAD 预取 → 转 GET（SPA 路由需要完整响应）
  if (method === "HEAD" && isSPARoute(path)) {
    method = "GET";
  }

  const upstreamUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${path}${url.search}`;
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
    // 手动处理重定向：Gin 尾斜杠 301 的 Location 会丢 Choreo 路径前缀
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
        // 相对路径 → 重新加 Choreo 前缀
        redirectUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${location}${url.search}`;
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
      JSON.stringify({ status: "error", message: `Proxy error: ${error.message}` }),
      {
        status: 502,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      }
    );
  }
}

// ==================== 工具函数 ====================

/**
 * 克隆请求头，替换 Host，剥离 Origin
 *
 * Origin 必须剥离：Worker 代理后 Host 变成 Choreo 域名，
 * 和浏览器 Origin 不匹配，Komari CORS 中间件会 403。
 */
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
  if (/\.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|avif)$/i.test(path)) return false;
  if (path === "/favicon.ico" || path === "/manifest.json" || path.startsWith("/themes/")) return false;
  return true;
}
