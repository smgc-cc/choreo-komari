/**
 * Cloudflare Snippet for Komari on Choreo（模式一，推荐）
 *
 * 默认：单域名。面板域名 = Choreo 自定义域 = Agent 域名。
 *
 * 架构:
 * - HTTP → Snippet → CHOREO_ORIGIN + REST 前缀（toChoreoHttpPath）
 * - WS   → 不进 Snippet；注入补 WS 路径前缀；WS_PUBLIC_HOST 空则同源
 * - 官方 agent:
 *     -e https://面板域名/default/komari/komari_ws/v1.0
 *     WSS 原生穿透；HTTP 的 komari_ws 前缀由 Snippet 改写成 REST 前缀
 *
 * 可选：多域名时把 WS_PUBLIC_HOST 设为 Choreo 绑定域（见 README 附录）
 * 终端跨注册域时注入 session_token query → Caddy 转 Cookie
 *
 * 安全:
 * - HTML Cache-Control: no-store
 * - T 仅 /admin* /terminal* 且有 cookie 时注入
 * - COOKIE_DOMAIN 默认空（host-only）
 *
 * 备选：全流量 Worker → _worker_standalone.js
 */

// ============ 配置区域 ============

const CHOREO_ORIGIN =
  "uuid-dev.e1-us-east-azure.choreoapis.dev";
const HTTP_PATH_PREFIX = "/default/komari/v1.0";
const WS_PATH_PREFIX = "/default/komari/komari_ws/v1.0";
// 单域名：留空 = WebSocket 与页面同 host（推荐）
// 多域名特例：填 Choreo 已绑定的域名，例如 "komari.example.com"
const WS_PUBLIC_HOST = "";
// 一般保持空。多服务共用父域时不要填 ".example.com"
const COOKIE_DOMAIN = "";
// 注入 T 的最大长度（异常 cookie 直接丢弃）
const SESSION_TOKEN_MAX_LEN = 512;

// ============ 注入脚本 ============

function buildWsInjectScript(sessionToken) {
  // sessionToken 仅后台/终端页非空；公开页为 ""
  return `<script>
(function(){
  var P=${JSON.stringify(WS_PATH_PREFIX)};
  var H=${JSON.stringify(WS_PUBLIC_HOST)};
  var T=${JSON.stringify(sessionToken || "")};
  var O=window.WebSocket;
  window.WebSocket=function(u,p){
    var o=new URL(u,location.href);
    if(o.host===location.host||o.host===H||o.host===("ws."+location.host)){
      o.host=H;
      // 终端: 改写为 Caddy admin-terminal 捷径（网关对 /api/clients/* 更友好）
      // 原: /api/admin/client/{uuid}/terminal
      // 新: {P}/api/clients/admin-terminal/{uuid}?session_token=...
      var m=o.pathname.match(/^(?:\\/default\\/komari\\/komari_ws\\/v1\\.0)?\\/api\\/admin\\/client\\/([^/]+)\\/terminal\\/?$/);
      if(m){
        var pref=P.replace(/\\/$/,"");
        o.pathname=pref+"/api/clients/admin-terminal/"+m[1];
        if(T&&!o.searchParams.get("session_token")){
          o.searchParams.set("session_token",T);
        }
      } else {
        if(P&&o.pathname.indexOf(P)!==0){
          o.pathname=P.replace(/\\/$/,"")+o.pathname;
        }
      }
    }
    return p!==void 0?new O(o.href,p):new O(o.href);
  };
  window.WebSocket.prototype=O.prototype;
  for(var k in{CONNECTING:0,OPEN:1,CLOSING:2,CLOSED:3})window.WebSocket[k]=O[k];
})();
</script>`;
}

function readRequestCookie(request, name) {
  const raw = request.headers.get("Cookie") || "";
  for (const part of raw.split(";")) {
    const i = part.indexOf("=");
    if (i === -1) continue;
    if (part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return "";
}

/** 只允许合理字符，过长/怪异 cookie 不注入 */
function sanitizeSessionToken(token) {
  if (!token) return "";
  if (token.length > SESSION_TOKEN_MAX_LEN) return "";
  // 常见 session 形态：hex / base64url / uuid 变体
  if (!/^[A-Za-z0-9._~\-+/=]+$/.test(token)) return "";
  return token;
}

/**
 * 仅后台 / 终端 SPA 路径注入 T。
 * 首页与公开页不注入，降低 XSS 与 HTML 泄露面。
 * 注意：从首页客户端路由进 /admin 需整页刷新后才有 T；
 * 终端一般是 window.open('/terminal?uuid=') 全页加载，可命中。
 */
function shouldInjectSessionToken(path) {
  if (!path) return false;
  // 去掉尾斜杠（根除外）
  let p = path;
  if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1);
  if (p === "/admin" || p.startsWith("/admin/")) return true;
  if (p === "/terminal" || p.startsWith("/terminal/")) return true;
  // 部分构建可能用 hash 路由；path 仍多为 /
  return false;
}

function applyNoStore(headers) {
  headers.set("Cache-Control", "no-store, no-cache, must-revalidate, private");
  headers.set("Pragma", "no-cache");
  headers.set("Expires", "0");
}

/**
 * 把浏览器/Agent 的 pathname 归一成 Choreo REST 上游路径。
 *
 * 1) 已带 HTTP 前缀 → 原样（防双重前缀）
 * 2) 误带 WS 前缀（官方 agent 长基址）→ 换成 HTTP 前缀 + 剩余 path
 * 3) 裸 /api/... → 加 HTTP 前缀
 */
function toChoreoHttpPath(path) {
  const http = (HTTP_PATH_PREFIX || "").replace(/\/+$/, "") || "";
  const ws = (WS_PATH_PREFIX || "").replace(/\/+$/, "") || "";
  let p = path || "/";
  if (!p.startsWith("/")) p = "/" + p;

  if (http && (p === http || p.startsWith(http + "/"))) {
    return p;
  }
  if (ws && (p === ws || p.startsWith(ws + "/"))) {
    const rest = p.slice(ws.length) || "/";
    return http + (rest.startsWith("/") ? rest : "/" + rest);
  }
  return http + p;
}

// ============ 主处理 ============

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const requestHost = url.hostname;

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
    if (method === "HEAD" && isSPARoute(path)) method = "GET";

    const upstreamPath = toChoreoHttpPath(path);
    const upstreamUrl = `https://${CHOREO_ORIGIN}${upstreamPath}${url.search}`;

    const headers = new Headers();
    for (const [key, value] of request.headers.entries()) {
      const lk = key.toLowerCase();
      if (lk !== "host" && lk !== "origin") headers.set(key, value);
    }
    headers.set("Host", CHOREO_ORIGIN);

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
      while (response.status >= 300 && response.status < 400 && redirects < 3) {
        const location = response.headers.get("Location");
        if (!location) break;
        let redirectUrl;
        if (location.startsWith("/")) {
          // Gin 相对 Location 也走归一化，避免 agent 长基址场景双重前缀
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

      const contentType = response.headers.get("Content-Type") || "";
      const isHTML = contentType.includes("text/html");

      const newHeaders = new Headers(response.headers);
      newHeaders.set("Access-Control-Allow-Origin", "*");
      newHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
      newHeaders.set("Access-Control-Allow-Headers", "*");

      rewriteCookieDomain(response, newHeaders, requestHost);

      if (!isHTML) {
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers: newHeaders,
        });
      }

      // P0: 仅后台/终端路径注入非空 T
      let sessionForInject = "";
      if (shouldInjectSessionToken(path)) {
        sessionForInject = sanitizeSessionToken(
          readRequestCookie(request, "session_token")
        );
      }

      let html = await response.text();
      html = html.replace(
        /<head([^>]*)>/i,
        `<head$1>${buildWsInjectScript(sessionForInject)}`
      );

      newHeaders.delete("Content-Length");
      newHeaders.set("Content-Type", "text/html; charset=utf-8");
      // P0: HTML 一律禁止缓存（尤其是带 T 的后台页）
      applyNoStore(newHeaders);

      return new Response(html, {
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
            "Cache-Control": "no-store",
          },
        }
      );
    }
  },
};

function resolveSessionCookieDomain(requestHost, wsPublicHost) {
  const forced = (COOKIE_DOMAIN || "").trim();
  if (forced) return forced.startsWith(".") ? forced : `.${forced}`;

  const host = (requestHost || "").toLowerCase();
  const wsHost = (wsPublicHost || "").toLowerCase();
  if (!host) return null;
  if (!wsHost || wsHost === host) return null;
  if (wsHost.endsWith("." + host)) return "." + host;
  return null;
}

function rewriteCookieDomain(response, newHeaders, host) {
  const cookies = response.headers.getAll
    ? response.headers.getAll("Set-Cookie")
    : [response.headers.get("Set-Cookie")].filter(Boolean);
  if (!cookies.length) return;

  const domain = resolveSessionCookieDomain(host, WS_PUBLIC_HOST);
  if (!domain) return;

  newHeaders.delete("Set-Cookie");
  for (const cookie of cookies) {
    if (cookie.includes("session_token")) {
      let rewritten = cookie.replace(/;\s*Domain=[^;]*/i, "");
      rewritten += `; Domain=${domain}`;
      newHeaders.append("Set-Cookie", rewritten);
    } else {
      newHeaders.append("Set-Cookie", cookie);
    }
  }
}

function isSPARoute(path) {
  if (path.startsWith("/api/")) return false;
  if (/\.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|avif)$/i.test(path))
    return false;
  if (path === "/favicon.ico" || path === "/manifest.json" || path.startsWith("/themes/"))
    return false;
  return true;
}
