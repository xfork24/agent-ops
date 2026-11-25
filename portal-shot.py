#!/usr/bin/env python3
# 通过 XDG screenshot portal 截图（用于验证文件管理器侧栏）
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
import shutil, sys

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/desk.png"
loop = GLib.MainLoop()
state = {"uri": None, "code": None}


def on_response(conn, sender, path, iface, signal, params):
    code, results = params.unpack()
    state["code"] = code
    if results:
        uri = results.get("uri")
        if uri:
            state["uri"] = uri
    loop.quit()


conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
conn.signal_subscribe(
    None, "org.freedesktop.portal.Desktop", "Response",
    None, None,
    Gio.DBusSignalFlags.NONE, on_response)

params = GLib.Variant("(sa{sv})", ("", {}))
try:
    res = conn.call_sync(
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot", "Screenshot", params,
        GLib.VariantType("(o)"), Gio.DBusCallFlags.NONE, -1, None)
    handle = res.unpack()[0]
    print("request handle:", handle)
except GLib.Error as e:
    print("调用 portal 失败:", e.message)
    raise SystemExit(1)

GLib.timeout_add_seconds(25, lambda: (loop.quit(), False)[1])
loop.run()

if not state["uri"]:
    print("未拿到截图 (code=%s)" % state["code"])
    raise SystemExit(1)

src = state["uri"].replace("file://", "")
shutil.copyfile(src, out)
print("已保存:", out)
