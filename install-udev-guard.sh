#!/bin/bash
# 永久防护：即使 GParted 再次遗留 90-udisks-inhibit.rules，
# 也保证这个 Windows NTFS 分区始终能被文件管理器识别和挂载
set -uo pipefail
UUID=024661E44661D945
RULEFILE=/etc/udev/rules.d/99-zz-windows-ntfs-udisks.rules
INHIBIT=/run/udev/rules.d/90-udisks-inhibit.rules
DEV=/dev/nvme0n1p3

echo "======== 1. 写入 /etc/udev/rules.d 覆盖规则 ========"
cat > "$RULEFILE" <<EOF
# 让 GNOME 文件管理器始终能识别并挂载这个 Windows NTFS 分区。
# GParted 运行时会往 /run/udev/rules.d/ 写 90-udisks-inhibit.rules，
# 把所有块设备标记为 UDISKS_IGNORE=1；若它异常退出导致规则残留，
# 文件管理器就只会看到一个空磁盘图标、无法挂载。
# udev 按文件名全局排序求值，99- 会在 90- 之后生效，因此可以覆盖它。
SUBSYSTEM=="block", ENV{ID_FS_UUID}=="$UUID", ENV{UDISKS_IGNORE}="0"
EOF
cat "$RULEFILE"

echo
echo "======== 2. 重载规则并重算设备属性 ========"
udevadm control --reload-rules && echo "规则已重载"
udevadm trigger --subsystem-match=block --action=change
udevadm settle --timeout=20
sleep 2
udevadm info --query=property --name="$DEV" | grep -E "UDISKS_IGNORE" || echo "当前分区无 UDISKS_IGNORE"
systemctl restart udisks2
sleep 2
udisksctl info -b "$DEV" | grep -E "HintIgnore|MountPoints"

echo
echo "======== 3. 模拟『GParted 残留』场景验证防护有效 ========"
printf 'SUBSYSTEM=="block", ENV{UDISKS_IGNORE}="1"\n' > "$INHIBIT"
echo "已重建残留规则: $INHIBIT"
udevadm control --reload-rules
udevadm trigger --subsystem-match=block --action=change
udevadm settle --timeout=20
sleep 2
echo "--- 残留规则存在时，分区状态 ---"
udevadm info --query=property --name="$DEV" | grep -E "UDISKS_IGNORE" || echo "  分区无 UDISKS_IGNORE（被 99- 规则成功覆盖）"
systemctl restart udisks2
sleep 2
udisksctl info -b "$DEV" | grep -E "HintIgnore|MountPoints"

echo
echo "======== 4. 清理残留规则，恢复正常 ========"
mv "$INHIBIT" /run/udev/90-udisks-inhibit.rules.disabled 2>/dev/null || true
udevadm control --reload-rules
udevadm trigger --subsystem-match=block --action=change
udevadm settle --timeout=20
sleep 2
systemctl restart udisks2
sleep 2
systemctl --user restart gvfs-udisks2-volume-monitor.service 2>/dev/null || true
sleep 1
echo "--- 最终状态 ---"
udevadm info --query=property --name="$DEV" | grep -E "UDISKS_IGNORE" || echo "  分区无 UDISKS_IGNORE"
udisksctl info -b "$DEV" | grep -E "HintIgnore|MountPoints|Configuration"

echo
echo "======== 5. 恢复挂载 ========"
systemctl daemon-reload
systemctl stop mnt-windows.automount mnt-windows.mount 2>/dev/null
umount /mnt/windows 2>/dev/null
systemctl start mnt-windows.automount 2>/dev/null
sleep 1
mount /mnt/windows 2>&1 && echo "挂载成功" || echo "挂载失败"
findmnt /mnt/windows
echo
echo "======== 完成 $(date '+%F %T') ========"
