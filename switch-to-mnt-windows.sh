#!/bin/bash
# 把挂载点统一到 /mnt/windows，并验证 GUI(udisks2) 路径
set -uo pipefail
DEV=/dev/nvme0n1p3
UUID=024661E44661D945
OLD=/mnt/ntfs
NEW=/mnt/windows
FSTAB=/etc/fstab
HERE=/home/hengliu/workspace/operations

echo "======== 1. 备份 fstab ========"
BAK="$FSTAB.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$BAK"
echo "备份: $BAK"

echo
echo "======== 2. 卸载旧挂载点 $OLD ========"
systemctl stop mnt-ntfs.automount mnt-ntfs.mount 2>/dev/null
umount "$OLD" 2>&1 && echo "卸载成功" || echo "卸载失败或未挂载"

echo
echo "======== 3. fstab 挂载点 $OLD -> $NEW ========"
sed -i -E "s#^(UUID=$UUID[[:space:]]+)$OLD([[:space:]]+)#\1$NEW\2#" "$FSTAB"
grep -n "$UUID" "$FSTAB" || { echo "!! 未找到 UUID 行，恢复备份"; cp -a "$BAK" "$FSTAB"; exit 1; }

echo
echo "======== 4. 创建新挂载点 / 清理旧目录 ========"
mkdir -p "$NEW"
chmod 755 "$NEW"
rmdir "$OLD" 2>&1 && echo "已删除空目录 $OLD" || echo "保留 $OLD（目录非空）"

echo
echo "======== 5. systemd 重载并挂载 ========"
systemctl daemon-reload
if mount "$NEW"; then
  echo "挂载成功"
else
  echo "!! 挂载失败，回滚 fstab"
  cp -a "$BAK" "$FSTAB"
  systemctl daemon-reload
  exit 1
fi
findmnt "$NEW"
df -hT "$NEW"

echo
echo "======== 6. udisks2 现在读到的挂载点 ========"
udisksctl info -b "$DEV" 2>&1 | grep -E "Configuration|MountPoints|UserspaceMountOptions"

echo
echo "======== 7. 还原到『刚开机未挂载』状态，模拟 GUI 点击 ========"
systemctl stop mnt-windows.automount mnt-windows.mount 2>/dev/null
umount "$NEW" 2>&1
systemctl daemon-reload
systemctl start mnt-windows.automount 2>&1
sleep 1
echo "--- 点击前状态 ---"
findmnt "$NEW" || echo "  (未挂载)"
udisksctl info -b "$DEV" 2>&1 | grep -E "MountPoints"

echo
echo "--- 以普通用户身份模拟 Nautilus 点击 ---"
runuser -u hengliu -- python3 "$HERE/gio_click_test.py" 2>&1

echo
echo "--- 点击后状态 ---"
findmnt "$NEW" || echo "  (未挂载)"
findmnt "$DEV" 2>&1 | head -3

echo
echo "======== 8. 恢复到最终期望状态 ========"
if ! findmnt "$NEW" >/dev/null 2>&1; then
  systemctl stop mnt-windows.automount 2>/dev/null
  systemctl start mnt-windows.automount 2>/dev/null
  mount "$NEW" 2>&1 || echo "!! 最终挂载失败"
fi
systemctl daemon-reload
findmnt "$NEW"
df -hT "$NEW"
echo
echo "======== 完成 $(date '+%F %T') ========"
