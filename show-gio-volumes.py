#!/usr/bin/env python3
"""列出 GIO 看到的卷名 —— 文件管理器(Nautilus)侧边栏显示的就是它。"""
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402

for vol in Gio.VolumeMonitor.get().get_volumes():
    try:
        mountpoint = vol.get_mountpoint()
    except AttributeError:
        mountpoint = "-"
    try:
        ident = vol.get_identifier(None)
    except TypeError:
        ident = ""
    print("%-24s %-16s %s" % (vol.get_name(), mountpoint, ident))
