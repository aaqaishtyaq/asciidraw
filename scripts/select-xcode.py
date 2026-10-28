#!/usr/bin/env python3
"""Point xcode-select at the newest Xcode installed on this machine."""

import glob
import os
import plistlib
import subprocess

best = None
best_version = ()
for app in glob.glob("/Applications/Xcode*.app"):
    plist_path = os.path.join(app, "Contents", "Info.plist")
    if not os.path.exists(plist_path):
        continue
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    raw = str(info.get("CFBundleShortVersionString", "0"))
    parts = tuple(int(piece) if piece.isdigit() else 0 for piece in raw.split("."))
    print(f"{raw}\t{app}")
    if parts > best_version:
        best_version = parts
        best = app

if best:
    subprocess.check_call(["sudo", "xcode-select", "-s", best])
