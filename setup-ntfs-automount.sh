#!/bin/bash
# 自动挂载 Windows NTFS 分区 /dev/nvme0n1p3 并写入 /etc/fstab
set -uo pipefail

DEV=/dev/nvme0n1p3
UUID=024661E44661D945
MP=/mnt/ntfs
FSTAB=/etc/fstab

echo "==== setup-ntfs-automount $(date '+%F %T') ===="

echo "--- 1. 分区识别 ---"
lsblk -no FSTYPE,LABEL,UUID,SIZE "$DEV" 2>&1
echo "设备权限: $(stat -c '%A %U:%G' "$DEV")"

echo
echo "--- 2. NTFS 卷状态检查（只读，不做任何修改）---"
ntfsfix -n "$DEV" 2>&1 | head -20

echo
echo "--- 3. 创建挂载点 $MP ---"
mkdir -p "$MP"

# 若已被挂载，先卸载以便重新测试
if findmnt -n "$MP" >/dev/null 2>&1; then
  echo "已挂载，先卸载"
  umount "$MP" 2>&1 || umount -l "$MP" 2>&1
fi

echo
echo "--- 4. 试挂载：优先 ntfs3（内核原生驱动）---"
if mount -t ntfs3 -o uid=1000,gid=1000,umask=022,noatime "$DEV" "$MP" 2>/tmp/ntfs3.err; then
  FSTYPE=ntfs3
  OPTS="defaults,uid=1000,gid=1000,umask=022,noatime,nofail,x-systemd.automount"
  echo "==> ntfs3 读写挂载成功"
else
  echo "ntfs3 挂载失败:"; cat /tmp/ntfs3.err; echo
  echo "--- 5. 试挂载：ntfs-3g（用户态，已安装）---"
  if mount -t ntfs-3g -o uid=1000,gid=1000,umask=022,noatime "$DEV" "$MP" 2>/tmp/ntfs3g.err; then
    FSTYPE=ntfs-3g
    OPTS="defaults,uid=1000,gid=1000,umask=022,noatime,nofail,x-systemd.automount,windows_names"
    echo "==> ntfs-3g 读写挂载成功"
  else
    echo "ntfs-3g 读写挂载失败:"; cat /tmp/ntfs3g.err; echo
    echo "--- 6. 回退：ntfs-3g 只读挂载（分区很可能处于 Windows 休眠状态）---"
    if mount -t ntfs-3g -o ro,uid=1000,gid=1000,umask=022,noatime "$DEV" "$MP" 2>/tmp/ntfs3g_ro.err; then
      FSTYPE=ntfs-3g
      OPTS="ro,uid=1000,gid=1000,umask=022,noatime,nofail,x-systemd.automount,windows_names"
      echo "==> ntfs-3g 只读挂载成功（分区处于休眠/脏状态）"
    else
      echo "只读挂载也失败:"; cat /tmp/ntfs3g_ro.err
      echo "!!! 未能挂载，不修改 fstab"
      exit 1
    fi
  fi
fi

echo
echo "--- 7. 挂载结果 ---"
findmnt "$MP" 2>&1
df -hT "$MP" 2>&1

echo
echo "--- 8. 备份并写入 /etc/fstab ---"
BAK="$FSTAB.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$BAK"
echo "备份: $BAK"
# 清掉同 UUID 或同挂载点的旧条目，避免重复
sed -i -E "\#^[ \t]*(UUID=$UUID|/dev/nvme0n1p3)[ \t].*\$#d" "$FSTAB"
sed -i -E "\#^[ \t]*$MP[ \t].*\$#d" "$FSTAB"
printf '\n# Windows NTFS 分区 %s (自动挂载)\nUUID=%s %s %s %s 0 0\n' "$DEV" "$UUID" "$MP" "$FSTYPE" "$OPTS" >> "$FSTAB"
echo "--- fstab 尾部 ---"
tail -n 5 "$FSTAB"

echo
echo "--- 9. daemon-reload 并按 fstab 重新挂载验证 ---"
systemctl daemon-reload
umount "$MP" 2>&1
sleep 1
if mount "$MP" 2>&1; then
  echo "==> 按 fstab 挂载成功"
else
  echo "!!! 按 fstab 挂载失败，尝试回滚"
  cp -a "$BAK" "$FSTAB"
  systemctl daemon-reload
  exit 1
fi

echo
echo "--- 10. 最终验证 ---"
findmnt "$MP" 2>&1
df -hT "$MP" 2>&1
echo
echo "写入挂载点文件测试:"
touch "$MP/.write-test-$$" && echo "可写: 是" && rm -f "$MP/.write-test-$$" || echo "可写: 否（只读挂载）"
ls -la "$MP" | head -10
echo
echo "==== 完成 $(date '+%F %T') ===="
