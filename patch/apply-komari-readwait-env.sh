#!/usr/bin/env sh
set -eu

python3 - <<'PY'
from pathlib import Path
import re

report = Path('api/client/report.go')
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
        r'(?s)const \(\n'
        r'\t// 如果超过这个时间没有收到任何消息，则认为连接已死\n'
        r'\t// 因为目前server没有存agent的信息上报间隔。只有写一个默认的\n'
        r'\treadWait = 11 \* time\.Second\n'
        r'\)'
    )
    text, count = pattern.subn(replacement.rstrip(), text, count=1)
    if count != 1:
        candidates = [line for line in text.splitlines() if 'readWait' in line]
        raise SystemExit('cannot find readWait const block to replace. candidates: ' + repr(candidates[:8]))

if 'websocket report loop closed' not in text:
    old = '''\t\t_, message, err := conn.ReadMessage()\n\t\tif err != nil {\n\t\t\tif websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {\n\t\t\t\tlog.Printf("Client %s connection error: %v", uuid, err)\n\t\t\t}\n\t\t\tbreak // 任何读错误（包括超时）都意味着连接已断开，退出循环\n\t\t}\n'''
    new = '''\t\t_, message, err := conn.ReadMessage()\n\t\tif err != nil {\n\t\t\tlastReportAge := "unknown"\n\t\t\tif latestReport := ws.GetLatestReport()[uuid]; latestReport != nil {\n\t\t\t\tlastReportAge = time.Since(latestReport.UpdatedAt).String()\n\t\t\t}\n\t\t\tlog.Printf("Client %s websocket report loop closed, connID: %d, readWait: %s, lastReportAge: %s, err: %v", uuid, conn.ID, readWait, lastReportAge, err)\n\t\t\tif websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {\n\t\t\t\tlog.Printf("Client %s connection error: %v", uuid, err)\n\t\t\t}\n\t\t\tbreak // 任何读错误（包括超时）都意味着连接已断开，退出循环\n\t\t}\n'''
    if old not in text:
        matches = [line for line in text.splitlines() if 'ReadMessage()' in line or 'connection error' in line]
        raise SystemExit('cannot find websocket read error block to instrument. candidates: ' + repr(matches[:8]))
    text = text.replace(old, new, 1)

report.write_text(text)
PY

gofmt -w api/client/report.go

grep -q '"os"' api/client/report.go
grep -q '"strconv"' api/client/report.go
grep -q 'var readWait = getReadWaitDuration()' api/client/report.go
grep -q 'KOMARI_AGENT_READ_WAIT' api/client/report.go
grep -q 'websocket report loop closed' api/client/report.go
