#!/bin/bash
# 验证 fstab + systemd automount 的开机行为（模拟：卸载 -> 让 systemd 接管 -> 首次访问触发挂载）
set -uo pipefail
MP=/mnt/ntfs

umount "$MP" 2>&1
echo "卸载后:"; findmnt "$MP" || echo "  已卸载"

systemctl daemon-reload
systemctl start mnt-ntfs.automount
echo "automount 单元: $(systemctl is-active mnt-ntfs.automount) / $(systemctl is-enabled mnt-ntfs.automount)"

echo "--- 触发访问（模拟开机后首次访问）---"
ls "$MP" >/dev/null 2>&1
sleep 1
echo "访问后挂载状态:"
findmnt -no SOURCE,FSTYPE,OPTIONS "$MP"

echo "--- 目录内容 ---"
ls "$MP" | head -5

echo "--- 可写性 ---"
TESTFILE="$MP/.mavis-automount-test"
if touch "$TESTFILE" 2>/dev/null; then
  echo "写入 OK"
  rm -f "$TESTFILE"
else
  echo "写入失败"
fi
