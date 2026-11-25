#!/bin/bash
# 完整复现：卸载 -> 模拟点击 Dock 中的 Windows 图标 -> 打开文件管理器 -> 截图
set -uo pipefail
HERE=/home/hengliu/workspace/operations

echo "=== 1. 卸载，回到点击前状态 ==="
pkexec /bin/bash -c 'systemctl stop mnt-windows.automount mnt-windows.mount 2>/dev/null; umount /mnt/windows 2>/dev/null; true'
sleep 1
echo "点击前: $(findmnt -no SOURCE,FSTYPE /mnt/windows 2>/dev/null || echo 未挂载)"

echo
echo "=== 2. 模拟点击 Windows 磁盘图标（GIO -> udisks2 -> fstab）==="
python3 "$HERE/gio_click_test.py" 2>&1 | grep -v "^Error creating proxy"
sleep 2
echo
echo "点击后挂载表:"
findmnt /mnt/windows

echo
echo "=== 3. 打开文件管理器到该卷（等同点击 Dock 图标）==="
nohup nautilus /mnt/windows >/dev/null 2>&1 &
sleep 6

echo
echo "=== 4. 截图 ==="
python3 "$HERE/shell-shot.py" /tmp/dock-after.png 2>&1

echo
echo "=== 5. 恢复 systemd automount ==="
pkexec /bin/bash -c 'systemctl start mnt-windows.automount 2>/dev/null; true'
sleep 1
findmnt /mnt/windows
