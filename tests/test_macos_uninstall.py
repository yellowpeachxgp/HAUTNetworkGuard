#!/usr/bin/env python3
"""在临时路径验证 macOS 卸载脚本；不调用正式 launchctl、Keychain 或 defaults。"""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "macOS" / "uninstall.sh"


def write(path: Path, text: str, mode: int = 0o755):
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def run_case(fail_unload: bool):
    with tempfile.TemporaryDirectory(prefix="haut-macos-uninstall-") as raw:
        base = Path(raw)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        launch = base / "LaunchAgents" / "cn.ehaut.networkguard.plist"
        app = base / "HAUTNetworkGuard.app"
        launch.parent.mkdir()
        launch.write_text("plist", encoding="utf-8")
        app.mkdir()
        events = base / "events"
        write(bin_dir / "launchctl", "#!/bin/sh\nprintf 'launchctl:%s\\n' \"$*\" >> \"$HAUT_EVENTS\"\nif [ \"${HAUT_FAIL_UNLOAD:-0}\" = 1 ]; then exit 7; fi\nexit 0\n")
        write(bin_dir / "security", "#!/bin/sh\nprintf 'security:%s\\n' \"$*\" >> \"$HAUT_EVENTS\"\n")
        write(bin_dir / "defaults", "#!/bin/sh\nprintf 'defaults:%s\\n' \"$*\" >> \"$HAUT_EVENTS\"\n")
        env = os.environ.copy()
        env.update({
            "PATH": str(bin_dir) + os.pathsep + env["PATH"],
            "HAUT_LAUNCH_AGENT": str(launch),
            "HAUT_APP_PATH": str(app),
            "HAUT_KEYCHAIN_SERVICE": "test-service",
            "HAUT_KEYCHAIN_ACCOUNT": "test-account",
            "HAUT_CONFIG_DOMAIN": "test-domain",
            "HAUT_EVENTS": str(events),
            "HAUT_FAIL_UNLOAD": "1" if fail_unload else "0",
        })
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
        assert (result.returncode != 0) == fail_unload, result.stdout + result.stderr
        if fail_unload:
            assert launch.exists() and app.exists(), "停止失败时不得删除用户文件"
        else:
            assert not launch.exists() and not app.exists(), "成功卸载后残留文件"
            lines = events.read_text(encoding="utf-8").splitlines()
            assert lines[0].startswith("launchctl:"), lines
            assert any(line.startswith("security:") for line in lines), lines
            assert any(line.startswith("defaults:") for line in lines), lines


run_case(False)
run_case(True)
print("macOS uninstall script tests passed")
