#!/usr/bin/env python3
"""在临时目录编译正式会话策略，重放共用事件；不访问网络和用户配置。"""
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)


def main():
    fixture = ROOT / "tests/fixtures/session_scenarios.txt"
    with tempfile.TemporaryDirectory(prefix="haut-session-") as directory:
        output = Path(directory)
        cpp = output / "cpp-session-tests"
        run(os.environ.get("CXX", "c++"), "-std=c++17", "-Wall", "-Wextra", "-Werror",
            ROOT / "Windows/tests/session_policy_tests.cpp", "-o", cpp)
        run(cpp, fixture)
        if platform.system() == "Darwin":
            swift = output / "swift-session-tests"
            sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
            run("xcrun", "--sdk", "macosx", "swiftc", "-sdk", sdk, "-o", swift,
                ROOT / "macOS/Sources/SessionPolicy.swift",
                ROOT / "macOS/tests/SessionPolicyTests.swift")
            run(swift, fixture)


if __name__ == "__main__":
    main()
