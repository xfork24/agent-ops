#!/bin/bash
# 修复：清除遗留的 udisks2 inhibit 规则，让 udisks2/GIO 重新接管该 NTFS 分区
set -uo pipefail
DEV=/dev/nvme0n1p3
RULE=/run/udev/rules.d/90-udisks-inhibit.rules
DISABLED=/run/udev/90-udisks-inhibit.rules.disabled
MP=/mnt/windows
HERE=/home/hengliu/workspace/operations

echo "======== 1. 修复前状态 ========"
echo "-- udev 属性 --"
udevadm info --query=property --name="$DEV" | grep -E "UDISKS_IGNORE" || echo "   (无 UDISKS_IGNORE)"
echo "-- udisks2 --"
udisksctl info -b "$DEV" | grep -E "HintIgnore|MountPoints"

echo
echo "======== 2. 移除遗留的 inhibit 规则（用改名代替删除，可随时还原）==========="
if [ -f "$RULE" ]; then
  mv "$RULE" "$DISABLED" && echo "已改名: $RULE -> $DISABLED"
else
  echo "规则文件不存在，跳过"
fi

echo
echo "======== 3. 重载 udev 规则并重算块设备属性 ========"
udevadm control --reload-rules 2>&1 && echo "规则已重载"
udevadm trigger --subsystem-match=block --action=change 2>&1
udevadm settle --timeout=20 2>&1
sleep 2
if udevadm info --query=property --name="$DEV" | grep -q "UDISKS_IGNORE"; then
  echo "!! UDISKS_IGNORE 仍存在"
else
  echo "UDISKS_IGNORE 已清除"
fi

echo
echo "======== 4. 重启 udisks2 ========"
systemctl restart udisks2 2>&1
sleep 3
echo "udisks2 状态: $(systemctl is-active udisks2)"
echo "-- 规则文件是否被重建 --"
ls -l /run/udev/rules.d/ 2>/dev/null | grep -i udisks || echo "   未被重建（符合预期）"
echo "-- udisks2 视角 --"
udisksctl info -b "$DEV" | grep -E "HintIgnore|MountPoints|Configuration"

echo
echo "======== 5. 回到『未挂载』状态，模拟 GUI 点击 ========"
systemctl stop mnt-windows.automount mnt-windows.mount 2>/dev/null
umount "$MP" 2>&1
systemctl start mnt-windows.automount 2>/dev/null
sleep 1
echo "点击前: $(findmnt -no SOURCE,FSTYPE "$MP" 2>/dev/null || echo '未挂载')"
echo "--- GIO 视角 + 模拟点击 ---"
env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    XDG_RUNTIME_DIR=/run/user/1000 \
    python3 "$HERE/gio_click_test.py" 2>&1

echo
echo "======== 6. 点击后状态 ========"
findmnt "$MP" 2>&1 | head -3
df -hT "$MP" 2>&1 | tail -2
echo "--- udisks2 报告的挂载点 ---"
udisksctl info -b "$DEV" | grep -E "MountPoints"

echo
echo "======== 7. 恢复最终状态 ========"
if ! findmnt "$MP" >/dev/null 2>&1; then
  systemctl stop mnt-windows.automount 2>/dev/null
  systemctl start mnt-windows.automount 2>/dev/null
  mount "$MP" 2>&1 || echo "!! 挂载失败"
fi
findmnt "$MP"
echo
echo "======== 完成 $(date '+%F %T') ========"
