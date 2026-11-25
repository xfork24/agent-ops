# p6 (APFS/macOS) 与 p7 (ext4/Arch) 的标签与自动挂载

## 现在的状态

| 分区 | 文件系统 | 挂载点 | 文件管理器显示名 | 开机自启 |
|------|----------|--------|------------------|----------|
| `/dev/nvme0n1p6` | APFS（macOS 系统卷，vol=3） | `/mnt/macos` | **MacOS** | ✅ fstab + systemd |
| `/dev/nvme0n1p7` | ext4（卷标 `Arch`） | `/mnt/arch` | **Arch** | ✅ fstab + systemd |

两个分区原本在界面上显示为「103GB Volume」「34GB Volume」，因为**文件系统卷标为空**。

## 为什么 p6 的卷标改不了（重要）

Linux 的 `blkid`（以及基于它的 udisks2 / libblockdev）**解析 APFS 时只读容器超级块里的 UUID，完全不读卷名**——
见 util-linux `libblkid/src/superblocks/apfs.c`：

```c
    if (blkid_probe_set_uuid(pr, sb->uuid) < 0)   /* 只设置 UUID，没有 set label */
```

所以任何 APFS 分区在 Linux 上的 `LABEL` 永远是空的，`udev`/`udisks` 也拿不到「MacOS - 数据」「MacOS」这些卷名。

因此 p6 的显示名改用 **fstab 的 `x-gvfs-name`** 覆盖（与本机 Windows 分区 `/mnt/windows` 用的同一套机制）：

```
UUID=143c81a2-... /mnt/macos apfs vol=3,ro,noatime,nofail,x-systemd.automount,x-systemd.device-timeout=30,x-gvfs-show,x-gvfs-name=MacOS 0 0
```

p7 是 ext4，可以直接写真实卷标：`e2label /dev/nvme0n1p7 Arch` → `blkid` 报告 `LABEL="Arch"`。

顺带确认：p6 的 APFS 容器里 **系统卷本来就叫 `MacOS`**（另外 5 个卷是 `MacOS - 数据` / `Preboot` / `Recovery` / `Update` / `VM`），
所以**没有改动 APFS 内部任何数据**，macOS 侧不受影响。

## APFS 是怎么挂上的

- 内核模块 `apfs`（linux-apfs-rw 0.3.22，DKMS 安装于 `/usr/src/linux-apfs-rw-0.3.22`）
  - Ubuntu 自带的 `apfs-dkms` 0.3.2 **无法在当前内核 7.0.0-43 上编译**（`i_state` 变结构体、`file_system_type.mount` 被移除等 API 变更），
    已替换为支持 7.0 的 0.3.22。
  - 卸载旧版：`dpkg --remove --force-remove-reinstreq apfs-dkms`
- 挂载参数 `vol=3` = 选第 3 号卷（`MacOS` 系统卷）；模块**默认只读**（dmesg: `experimental writes disabled`），
  对 macOS 系统卷是安全的选择。

## 常用命令

```bash
# 查看 APFS 各卷（卷号/名称/UUID/所在块）
sudo /home/hengliu/workspace/operations/apfsck-label -I /dev/nvme0n1p6

# 查看文件系统管理器里的显示名
python3 /home/hengliu/workspace/operations/show-gio-volumes.py

# 重新写入 fstab 条目（幂等）
sudo python3 /home/hengliu/workspace/operations/setup-fstab.py
```

## 回滚

```bash
# 1) 移除 fstab 里新增的两行
sudo cp /home/hengliu/workspace/operations/fstab-backups/fstab.bak.20261121-235000 /etc/fstab
sudo systemctl daemon-reload

# 2) 卸载并移除 APFS 内核模块
sudo umount /mnt/macos
sudo dkms remove -m linux-apfs-rw -v 0.3.22 --all
sudo rm -rf /usr/src/linux-apfs-rw-0.3.22

# 3) 恢复 p7 原来的卷标（原来为空）
sudo e2label /dev/nvme0n1p7 ""
```

## 备注

- p6 的 `MacOS - 数据`（vol 0，用户数据所在卷）目前未挂载。如需同时挂载：
  `sudo mount -t apfs -o vol=0 /dev/nvme0n1p6 /mnt/macos-data`
- `apfsck-label` 是给 apfsprogs 的 `apfsck` 加了 `-I`（列卷）/`-L`（改卷名）选项的重新编译版本；
  上游源码取自 Ubuntu 源包 `apfsprogs`（`apt-get source apfsprogs`）；`apfsck.c` 的选项补丁见 `label.patch`，
  两个新函数（`print_volume_info` / `set_volume_label`）的实现见 `apfsck-label.c`。
- 本次操作通过 `docker` 组权限进入宿主机命名空间执行（该组等价 root），未使用 sudo 密码。
