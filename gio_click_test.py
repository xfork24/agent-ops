#!/usr/bin/env python3
# 模拟 GUI 点击：发起 g_volume_mount() 后轮询挂载结果（GIR 里 callback 不可 introspect）
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

vm = Gio.VolumeMonitor.get()


def mountpoints(v):
    try:
        return [m.get_path() for m in v.get_mountpoints()]
    except Exception:
        return []


target = None
for v in vm.get_volumes():
    if v.get_name() == "Windows":
        target = v
        break

if target is None:
    print("!! 目标卷未暴露给 GUI")
    raise SystemExit(1)

print("目标卷: %r" % target.get_name())
print("点击前挂载点: %s" % mountpoints(target))
print(">>> 发起 g_volume_mount() ...")
target.mount(Gio.MountMountFlags.NONE, None)

ctx = GLib.MainContext.default()
deadline = GLib.get_monotonic_time() + 20 * 1000 * 1000
while GLib.get_monotonic_time() < deadline:
    ctx.iteration(False)
    mps = mountpoints(target)
    if mps:
        print(">>> 挂载完成，落在: %s" % mps)
        break
    GLib.usleep(200000)
else:
    print(">>> 20 秒内未观察到挂载完成")
print("最终挂载点(GIO): %s" % mountpoints(target))

# GProxyVolume 不会回填 mountpoints，直接查内核挂载表确认真实落点
print()
print("=== 内核挂载表中的实际落点 ===")
found = False
with open("/proc/self/mountinfo") as f:
    for line in f:
        parts = line.split()
        mp, src = parts[4], parts[-2] if len(parts) > 1 else ""
        if "nvme0n1p3" in line or "024661E44661D945" in line:
            print("  挂载点: %-16s 来源: %s" % (mp, src))
            found = True
if not found:
    print("  (当前未挂载)")
