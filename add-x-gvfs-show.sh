#!/bin/bash
# 为 fstab 条目加上 x-gvfs-show，让 GNOME 图形界面显示这个卷
set -uo pipefail
UUID=024661E44661D945
FSTAB=/etc/fstab

echo "======== 1. 备份 fstab ========"
BAK="$FSTAB.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$BAK"
echo "备份: $BAK"

echo
echo "======== 2. 追加 x-gvfs-show / x-gvfs-name ========"
if grep -q "$UUID" "$FSTAB"; then
  # 若已有 x-gvfs-show 则先去掉，避免重复
  sed -i -E "s#^(UUID=$UUID[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+)(.*)\$#\1\2#" "$FSTAB"
  sed -i -E "s#^(UUID=$UUID[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+.*),x-gvfs-show,x-gvfs-name=[^[:space:]]*#\1#" "$FSTAB"
  # 在 opts 末尾（第4个字段）追加
  sed -i -E "s#^(UUID=$UUID[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+)[[:space:]]+0[[:space:]]+0[[:space:]]*\$#\1,x-gvfs-show,x-gvfs-name=Windows 0 0#" "$FSTAB"
else
  echo "!! fstab 中未找到 $UUID"
  cp -a "$BAK" "$FSTAB"
  exit 1
fi
echo "--- 新条目 ---"
grep -n "$UUID" "$FSTAB"

echo
echo "======== 3. 校验语法 ========"
findmnt --verify --verbose 2>&1 | grep -A6 "/mnt/windows" || true

echo
echo "======== 4. 重载 systemd ========"
systemctl daemon-reload
systemctl stop mnt-windows.automount mnt-windows.mount 2>/dev/null
umount /mnt/windows 2>/dev/null
systemctl start mnt-windows.automount 2>/dev/null
sleep 1
mount /mnt/windows 2>&1 && echo "重新挂载成功" || echo "挂载失败"
findmnt /mnt/windows

echo
echo "======== 完成 $(date '+%F %T') ========"
