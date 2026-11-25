#!/usr/bin/env python3
"""把 /mnt/macos 与 /mnt/arch 的自动挂载写入 /etc/fstab（幂等）。"""

FSTAB = "/etc/fstab"

MACOS_UUID = "143c81a2-fa1a-422c-a519-5e5a0ec9f250"
ARCH_UUID = "de80e85e-8d75-4806-a358-0708b7d76ea3"

BLOCK = """
# macOS APFS 系统卷（只读；内核模块 apfs，vol=3 = "MacOS" 系统卷）
UUID={mac_uuid} /mnt/macos apfs vol=3,ro,noatime,nofail,x-systemd.automount,x-systemd.device-timeout=30,x-gvfs-show,x-gvfs-name=MacOS 0 0

# Arch Linux 根分区（ext4，卷标 Arch）
UUID={arch_uuid} /mnt/arch ext4 defaults,noatime,nofail,x-systemd.automount,x-gvfs-show,x-gvfs-name=Arch 0 2
""".format(mac_uuid=MACOS_UUID, arch_uuid=ARCH_UUID)


def main():
    with open(FSTAB) as f:
        lines = f.read().splitlines()

    # 清掉旧条目，保证重复执行不产生重复行
    lines = [l for l in lines if "/mnt/macos" not in l and "/mnt/arch" not in l]
    # 去掉尾部多余空行后拼接
    while lines and not lines[-1].strip():
        lines.pop()

    with open(FSTAB, "w") as f:
        f.write("\n".join(lines) + "\n" + BLOCK)

    print("fstab 已更新：")
    with open(FSTAB) as f:
        for line in f:
            if "/mnt/macos" in line or "/mnt/arch" in line:
                print("  " + line.rstrip())


if __name__ == "__main__":
    main()
