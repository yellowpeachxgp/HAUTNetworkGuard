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
    cmake = (ROOT / "Windows" / "CMakeLists.txt").read_text(encoding="utf-8")
    assert 'file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../VERSION" HAUT_VERSION' in cmake
    for path in (ROOT / "Windows" / "src" / "main.cpp",
                 ROOT / "Windows" / "src" / "api.cpp",
                 ROOT / "Windows" / "src" / "mainwindow.cpp"):
        content = path.read_text(encoding="utf-8")
        assert "HAUT_VERSION_STRING" in content, f"{path} must consume generated version"
    require_version(ROOT / "macOS" / "Info.plist", r"<key>CFBundleShortVersionString</key>\s*<string>([0-9.]+)</string>")
    require_version(ROOT / "macOS" / "Sources" / "Config.swift", r'static let version = "([0-9.]+)"')
    require_version(ROOT / "OpenWrt" / "files" / "usr" / "lib" / "haut-network-guard" / "version.lua", r'return "([0-9.]+)"')
    for path in (ROOT / "OpenWrt" / "files" / "usr" / "lib" / "haut-network-guard" / "main.lua",
                 ROOT / "OpenWrt" / "files" / "usr" / "lib" / "haut-network-guard" / "api.lua"):
        assert 'require("version")' in path.read_text(encoding="utf-8"), f"{path} must consume version.lua"

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
