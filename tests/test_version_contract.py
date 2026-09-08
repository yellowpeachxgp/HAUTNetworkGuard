#!/usr/bin/env python3

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
assert re.fullmatch(r"\d+\.\d+\.\d+", VERSION), f"invalid VERSION: {VERSION!r}"


def require_version(path: Path, pattern: str):
    content = path.read_text(encoding="utf-8")
    match = re.search(pattern, content)
    assert match, f"{path} missing version pattern: {pattern}"
    assert match.group(1) == VERSION, (
        f"{path} version drift: expected {VERSION}, got {match.group(1)}"
    )


def main():
    require_version(ROOT / "Windows" / "CMakeLists.txt", r"project\(HAUTNetworkGuard VERSION ([0-9.]+)")
    require_version(ROOT / "Windows" / "src" / "main.cpp", r'app\.setApplicationVersion\("([0-9.]+)"\)')
    require_version(ROOT / "Windows" / "src" / "api.cpp", r'HAUTNetworkGuard/([0-9.]+) Qt')
    require_version(ROOT / "Windows" / "src" / "mainwindow.cpp", r'HAUT Network Guard v([0-9.]+)')
    require_version(ROOT / "macOS" / "Info.plist", r"<key>CFBundleShortVersionString</key>\s*<string>([0-9.]+)</string>")
    require_version(ROOT / "macOS" / "Sources" / "Config.swift", r'static let version = "([0-9.]+)"')
    require_version(ROOT / "OpenWrt" / "files" / "usr" / "lib" / "haut-network-guard" / "main.lua", r'local VERSION = "([0-9.]+)"')
    require_version(ROOT / "OpenWrt" / "files" / "usr" / "lib" / "haut-network-guard" / "api.lua", r'HAUTNetworkGuard/([0-9.]+) OpenWrt')

    for path in (
        ROOT / "README.md",
        ROOT / "OpenWrt" / "README.md",
        ROOT / "OpenWrt" / "install.sh",
        ROOT / "OpenWrt" / "install-online.sh",
        ROOT / "OpenWrt" / "upgrade-online.sh",
        ROOT / "Windows" / "AIREADME.md",
        ROOT / "macOS" / "AIREADME.md",
    ):
        content = path.read_text(encoding="utf-8")
        assert VERSION in content, f"{path} missing current version {VERSION}"

    print("version contract ok")


if __name__ == "__main__":
    main()
