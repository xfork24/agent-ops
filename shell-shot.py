#!/usr/bin/env python3
# 通过 GNOME Shell 的 Screenshot D-Bus 接口截图。
# Shell 只允许 org.gnome.Screenshot / 门户后端等特定总线名调用，
# 本脚本自行持有 org.gnome.Screenshot 这个名字（等价于 gnome-screenshot 的身份）。
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
import os, sys

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/shot.png"
cursor = (len(sys.argv) > 2 and sys.argv[2] == "cursor")

conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

acquired = GLib.MainLoop()
state = {"ok": False}


def on_acquired(bus, name):
    state["ok"] = True
    acquired.quit()


def on_lost(bus, name):
    if not state["ok"]:
        acquired.quit()


Gio.bus_own_name(Gio.BusType.SESSION, "org.gnome.Screenshot",
                 Gio.BusNameOwnerFlags.DO_NOT_QUEUE, on_acquired, on_lost)
GLib.timeout_add_seconds(10, lambda: (acquired.quit(), False)[1])
acquired.run()

if not state["ok"]:
    print("未能取得 org.gnome.Screenshot 名字")
    raise SystemExit(1)
print("已持有总线名 org.gnome.Screenshot")

try:
    res = conn.call_sync(
        "org.gnome.Shell", "/org/gnome/Shell/Screenshot",
        "org.gnome.Shell.Screenshot", "Screenshot",
        GLib.Variant("(bbs)", (cursor, False, out)),
        GLib.VariantType("(bs)"), Gio.DBusCallFlags.NONE, 60000, None)
    ok, used = res.unpack()
    print("结果: success=%s file=%s" % (ok, used))
except GLib.Error as e:
    print("失败:", e.message)
    raise SystemExit(1)

if os.path.exists(out):
    print("已保存:", out, os.path.getsize(out), "字节")
else:
    print("文件未生成")
    raise SystemExit(1)
