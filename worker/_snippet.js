/**
 * Cloudflare Snippet for Komari on Choreo (混合模式 - HTTP 部分)
 *
 * 处理所有 HTTP 流量（页面、API、静态资源），WebSocket 交给 Worker 处理。
 * Snippet 在返回 HTML 时注入脚本，将前端 WebSocket 连接重定向到 ws.{当前域名}，
 * 该子域名绑定到 Worker 的 Custom Domain。
 *
 * 架构:
 * - HTTP (页面/API/资源) → Snippet → Choreo HTTP 端点 [免费无限额度]
 * - WS (前端实时数据)    → ws.{host} (Worker Custom Domain) → Choreo WS 端点
 *
 * Cookie 处理:
 * - 上游 Set-Cookie 的 session_token 没有 Domain 属性（只对当前 host 生效）
 * - Snippet 给它加上 Domain=.{host}，使 cookie 对 ws.{host} 子域名也生效
 * - 这样终端等需要登录态的 WS 功能可以正常鉴权
 *
 * 配套:
 * - _worker.js: 部署为 Worker，添加 Custom Domain: ws.{host}
 * - _snippet.js: 部署为 Snippet
 */

// ============ 配置区域 ============

const CHOREO_ORIGIN = "uuid-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";

// 注入到 HTML 的脚本: 根据当前访问域名自动推导 WS 域名 (ws. 前缀)
const WS_INJECT_SCRIPT = `<script>
(function(){
  var O=window.WebSocket;
  window.WebSocket=function(u,p){
    var o=new URL(u);
    o.host="ws."+location.host;
    return p!==void 0?new O(o+"",p):new O(o+"");
  };
  window.WebSocket.prototype=O.prototype;
  for(var k in{CONNECTING:0,OPEN:1,CLOSING:2,CLOSED:3})window.WebSocket[k]=O[k];
})();
</script>`;

// ============ 代码区域 ============

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const requestHost = url.hostname; // 当前访问域名，用于 cookie domain

    // 处理 CORS 预检请求
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

    let method = request.method;

    // Safari HEAD 预取 → 转为 GET
    if (method === 'HEAD' && isSPARoute(path)) {
      method = 'GET';
    }

    const upstreamUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${path}${url.search}`;

    // 克隆请求头，替换 Host，剥离 Origin (避免 Komari CORS 403)
    const headers = new Headers();
    for (const [key, value] of request.headers.entries()) {
      const lk = key.toLowerCase();
      if (lk !== 'host' && lk !== 'origin') {
        headers.set(key, value);
      }
    }
    headers.set('Host', CHOREO_ORIGIN);

    // 读取请求体
    let body = null;
    if (method !== "GET" && method !== "HEAD") {
      try {
        body = await request.arrayBuffer();
      } catch (e) {
        body = request.body;
      }
    }

    try {
      // 手动处理重定向: Gin 的尾斜杠 301 会丢 Choreo 路径前缀
      let response = await fetch(upstreamUrl, {
        method: method,
        headers: headers,
        body: body,
        redirect: "manual",
      });

      // 处理重定向(最多跟 3 次)
      let redirects = 0;
      while (response.status >= 300 && response.status < 400 && redirects < 3) {
        const location = response.headers.get("Location");
        if (!location) break;

        let redirectUrl;
        if (location.startsWith("/")) {
          redirectUrl = `https://${CHOREO_ORIGIN}${HTTP_PATH_PREFIX}${location}`;
        } else if (location.startsWith("http")) {
          redirectUrl = location;
        } else {
          redirectUrl = new URL(location, upstreamUrl).href;
        }

        response = await fetch(redirectUrl, {
          method: method,
          headers: headers,
          body: body,
          redirect: "manual",
        });
        redirects++;
      }

      const contentType = response.headers.get("Content-Type") || "";
      const isHTML = contentType.includes("text/html");

      const newHeaders = new Headers(response.headers);
      newHeaders.set("Access-Control-Allow-Origin", "*");
      newHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
      newHeaders.set("Access-Control-Allow-Headers", "*");

      // 改写 Set-Cookie: 给 session_token 加 Domain=.{host}
      // 使 cookie 对 ws.{host} 子域名也生效（终端等 WS 功能需要登录态）
      rewriteCookieDomain(response, newHeaders, requestHost);

      if (!isHTML) {
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers: newHeaders,
        });
      }

      // HTML 响应: 注入 WS 重定向脚本
      let html = await response.text();
      html = html.replace(/<head([^>]*)>/i, `<head$1>${WS_INJECT_SCRIPT}`);

      newHeaders.delete("Content-Length");
      newHeaders.set("Content-Type", "text/html; charset=utf-8");

      return new Response(html, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders,
      });
    } catch (error) {
      return new Response(JSON.stringify({ status: "error", message: `Proxy error: ${error.message}` }), {
        status: 502,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        }
      });
    }
  },
};

/**
 * 改写 Set-Cookie 中 session_token 的 Domain
 *
 * 上游返回: Set-Cookie: session_token=xxx; Path=/; HttpOnly; Secure; SameSite=Lax
 * 改写为:   Set-Cookie: session_token=xxx; Path=/; HttpOnly; Secure; SameSite=Lax; Domain=.{host}
 *
 * Domain=.{host} 使 cookie 对 ws.{host} 子域名也生效
 * SameSite 保持 Lax: ws.{host} 与 {host} 是同站(same-site)，Lax 即可
 * 不能改为 None: Chrome 对 SameSite=None 有严格的第三方 cookie 限制，会导致登录失败
 */
function rewriteCookieDomain(response, newHeaders, host) {
  const cookies = response.headers.getAll
    ? response.headers.getAll("Set-Cookie")
    : [response.headers.get("Set-Cookie")].filter(Boolean);

  if (!cookies.length) return;

  newHeaders.delete("Set-Cookie");

  for (const cookie of cookies) {
    if (cookie.includes("session_token")) {
      // 只加 Domain，不改 SameSite
      let rewritten = cookie.replace(/;\s*Domain=[^;]*/i, "");
      rewritten += `; Domain=.${host}`;
      newHeaders.append("Set-Cookie", rewritten);
    } else {
      newHeaders.append("Set-Cookie", cookie);
    }
  }
}

function isSPARoute(path) {
  const isApiPath = path.startsWith('/api/');
  const isStaticAsset = /\.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|avif)$/i.test(path);
  const isSpecialPath = path === '/favicon.ico' || path === '/manifest.json' || path.startsWith('/themes/');
  return !isApiPath && !isStaticAsset && !isSpecialPath;
}
