#!/usr/bin/env python3
"""Verify alternate icons in the archive that TestFlight is about to upload."""
from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path


def verify(archive: Path) -> None:
    required = {"AppIcon-A", "AppIcon-B", "AppIcon-C"}
    apps = list((archive / "Products/Applications").glob("*.app/Info.plist"))
    if len(apps) != 1:
        raise SystemExit(f"expected one archived app, found {len(apps)}: {archive}")
    info = plistlib.loads(apps[0].read_bytes())
    icons = set((info.get("CFBundleIcons") or {}).get("CFBundleAlternateIcons") or {})
    if not required <= icons:
        raise SystemExit(f"missing archived iPhone icons: {sorted(required - icons)}")
    ipad = set((info.get("CFBundleIcons~ipad") or {}).get("CFBundleAlternateIcons") or {})
    if 2 in info.get("UIDeviceFamily", []) and not required <= ipad:
        raise SystemExit(f"missing archived iPad icons: {sorted(required - ipad)}")
    print("==> Alternate icons verified: " + json.dumps({
        "archive": str(archive), "bundle": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
        "iphone": sorted(icons), "ipad": sorted(ipad),
    }, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify-alternate-icons.py ARCHIVE")
    verify(Path(sys.argv[1]))
