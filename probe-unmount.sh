#!/bin/bash
# 对照实验：卸载后 udisks2 / GIO 的状态
set -uo pipefail
echo "=== 卸载 /mnt/ntfs ==="
umount /mnt/ntfs 2>&1 && echo "卸载成功" || echo "卸载失败"
sleep 1
echo
echo "=== findmnt ==="
findmnt /mnt/ntfs 2>&1 || echo "  （已卸载）"
echo
echo "=== udisks2 视角 ==="
udisksctl info -b /dev/nvme0n1p3 2>&1 | grep -E "MountPoints|UserspaceMountOptions|Configuration|HintIgnore"
echo
echo "=== udisksctl mount 测试（GUI 点击走的同一条路径）==="
udisksctl mount -b /dev/nvme0n1p3 2>&1
echo "exit=$?"
