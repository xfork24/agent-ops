#!/bin/bash
# 清理本次操作产生的临时文件，把中间备份移出 /etc
set -uo pipefail
WS=/home/hengliu/workspace/operations

echo "=== 1. 清理 /tmp 临时产物 ==="
rm -rf /tmp/gio-src
rm -f /tmp/gio_probe.py /tmp/gio_probe2.py /tmp/gio_click_test.py /tmp/gio_mounts_check.py
rm -f /tmp/ntfs3.err /tmp/ntfs3g.err /tmp/ntfs3g_ro.err /tmp/gnome-shell-replace.log
ls -1 /tmp/*.py /tmp/*.err /tmp/gnome-shell-replace.log 2>/dev/null || echo "  已清理干净"

echo
echo "=== 2. 中间 fstab 备份移出 /etc（只保留最初的原始备份）==="
mkdir -p "$WS/fstab-backups"
for f in /etc/fstab.bak.20261116-184314 /etc/fstab.bak.20261116-185130; do
  [ -f "$f" ] && mv "$f" "$WS/fstab-backups/" && echo "  已移动: $f -> $WS/fstab-backups/"
done
echo "--- /etc 下现存的 fstab 备份 ---"
ls -l /etc/fstab.bak.* 2>/dev/null
echo "--- 工作区归档 ---"
ls -l "$WS/fstab-backups/" 2>/dev/null

echo
echo "=== 3. 确认无其它残留 ==="
echo "被 mask 的用户服务:"
systemctl --user list-unit-files --state=masked 2>/dev/null | tail -n +2
echo "/etc/udev/rules.d 自定义规则:"
ls -l /etc/udev/rules.d/ | grep -v "^total" | grep -v "70-snap" || echo "  (无)"
echo "工作区文件:"
ls -1 "$WS" | sed 's/^/  /'
