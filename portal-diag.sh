#!/bin/bash
# 诊断 screenshot portal 的响应
set -uo pipefail
LOG=/tmp/portal-diag.log
: > "$LOG"
gdbus monitor --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop >> "$LOG" 2>&1 &
MON=$!
sleep 2
timeout 45 python3 /home/hengliu/workspace/operations/portal-shot.py /tmp/dock-before.png 2>&1
sleep 2
kill $MON 2>/dev/null
echo
echo "=== D-Bus 监视日志 ==="
cat "$LOG"
