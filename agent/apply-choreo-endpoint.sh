#!/usr/bin/env bash
# Apply minimal Choreo endpoint support onto an upstream komari-agent checkout.
#
# Expected cwd: root of a komari-monitor/komari-agent source tree.
# This script mutates source in place (no unified diff) so minor upstream
# line drift is less likely to break CI.
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

def die(msg: str) -> None:
    raise SystemExit(msg)

# ---------------------------------------------------------------------------
# cmd/flags/flag.go — add optional WS overrides
# ---------------------------------------------------------------------------
flag_path = Path("cmd/flags/flag.go")
if not flag_path.exists():
    die(f"missing {flag_path}")
flag_text = flag_path.read_text()

if "WsEndpoint" not in flag_text:
    needle = '\tEndpoint            string  `json:"endpoint" env:"AGENT_ENDPOINT"`                             // 面板地址\n'
    if needle not in flag_text:
        # tolerant fallback: find Endpoint line
        m = re.search(r'(?m)^(\tEndpoint\s+string\s+`json:"endpoint"[^`]*`[^\n]*\n)', flag_text)
        if not m:
            die("cannot find Endpoint field in cmd/flags/flag.go")
        needle = m.group(1)
    insert = (
        needle
        + '\tWsEndpoint          string  `json:"ws_endpoint" env:"AGENT_WS_ENDPOINT"`                     // WebSocket 基址（可选；默认自动 ws.{host}+前缀）\n'
        + '\tWsPathPrefix        string  `json:"ws_path_prefix" env:"AGENT_WS_PATH_PREFIX"`               // Choreo WS 路径前缀（默认 /default/komari/komari_ws/v1.0）\n'
    )
    flag_text = flag_text.replace(needle, insert, 1)
    flag_path.write_text(flag_text)
    print("patched cmd/flags/flag.go")
else:
    print("cmd/flags/flag.go already patched")

# ---------------------------------------------------------------------------
# cmd/root.go — register CLI flags
# ---------------------------------------------------------------------------
root_path = Path("cmd/root.go")
if not root_path.exists():
    die(f"missing {root_path}")
root_text = root_path.read_text()

if "WsEndpoint" not in root_text:
    needle = '\tRootCmd.PersistentFlags().StringVarP(&flags.Endpoint, "endpoint", "e", "", "API endpoint")\n'
    if needle not in root_text:
        m = re.search(
            r'(?m)^(\tRootCmd\.PersistentFlags\(\)\.StringVarP\(&flags\.Endpoint, "endpoint", "e", "", "[^"]*"\)\n)',
            root_text,
        )
        if not m:
            die("cannot find endpoint flag registration in cmd/root.go")
        needle = m.group(1)
    insert = (
        needle
        + '\tRootCmd.PersistentFlags().StringVar(&flags.WsEndpoint, "ws-endpoint", "", "WebSocket base URL (optional; default: https://ws.{host}/default/komari/komari_ws/v1.0)")\n'
        + '\tRootCmd.PersistentFlags().StringVar(&flags.WsPathPrefix, "ws-path-prefix", "", "Choreo WebSocket path prefix (default: /default/komari/komari_ws/v1.0)")\n'
    )
    root_text = root_text.replace(needle, insert, 1)
    root_path.write_text(root_text)
    print("patched cmd/root.go")
else:
    print("cmd/root.go already patched")

# ---------------------------------------------------------------------------
# server/websocket.go — derive WS base (ws.{host} + Choreo prefix)
# ---------------------------------------------------------------------------
ws_path = Path("server/websocket.go")
if not ws_path.exists():
    die(f"missing {ws_path}")
ws_text = ws_path.read_text()

if "func wsBase()" not in ws_text:
    # ensure net/url import
    if '"net/url"' not in ws_text:
        if '"net/http"' in ws_text:
            ws_text = ws_text.replace('"net/http"\n', '"net/http"\n\t"net/url"\n', 1)
        else:
            die("cannot find net/http import anchor in server/websocket.go")

    helpers = '''
// Default Choreo public WS gateway path prefix.
// With -e https://komari.example.com the agent derives:
//   wss://ws.komari.example.com/default/komari/komari_ws/v1.0/api/clients/...
const defaultWsPathPrefix = "/default/komari/komari_ws/v1.0"

func httpBase() string {
\treturn strings.TrimSuffix(flags.Endpoint, "/")
}

func isLocalEndpointHost(host string) bool {
\thost = strings.ToLower(strings.TrimSpace(host))
\tif host == "" || host == "localhost" || host == "127.0.0.1" || host == "::1" {
\t\treturn true
\t}
\tif strings.HasSuffix(host, ".localhost") || strings.HasSuffix(host, ".local") {
\t\treturn true
\t}
\treturn false
}

// wsBase returns the WebSocket HTTP(S) base used before http→ws conversion.
// Priority:
//  1. explicit --ws-endpoint / AGENT_WS_ENDPOINT
//  2. local endpoints keep -e as-is (container agent → localhost:8080)
//  3. public endpoints → https://ws.{host}{ws-path-prefix}
func wsBase() string {
\tif explicit := strings.TrimSpace(flags.WsEndpoint); explicit != "" {
\t\treturn strings.TrimSuffix(explicit, "/")
\t}

\tbase := httpBase()
\tif base == "" {
\t\treturn base
\t}

\tu, err := url.Parse(base)
\tif err != nil || u.Host == "" {
\t\treturn base
\t}
\tif isLocalEndpointHost(u.Hostname()) {
\t\treturn base
\t}

\thost := u.Hostname()
\tport := u.Port()
\tif !strings.HasPrefix(strings.ToLower(host), "ws.") {
\t\thost = "ws." + host
\t}
\tif port != "" {
\t\thost = host + ":" + port
\t}

\tprefix := strings.TrimSpace(flags.WsPathPrefix)
\tif prefix == "" {
\t\tprefix = defaultWsPathPrefix
\t}
\tif !strings.HasPrefix(prefix, "/") {
\t\tprefix = "/" + prefix
\t}
\tprefix = strings.TrimSuffix(prefix, "/")

\tscheme := u.Scheme
\tif scheme == "" {
\t\tscheme = "https"
\t}
\t// WebSocket bases must be http/https so existing "ws"+TrimPrefix(...,"http") works.
\tif scheme == "ws" {
\t\tscheme = "http"
\t}
\tif scheme == "wss" {
\t\tscheme = "https"
\t}
\treturn scheme + "://" + host + prefix
}

'''

    # insert helpers before buildWebSocketEndpoint
    marker = "func buildWebSocketEndpoint(protocolVersion int) string {"
    if marker not in ws_text:
        die("cannot find buildWebSocketEndpoint in server/websocket.go")
    ws_text = ws_text.replace(marker, helpers + marker, 1)

    # rewrite buildWebSocketEndpoint body to use wsBase()
    old_build = '''func buildWebSocketEndpoint(protocolVersion int) string {
\tpath := "/api/clients/report?token=" + flags.Token
\tif protocolVersion >= 2 {
\t\tpath = "/api/clients/v2/rpc?token=" + flags.Token
\t}
\twebsocketEndpoint := strings.TrimSuffix(flags.Endpoint, "/") + path
\twebsocketEndpoint = "ws" + strings.TrimPrefix(websocketEndpoint, "http")
'''
    new_build = '''func buildWebSocketEndpoint(protocolVersion int) string {
\tpath := "/api/clients/report?token=" + flags.Token
\tif protocolVersion >= 2 {
\t\tpath = "/api/clients/v2/rpc?token=" + flags.Token
\t}
\twebsocketEndpoint := wsBase() + path
\twebsocketEndpoint = "ws" + strings.TrimPrefix(websocketEndpoint, "http")
'''
    if old_build not in ws_text:
        # looser replace of the concatenation line only
        ws_text2, n = re.subn(
            r'websocketEndpoint := strings\.TrimSuffix\(flags\.Endpoint, "/"\) \+ path',
            'websocketEndpoint := wsBase() + path',
            ws_text,
            count=1,
        )
        if n != 1:
            die("cannot rewrite buildWebSocketEndpoint concatenation")
        ws_text = ws_text2
    else:
        ws_text = ws_text.replace(old_build, new_build, 1)

    # v2 POST fallback still uses HTTP endpoint (Snippet) — use httpBase()
    ws_text2, n = re.subn(
        r'endpoint := strings\.TrimSuffix\(flags\.Endpoint, "/"\) \+ "/api/clients/v2/rpc\?token=" \+ flags\.Token',
        'endpoint := httpBase() + "/api/clients/v2/rpc?token=" + flags.Token',
        ws_text,
        count=1,
    )
    if n != 1:
        die("cannot rewrite postV2Request endpoint concatenation")
    ws_text = ws_text2

    # terminal uses flags.Endpoint — change establishTerminalConnection to prefer wsBase
    # The call sites pass flags.Endpoint; better change the function body.
    old_term = '''func establishTerminalConnection(token, id, endpoint string) {
\tendpoint = strings.TrimSuffix(endpoint, "/") + "/api/clients/terminal?token=" + token + "&id=" + id
\tendpoint = "ws" + strings.TrimPrefix(endpoint, "http")
'''
    new_term = '''func establishTerminalConnection(token, id, endpoint string) {
\t// Prefer Choreo-aware wsBase(); fall back to the provided endpoint for callers.
\tbase := wsBase()
\tif base == "" {
\t\tbase = strings.TrimSuffix(endpoint, "/")
\t}
\tendpoint = base + "/api/clients/terminal?token=" + token + "&id=" + id
\tendpoint = "ws" + strings.TrimPrefix(endpoint, "http")
'''
    if old_term not in ws_text:
        # try looser
        if "func establishTerminalConnection(token, id, endpoint string)" not in ws_text:
            die("cannot find establishTerminalConnection")
        ws_text2, n = re.subn(
            r'func establishTerminalConnection\(token, id, endpoint string\) \{\n'
            r'\tendpoint = strings\.TrimSuffix\(endpoint, "/"\) \+ "/api/clients/terminal\?token=" \+ token \+ "&id=" \+ id\n'
            r'\tendpoint = "ws" \+ strings\.TrimPrefix\(endpoint, "http"\)\n',
            new_term,
            ws_text,
            count=1,
        )
        if n != 1:
            die("cannot rewrite establishTerminalConnection")
        ws_text = ws_text2
    else:
        ws_text = ws_text.replace(old_term, new_term, 1)

    ws_path.write_text(ws_text)
    print("patched server/websocket.go")
else:
    print("server/websocket.go already patched")

# ---------------------------------------------------------------------------
# server/basicInfo.go — keep HTTP on -e (Snippet)
# ---------------------------------------------------------------------------
bi_path = Path("server/basicInfo.go")
if not bi_path.exists():
    die(f"missing {bi_path}")
bi_text = bi_path.read_text()

if "httpBase()" not in bi_text:
    # basicInfo may not import helpers from websocket.go — same package server, OK
    bi_text2, n1 = re.subn(
        r'endpoint := strings\.TrimSuffix\(flags\.Endpoint, "/"\) \+ "/api/clients/uploadBasicInfo\?token=" \+ flags\.Token',
        'endpoint := httpBase() + "/api/clients/uploadBasicInfo?token=" + flags.Token',
        bi_text,
        count=1,
    )
    bi_text2, n2 = re.subn(
        r'endpoint = strings\.TrimSuffix\(flags\.Endpoint, "/"\) \+ "/api/clients/v2/rpc\?token=" \+ flags\.Token',
        'endpoint = httpBase() + "/api/clients/v2/rpc?token=" + flags.Token',
        bi_text2,
        count=1,
    )
    if n1 != 1 or n2 != 1:
        die(f"cannot rewrite basicInfo endpoint concatenations (n1={n1}, n2={n2})")
    # TrimSuffix was the only strings use in this file on current upstream.
    if re.search(r'(?m)^\t"strings"\n', bi_text2) and "strings." not in bi_text2.replace('"strings"', ""):
        bi_text2 = re.sub(r'(?m)^\t"strings"\n', "", bi_text2, count=1)
    bi_path.write_text(bi_text2)
    print("patched server/basicInfo.go")
else:
    print("server/basicInfo.go already patched")

print("Choreo endpoint patch applied successfully")
PY

# Format if gofmt is available
if command -v gofmt >/dev/null 2>&1; then
  gofmt -w cmd/flags/flag.go cmd/root.go server/websocket.go server/basicInfo.go
fi

# Sanity checks
grep -q 'WsEndpoint' cmd/flags/flag.go
grep -q 'ws-endpoint' cmd/root.go
grep -q 'func wsBase()' server/websocket.go
grep -q 'wsBase() + path' server/websocket.go
grep -q 'httpBase() + "/api/clients/uploadBasicInfo' server/basicInfo.go

echo "OK: Choreo agent endpoint patch verified"
