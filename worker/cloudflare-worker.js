/**
 * Cloudflare Worker for Komari on Choreo (Caddy 版本)
 *
 * 用于将 Komari 部署到 Choreo 时，通过 Cloudflare Worker 实现路由代理。
 * 此版本配合 Caddy 反向代理使用，不需要修改 Komari 源代码。
 *
 * 架构:
 * - Komari 运行在 8080 端口（单端口，原始代码）
 * - Caddy 运行在 8081 端口，代理到 8080
 * - Choreo HTTP 端点 (8080) → Komari
 * - Choreo WS 端点 (8081) → Caddy → Komari
 *
 * 部署步骤:
 * 1. 在 Cloudflare Dashboard → Workers & Pages → Create Worker
 * 2. 粘贴此代码并部署
 * 3. 在 Worker Settings → Triggers 中绑定自定义域名
 * 4. 确保域名 DNS 记录开启 Cloudflare 代理（橙色云朵）
 *
 * 注意: 必须绑定自定义域名才能正常代理 WebSocket 连接
 */

// ============ 配置区域 ============
// 请根据你的 Choreo 部署修改以下配置

const CHOREO_ORIGIN = "uuid-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";

// ============ 代码区域 ============

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 调试端点
    if (path === '/debug-worker') {
      return new Response('Worker is active! Caddy version v1', { status: 200 });
    }

    // 请求回显调试端点
    if (path === '/debug-request') {
      return handleDebugRequest(request, url, env);
    }

    // 处理 CORS 预检请求
    if (request.method === "OPTIONS") {
      return handleCORS();
    }

    // 检查是否是 WebSocket 升级请求
    const upgradeHeader = request.headers.get("Upgrade");
    const isWebSocketUpgrade = upgradeHeader && upgradeHeader.toLowerCase() === "websocket";

    console.log(`[Request] ${request.method} ${path} | WS: ${isWebSocketUpgrade}`);

    // 所有 WebSocket 请求都路由到 WS 端点（通过 Caddy 代理到 Komari）
    if (isWebSocketUpgrade) {
      return handleWebSocket(request, url);
    }

    // 其他 HTTP 请求走 HTTP 端点
    return handleHTTP(request, url);
  },
};

/**
 * 处理 CORS 预检请求
 */
function handleCORS() {
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

/**
 * 处理所有 WebSocket 连接
 * 路由到 Choreo WS 端点 (8081) → Caddy → Komari (8080)
 */
async function handleWebSocket(request, url) {
  let path = url.pathname;

  // Choreo WS 端点只允许 /api/clients/* 路径
  // 将 /api/admin/client/:uuid/terminal 重写为 /api/clients/admin-terminal/:uuid
  // Caddy 会将其还原回原始路径
  const adminTerminalMatch = path.match(/^\/api\/admin\/client\/([^/]+)\/terminal$/);
  if (adminTerminalMatch) {
    const uuid = adminTerminalMatch[1];
    path = `/api/clients/admin-terminal/${uuid}`;
    console.log(`[WebSocket] Rewriting admin terminal path to: ${path}`);
  }

  const upstreamUrl = `https://${CHOREO_ORIGIN}${WS_PATH_PREFIX}${path}${url.search}`;

  console.log(`[WebSocket] Proxying to: ${upstreamUrl}`);

  const headers = cloneHeaders(request.headers, CHOREO_ORIGIN);

  const upstreamRequest = new Request(upstreamUrl, {
    method: request.method,
    headers: headers,
  });

  try {
    const response = await fetch(upstreamRequest);
    console.log(`[WebSocket] Response status: ${response.status}`);

    // 如果是错误响应，记录详情
    if (response.status >= 400) {
      const responseBody = await response.text();
      console.log(`[WebSocket] Error response: ${responseBody.substring(0, 500)}`);
      return new Response(responseBody, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      });
    }

    return response;
  } catch (error) {
    console.log(`[WebSocket] Error: ${error.message}`);
    return new Response(`WebSocket proxy error: ${error.message}`, { status: 502 });
  }
}

/**
 * 判断是否是 SPA 路由（非 API 且非静态资源）
 */
function isSPARoute(path) {
  const isApiPath = path.startsWith('/api/');
  const isStaticAsset = /\.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|avif)$/i.test(path);
  const isSpecialPath = path === '/favicon.ico' || path === '/manifest.json' || path.startsWith('/themes/');
  return !isApiPath && !isStaticAsset && !isSpecialPath;
}

/**
 * 处理 HTTP 请求
 */
async function handleHTTP(request, url) {
  const path = url.pathname;
  let method = request.method;

  // Safari 等浏览器会对页面链接发起 HEAD 预取请求
  // 对于 SPA 路由的 HEAD 请求，转换为 GET 请求以获得正确响应
  if (method === 'HEAD' && isSPARoute(path)) {
    console.log(`[HTTP] Converting HEAD to GET for SPA route: ${path}`);
    method = 'GET';
  }

  let upstreamUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${path}${url.search}`;

  console.log(`[HTTP] Proxying ${method} to: ${upstreamUrl}`);

  const headers = cloneHeaders(request.headers, CHOREO_ORIGIN);

  // 对于有请求体的请求，先读取为 ArrayBuffer
  let body = null;
  if (method !== "GET" && method !== "HEAD") {
    try {
      body = await request.arrayBuffer();
    } catch (e) {
      body = request.body;
    }
  }

  // 手动处理重定向，保持请求方法不变
  let upstreamRequest = new Request(upstreamUrl, {
    method: method,
    headers: headers,
    body: body,
    redirect: "manual",
  });

  try {
    let response = await fetch(upstreamRequest);
    console.log(`[HTTP] Response status: ${response.status}`);

    // 手动处理重定向
    let redirectCount = 0;
    const maxRedirects = 5;
    while (response.status >= 300 && response.status < 400 && redirectCount < maxRedirects) {
      const location = response.headers.get("Location");
      if (!location) break;

      const redirectUrl = buildRedirectUrl(location, upstreamUrl);

      console.log(`[HTTP] Following redirect to: ${redirectUrl}`);

      upstreamRequest = new Request(redirectUrl, {
        method: method,
        headers: headers,
        body: body,
        redirect: "manual",
      });

      response = await fetch(upstreamRequest);
      redirectCount++;
    }

    // 读取完整响应体
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
    console.log(`[HTTP] Error: ${error.message}`);
    return new Response(JSON.stringify({ status: "error", message: `Proxy error: ${error.message}` }), {
      status: 502,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      }
    });
  }
}

function handleDebugRequest(request, url, env) {
  const debugToken = env.DEBUG_TOKEN || "";
  const requestToken = request.headers.get("X-Debug-Token") || url.searchParams.get("debug_token") || "";

  if (!debugToken || requestToken !== debugToken) {
    return new Response("Not found", { status: 404 });
  }

  const debugInfo = {
    method: request.method,
    url: request.url,
    path: url.pathname,
    search: url.search,
    headers: redactHeaders(request.headers),
  };

  return new Response(JSON.stringify(debugInfo, null, 2), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  });
}

function redactHeaders(originalHeaders) {
  const sensitiveHeaders = new Set([
    "authorization",
    "cookie",
    "set-cookie",
    "cf-access-client-secret",
    "x-debug-token",
  ]);
  const headers = {};

  for (const [key, value] of originalHeaders.entries()) {
    headers[key] = sensitiveHeaders.has(key.toLowerCase()) ? "[REDACTED]" : value;
  }

  return headers;
}

function buildRedirectUrl(location, upstreamUrl) {
  if (location.startsWith("/")) {
    return new URL(`${HTTP_PATH_PREFIX}${location}`, `https://${CHOREO_ORIGIN}`).href;
  }

  return new URL(location, upstreamUrl).href;
}

/**
 * 克隆请求头，替换 Host
 */
function cloneHeaders(originalHeaders, newHost) {
  const headers = new Headers();
  for (const [key, value] of originalHeaders.entries()) {
    if (key.toLowerCase() !== 'host') {
      headers.set(key, value);
    }
  }
  headers.set('Host', newHost);
  return headers;
}
