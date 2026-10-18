#!/usr/bin/env python3
"""在临时根目录执行通用 Linux 安装/卸载脚本，注入 systemctl/curl/id 边界。"""

import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
requested_lua = os.environ.get("HAUT_TEST_LUA", "lua")
requested_path = Path(requested_lua).expanduser()
LUA = str(requested_path.resolve()) if requested_path.exists() else shutil.which(requested_lua)


class LinuxGenericInstallationTests(unittest.TestCase):
    def setUp(self):
        if not LUA:
            self.fail("必须提供真实 Lua，示例：HAUT_TEST_LUA=lua5.1")
        self.temp = tempfile.TemporaryDirectory(prefix="haut-linux-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "host root"
        self.bin = self.base / "bin"
        self.remote = self.base / "remote"
        self.program = self.root / "usr/lib/haut-network-guard"
        self.config = self.root / "etc/haut-network-guard.conf"
        self.service = self.root / "etc/systemd/system/haut-network-guard.service"
        self.events = self.base / "events"
        self.running = self.base / "running"
        self.enabled = self.base / "enabled"
        for path in (self.program.parent, self.config.parent, self.service.parent,
                     self.bin, self.remote):
            path.mkdir(parents=True, exist_ok=True)
        self.env = dict(os.environ)
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HAUT_ROOT": str(self.root),
            "HAUT_SYSTEMCTL": str(self.bin / "systemctl"),
            "HAUT_LUA": LUA,
            "HAUT_SOURCE_ROOT": str(ROOT),
            "HAUT_FAKE_EVENTS": str(self.events),
            "HAUT_FAKE_RUNNING": str(self.running),
            "HAUT_FAKE_ENABLED": str(self.enabled),
            "HAUT_FAKE_REMOTE": str(self.remote),
        })
        self.write(self.bin / "id", '#!/bin/sh\nprintf "0\\n"\n', executable=True)
        self.write(self.bin / "sleep", "#!/bin/sh\nexit 0\n", executable=True)
        self.write(self.bin / "systemctl", """#!/bin/sh
set -u
printf '%s\\n' "$*" >> "$HAUT_FAKE_EVENTS"
case "$1" in
    daemon-reload)
        test "${HAUT_FAIL_DAEMON_RELOAD:-0}" = 1 && exit 1
        exit 0 ;;
    is-active)
        test -f "$HAUT_FAKE_RUNNING" ;;
    start)
        test "${HAUT_FAIL_START:-0}" = 1 && exit 1
        : > "$HAUT_FAKE_RUNNING" ;;
    stop)
        test "${HAUT_FAIL_STOP:-0}" = 1 && exit 1
        rm -f "$HAUT_FAKE_RUNNING" ;;
    enable)
        test "${HAUT_FAIL_ENABLE:-0}" = 1 && exit 1
        : > "$HAUT_FAKE_ENABLED" ;;
    disable)
        rm -f "$HAUT_FAKE_ENABLED" ;;
    *)
        exit 2 ;;
esac
""", executable=True)
        self.write(self.bin / "curl", "#!" + sys.executable + r'''
import os, pathlib, sys
args = sys.argv[1:]
url = output = None
i = 0
while i < len(args):
    if args[i] == "-o":
        output = args[i + 1]; i += 2; continue
    if args[i] in ("--connect-timeout", "--max-time"):
        i += 2; continue
    if args[i].startswith("https://"):
        url = args[i]
    i += 1
remote = pathlib.Path(os.environ["HAUT_FAKE_REMOTE"])
if url.endswith("/HAUTNetworkGuard-Linux.tar.gz"):
    source = remote / "HAUTNetworkGuard-Linux.tar.gz"
elif url.endswith("/SHA256SUMS"):
    source = remote / "SHA256SUMS"
elif url.endswith("/main.tar.gz"):
    source = remote / "main.tar.gz"
else:
    sys.exit(22)
if os.environ.get("HAUT_FAIL_DOWNLOAD") == source.name:
    if output: pathlib.Path(output).write_text("partial")
    sys.exit(22)
data = source.read_bytes()
if output: pathlib.Path(output).write_bytes(data)
else: sys.stdout.buffer.write(data)
''', executable=True)

    def write(self, path, content, executable=False):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755 if executable else 0o644)

    def run_script(self, name, args=(), success=True, env=None):
        script = ROOT / "linux-generic" / name
        merged = dict(self.env)
        if env:
            merged.update(env)
        result = subprocess.run(["sh", str(script), *args], env=merged, cwd=ROOT,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {
            str(p.relative_to(self.root)): (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
            for p in self.root.rglob("*") if p.is_file()
        }

    def assert_no_temporary_files(self):
        residue = [str(p) for p in self.root.rglob("*")
                   if ".backup." in p.name or ".removing." in p.name
                   or p.name.startswith(".haut-") or p.suffix == ".tmp"]
        self.assertEqual(residue, [], "安装/卸载后不应遗留临时文件")

    def seed_old(self, running=True):
        self.write(self.program / "version.lua", 'return "0.9.0"\n')
        for name in ("crypto.lua", "api.lua", "log.lua", "protocol.lua",
                     "session.lua", "config.lua"):
            self.write(self.program / name, "return { old = true }\n")
        self.write(self.program / "main.lua", 'local VERSION = "0.9.0"\n')
        self.write(self.service, "[Service]\nExecStart=/bin/true\n")
        self.write(self.config, "username=old-user\npassword=old-pass\n")
        self.config.chmod(0o600)
        if running:
            self.running.touch()

    def assert_installed(self):
        for name in ("version.lua", "crypto.lua", "api.lua", "log.lua",
                     "protocol.lua", "session.lua", "config.lua", "main.lua"):
            self.assertTrue((self.program / name).is_file(), f"缺少程序文件: {name}")
        self.assertTrue(self.service.is_file())
        self.assertIn("ExecStart=", self.service.read_text())
        self.assertIn(str(self.program / "main.lua"), self.service.read_text())
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assert_no_temporary_files()

    def make_release_tarball(self, version=VERSION):
        stage = self.base / "release-stage/HAUTNetworkGuard-Linux"
        shutil.copytree(ROOT / "OpenWrt/files", stage / "OpenWrt/files")
        shutil.copytree(ROOT / "linux-generic", stage / "linux-generic")
        (stage / "VERSION").write_text(version + "\n")
        version_file = stage / "OpenWrt/files/usr/lib/haut-network-guard/version.lua"
        version_file.write_text(f'return "{version}"\n')
        shutil.copy2(ROOT / "README.md", stage / "README.md")
        archive = self.remote / "HAUTNetworkGuard-Linux.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(stage, arcname="HAUTNetworkGuard-Linux")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.write(self.remote / "SHA256SUMS",
                   f"{digest}  HAUTNetworkGuard-Linux.tar.gz\n")

    def make_main_tarball(self):
        stage = self.base / "main-stage/HAUTNetworkGuard-main"
        shutil.copytree(ROOT / "OpenWrt/files", stage / "OpenWrt/files")
        shutil.copytree(ROOT / "linux-generic", stage / "linux-generic")
        shutil.copy2(ROOT / "VERSION", stage / "VERSION")
        archive = self.remote / "main.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(stage, arcname="HAUTNetworkGuard-main")

    def test_local_fresh_install(self):
        self.run_script("install.sh")
        self.assert_installed()
        events = self.events.read_text()
        self.assertIn("daemon-reload", events)
        self.assertIn("enable haut-network-guard", events)
        self.assertNotIn("start haut-network-guard", events)
        self.assertFalse(self.running.exists(), "安装不应擅自启动服务")

    def test_reinstall_preserves_config(self):
        self.seed_old()
        old_config = self.config.read_bytes()
        self.run_script("install.sh")
        self.assertEqual(self.config.read_bytes(), old_config)
        self.assert_installed()
        self.assertIn("daemon-reload", self.events.read_text())
        self.assertIn("start haut-network-guard", self.events.read_text())

    def test_enable_failure_rolls_back_fresh_install(self):
        result = self.run_script("install.sh", success=False,
                                 env={"HAUT_FAIL_ENABLE": "1"})
        self.assertIn("错误", result.stdout + result.stderr)
        self.assertFalse(self.program.exists())
        self.assertFalse(self.service.exists())
        self.assertFalse(self.config.exists())
        self.assert_no_temporary_files()

    def test_enable_failure_restores_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.run_script("install.sh", success=False, env={"HAUT_FAIL_ENABLE": "1"})
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(self.running.exists(), "回滚后应恢复原服务运行状态")
        self.assert_no_temporary_files()

    def test_stop_failure_keeps_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.run_script("install.sh", success=False, env={"HAUT_FAIL_STOP": "1"})
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(self.running.exists())

    def test_start_failure_restores_old_files(self):
        self.seed_old()
        before = self.snapshot()
        self.run_script("install.sh", success=False, env={"HAUT_FAIL_START": "1"})
        self.assertEqual(self.snapshot(), before)
        self.assert_no_temporary_files()

    def test_daemon_reload_failure_rolls_back(self):
        self.seed_old()
        before = self.snapshot()
        self.run_script("install.sh", success=False,
                        env={"HAUT_FAIL_DAEMON_RELOAD": "1"})
        self.assertEqual(self.snapshot(), before)

    def test_uninstall_preserves_config_by_default(self):
        self.seed_old()
        self.run_script("uninstall.sh")
        self.assertFalse(self.program.exists())
        self.assertFalse(self.service.exists())
        self.assertTrue(self.config.exists())
        events = self.events.read_text()
        self.assertIn("stop haut-network-guard", events)
        self.assertIn("disable haut-network-guard", events)

    def test_uninstall_purge_removes_config(self):
        self.seed_old()
        self.run_script("uninstall.sh", args=("--purge-config",))
        self.assertFalse(self.config.exists())

    def test_uninstall_stop_failure_keeps_install(self):
        self.seed_old()
        before = self.snapshot()
        self.run_script("uninstall.sh", success=False, env={"HAUT_FAIL_STOP": "1"})
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(self.running.exists())

    def test_online_release_install_and_checksum(self):
        self.make_release_tarball()
        self.run_script("install-online.sh", args=(f"v{VERSION}",))
        self.assert_installed()
        self.assertIn("enable haut-network-guard", self.events.read_text())

    def test_online_release_checksum_mismatch(self):
        self.make_release_tarball()
        self.write(self.remote / "SHA256SUMS",
                   "0" * 64 + "  HAUTNetworkGuard-Linux.tar.gz\n")
        result = self.run_script("install-online.sh", args=(f"v{VERSION}",), success=False)
        self.assertIn("校验失败", result.stdout)
        self.assertFalse(self.program.exists())

    def test_online_release_version_mismatch(self):
        self.make_release_tarball(version="9.9.9")
        result = self.run_script("install-online.sh", args=(f"v{VERSION}",), success=False)
        self.assertIn("tag 与程序版本不一致", result.stdout)
        self.assertFalse(self.program.exists())

    def test_online_main_install(self):
        self.make_main_tarball()
        self.run_script("install-online.sh")
        self.assert_installed()

    def test_invalid_ref_is_rejected(self):
        for ref in ("v1.3", f"v{VERSION}/../../evil", "feature/branch"):
            result = self.run_script("install-online.sh", args=(ref,), success=False)
            self.assertIn("错误", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
