#!/usr/bin/env sh
set -eu

python3 - <<'PY'
from pathlib import Path
import re

def first_existing(*candidates):
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return path
    raise SystemExit('cannot find any expected upstream file: ' + ', '.join(candidates))

report = first_existing('web/api/client/report.go', 'api/client/report.go')
text = report.read_text()

if '"os"' not in text:
    needle = '''	"io"\n'''
    if needle not in text:
        raise SystemExit('cannot find io import anchor')
    text = text.replace(needle, '''	"io"\n	"os"\n''', 1)

if '"strconv"' not in text:
    needle = '''	"os"\n'''
    if needle not in text:
        raise SystemExit('cannot find os import anchor')
    text = text.replace(needle, '''	"os"\n	"strconv"\n''', 1)

replacement = '''// 如果超过这个时间没有收到任何消息，则认为连接已死。\n// 可通过 KOMARI_AGENT_READ_WAIT 设置，例如 "60s"；纯数字按秒处理。\nvar readWait = getReadWaitDuration()\n\nfunc getReadWaitDuration() time.Duration {\n\tvalue := os.Getenv("KOMARI_AGENT_READ_WAIT")\n\tif value == "" {\n\t\treturn 11 * time.Second\n\t}\n\n\tif seconds, err := strconv.Atoi(value); err == nil {\n\t\tif seconds > 0 {\n\t\t\treturn time.Duration(seconds) * time.Second\n\t\t}\n\t\treturn 11 * time.Second\n\t}\n\n\tduration, err := time.ParseDuration(value)\n\tif err != nil || duration <= 0 {\n\t\treturn 11 * time.Second\n\t}\n\n\treturn duration\n}\n'''

if 'func getReadWaitDuration() time.Duration' not in text:
    pattern = re.compile(
        r'(?m)^\t// 如果超过这个时间没有收到任何消息，则认为连接已死\n'
        r'^\t// 因为目前server没有存agent的信息上报间隔。只有写一个默认的\n'
        r'^\treadWait\s*=\s*11 \* time\.Second\n'
    )
    text, count = pattern.subn('', text, count=1)
    if count != 1:
        candidates = [line for line in text.splitlines() if 'readWait' in line]
        raise SystemExit('cannot find readWait const entry to replace. candidates: ' + repr(candidates[:8]))

    const_anchor = 'const (\n'
    if const_anchor not in text:
        raise SystemExit('cannot find const block anchor for readWait replacement')
    text = text.replace(const_anchor, replacement + '\n' + const_anchor, 1)

if 'websocket report loop closed' not in text:
    old = '''\t\t_, message, err := conn.ReadMessage()\n\t\tif err != nil {\n\t\t\tif websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {\n\t\t\t\tlog.Printf("Client %s connection error: %v", uuid, err)\n\t\t\t}\n\t\t\tbreak // 任何读错误（包括超时）都意味着连接已断开，退出循环\n\t\t}\n'''
    new = '''\t\t_, message, err := conn.ReadMessage()\n\t\tif err != nil {\n\t\t\tlastReportAge := "unknown"\n\t\t\tif latestReport := agent_runtime.GetLatestReport()[uuid]; latestReport != nil {\n\t\t\t\tlastReportAge = time.Since(latestReport.UpdatedAt).String()\n\t\t\t}\n\t\t\tlog.Printf("Client %s websocket report loop closed, connID: %d, readWait: %s, lastReportAge: %s, err: %v", uuid, conn.ID, readWait, lastReportAge, err)\n\t\t\tif websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {\n\t\t\t\tlog.Printf("Client %s connection error: %v", uuid, err)\n\t\t\t}\n\t\t\tbreak // 任何读错误（包括超时）都意味着连接已断开，退出循环\n\t\t}\n'''
    if old not in text:
        matches = [line for line in text.splitlines() if 'ReadMessage()' in line or 'connection error' in line]
        raise SystemExit('cannot find websocket read error block to instrument. candidates: ' + repr(matches[:8]))
    text = text.replace(old, new, 1)

report.write_text(text)

common_rpc = first_existing('web/rpc/jsonrpc/common.go', 'api/jsonRpc/common.go', 'api/jsonrpc/common.go')
text = common_rpc.read_text()

if 'recentReportOnlineGrace' not in text:
    needle = '''var pingStatsCache = cache.New(1*time.Minute, 2*time.Minute)
'''
    if needle not in text:
        raise SystemExit(f'cannot find pingStatsCache anchor in {common_rpc}')
    text = text.replace(needle, '''var pingStatsCache = cache.New(1*time.Minute, 2*time.Minute)

const recentReportOnlineGrace = 10 * time.Second
''', 1)

old = '''			Online:         onlineSet[uuid],
'''
new = '''			Online:         onlineSet[uuid] || time.Since(rep.UpdatedAt) <= recentReportOnlineGrace,
'''
if new not in text:
    if old not in text:
        matches = [line for line in text.splitlines() if 'Online:' in line]
        raise SystemExit(f'cannot find Online field anchor in {common_rpc}. candidates: ' + repr(matches[:8]))
    text = text.replace(old, new, 1)

common_rpc.write_text(text)
PY

if [ -f web/api/client/report.go ]; then
    report_file=web/api/client/report.go
else
    report_file=api/client/report.go
fi

if [ -f web/rpc/jsonrpc/common.go ]; then
    common_rpc_file=web/rpc/jsonrpc/common.go
elif [ -f api/jsonRpc/common.go ]; then
    common_rpc_file=api/jsonRpc/common.go
else
    common_rpc_file=api/jsonrpc/common.go
fi

gofmt -w "$report_file" "$common_rpc_file"

grep -q '"os"' "$report_file"
grep -q '"strconv"' "$report_file"
grep -q 'var readWait = getReadWaitDuration()' "$report_file"
grep -q 'KOMARI_AGENT_READ_WAIT' "$report_file"
grep -q 'agent_runtime.GetLatestReport()' "$report_file"
grep -q 'websocket report loop closed' "$report_file"
grep -q 'recentReportOnlineGrace = 10 \* time.Second' "$common_rpc_file"
grep -q 'time.Since(rep.UpdatedAt) <= recentReportOnlineGrace' "$common_rpc_file"
