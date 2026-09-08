#!/usr/bin/env python3

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require_contains(path: Path, needle: str):
    content = path.read_text(encoding="utf-8")
    assert needle in content, f"{path} missing: {needle}"


def require_not_contains(path: Path, needle: str):
    content = path.read_text(encoding="utf-8")
    assert needle not in content, f"{path} still contains stale text: {needle}"


def main():
    readme = ROOT / "README.md"
    openwrt_readme = ROOT / "OpenWrt" / "README.md"
    windows_ai = ROOT / "Windows" / "AIREADME.md"
    macos_ai = ROOT / "macOS" / "AIREADME.md"
    logging_contract = ROOT / "docs" / "LOGGING_CONTRACT.md"
    protocol_spec = ROOT / "docs" / "SRUN3K_PROTOCOL_SPEC.md"
    state_machine = ROOT / "docs" / "STATE_MACHINE_CONTRACT.md"
    ledger = ROOT / "docs" / "IMPLEMENTATION_LEDGER.md"

    require_contains(readme, "HAUTNetworkGuard-Windows.zip")
    require_contains(readme, "HAUTNetworkGuard.dmg")
    require_contains(readme, "sh -s -- v1.3.18")
    require_contains(readme, "protocol_utils.h/cpp")
    require_contains(readme, "SrunProtocol.swift")
    require_contains(readme, "tests/")
    require_contains(readme, "SHA256SUMS")
    require_not_contains(readme, "HAUTNetworkGuard-Windows.exe")
    require_not_contains(readme, "HAUTNetworkGuard-macOS.dmg")

    require_contains(openwrt_readme, "HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh")
    require_contains(openwrt_readme, "HAUTNetworkGuard/v1.3.18/OpenWrt/install-online.sh | sh -s -- v1.3.18")
    require_contains(openwrt_readme, "upgrade-online.sh | sh")
    require_contains(openwrt_readme, "log.lua")
    require_contains(openwrt_readme, "../docs/LOGGING_CONTRACT.md")
    require_contains(openwrt_readme, "权限为 `600`")
    require_contains(openwrt_readme, "OpenWrt-SHA256SUMS")

    require_contains(windows_ai, "版本号**: 1.3.18")
    require_contains(windows_ai, "172.16.154.130")
    require_contains(windows_ai, "protocol_utils.cpp")
    require_not_contains(windows_ai, "172.20.255.2")
    require_not_contains(windows_ai, "版本号**: 1.3.0")

    require_contains(macos_ai, "版本号**: 1.3.18")
    require_contains(macos_ai, "run_ui_smoke_tests.sh")
    require_contains(macos_ai, "Logger.swift")
    require_contains(macos_ai, "SrunProtocol.swift")
    require_contains(macos_ai, "172.16.154.130")
    require_contains(macos_ai, "Keychain")
    require_contains(macos_ai, "卸载脚本会删除")
    require_not_contains(macos_ai, "版本号**: 1.1.4")
    require_contains(windows_ai, "DPAPI")

    require_contains(logging_contract, "error_E####")
    require_contains(logging_contract, "online_jsonp")
    require_contains(logging_contract, "<redacted>")
    require_contains(protocol_spec, "error_E####")
    require_contains(protocol_spec, "Windows/tests/windows_smoke_tests.cpp")
    require_contains(protocol_spec, "学生可理解的提示")
    require_contains(state_machine, "手动离线保持")
    require_contains(state_machine, "error` 不等于 `offline")
    require_contains(ledger, "当前环境阻塞")
    require_contains(ledger, "M5-03 升级健康检查")
    require_contains(ledger, "M5-02 原子在线安装")
    require_contains(ledger, "日志脱敏")
    require_contains(ROOT / "docs" / "VALIDATION_2026-09-08.md", "实际执行正式 Shell 脚本和真实 Lua")

    print("docs contract ok")


if __name__ == "__main__":
    main()
