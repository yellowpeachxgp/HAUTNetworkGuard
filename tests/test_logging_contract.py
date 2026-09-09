#!/usr/bin/env python3
"""检查日志调用不会把凭据或完整网关正文重新带入输出。"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require_absent(text: str, needle: str, label: str):
    assert needle not in text, f"{label} 不得包含: {needle}"


def main():
    swift_api = (ROOT / "macOS/Sources/SrunAPI.swift").read_text(encoding="utf-8")
    swift_controller = (ROOT / "macOS/Sources/StatusBarController.swift").read_text(encoding="utf-8")
    cpp_api = (ROOT / "Windows/src/api.cpp").read_text(encoding="utf-8")
    cpp_window = (ROOT / "Windows/src/mainwindow.cpp").read_text(encoding="utf-8")
    lua_api = (ROOT / "OpenWrt/files/usr/lib/haut-network-guard/api.lua").read_text(encoding="utf-8")
    lua_main = (ROOT / "OpenWrt/files/usr/lib/haut-network-guard/main.lua").read_text(encoding="utf-8")

    require_absent(swift_api, "password=\\(password)", "macOS API 日志")
    require_absent(swift_api, "enc_password=\\(encryptedPassword)", "macOS API 日志")
    require_absent(swift_controller, "password=\\(config.password)", "macOS 控制器日志")
    require_absent(cpp_api, '.arg(password).', "Windows API 日志")
    require_absent(cpp_api, '.arg(encPassword).', "Windows API 日志")
    require_absent(cpp_window, '.arg(password).', "Windows 窗口日志")
    require_absent(cpp_window, '.arg(m_passwordEdit->text()).', "Windows 窗口日志")
    require_absent(lua_api, "password=%s", "OpenWrt API 日志")
    require_absent(lua_api, "enc_password=%s", "OpenWrt API 日志")
    require_absent(lua_main, "password=%s", "OpenWrt 主循环日志")

    require_absent(swift_api, "Logger.debug(\"登录响应", "macOS 原始响应日志")
    require_absent(cpp_api, 'Logger::debug(QString("登录响应: %1")', "Windows 原始响应日志")

    for path, marker in (
        (ROOT / "macOS/Sources/SrunProtocol.swift", "<redacted>"),
        (ROOT / "Windows/src/protocol_utils.cpp", "<redacted>"),
        (ROOT / "OpenWrt/files/usr/lib/haut-network-guard/log.lua", "<redacted>"),
    ):
        require_absent(path.read_text(encoding="utf-8"), "return response", f"{path} 响应返回")
        assert marker in path.read_text(encoding="utf-8"), f"{path} 缺少脱敏摘要标记"

    print("logging contract ok")


if __name__ == "__main__":
    main()
