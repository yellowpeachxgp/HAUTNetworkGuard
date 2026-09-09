#!/usr/bin/env python3
"""在临时根目录执行正式安装脚本；Lua 用真实解释器，其余设备边界注入。"""

import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
requested_lua = os.environ.get("HAUT_TEST_LUA", "lua")
requested_path = Path(requested_lua).expanduser()
LUA = str(requested_path.resolve()) if requested_path.exists() else shutil.which(requested_lua)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        if not LUA:
            self.fail("必须提供真实 Lua，示例：HAUT_TEST_LUA=lua5.3")
        self.temp = tempfile.TemporaryDirectory(prefix="haut-install-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "host root"
        self.remote = self.base / "remote"
        self.bin = self.base / "bin"
        self.program = self.root / "usr/lib/haut-network-guard"
        self.init = self.root / "etc/init.d/haut-network-guard"
        self.config = self.root / "etc/config/haut-network-guard"
        for path in (self.program.parent, self.init.parent, self.config.parent,
                     self.root / "tmp", self.bin):
            path.mkdir(parents=True, exist_ok=True)
        self.env = dict(os.environ)
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HAUT_ROOT": str(self.root), "HAUT_FAKE_REMOTE": str(self.remote),
            "HAUT_FAKE_EVENTS": str(self.base / "events"),
            "HAUT_FAKE_RUNNING": str(self.base / "running"),
            "HAUT_FAKE_ENABLED": str(self.base / "enabled"),
            "HAUT_REAL_MV": shutil.which("mv"),
            "HAUT_REAL_RM": shutil.which("rm"),
        })
        (self.bin / "lua").symlink_to(LUA)
        self.write(self.bin / "id", '#!/bin/sh\nprintf "0\\n"\n', executable=True)
        self.write(self.bin / "opkg", "#!/bin/sh\nexit 0\n", executable=True)
        self.write(self.bin / "sleep", "#!/bin/sh\nexit 0\n", executable=True)
        self.write(self.bin / "rm", "#!" + sys.executable + r'''
import os, subprocess, sys
if os.environ.get("HAUT_FAIL_BACKUP_CLEANUP") == "1" and any(".backup." in a for a in sys.argv[1:]):
    sys.exit(73)
sys.exit(subprocess.call([os.environ["HAUT_REAL_RM"], *sys.argv[1:]]))
''', executable=True)
        self.write(self.bin / "curl", "#!" + sys.executable + r'''
import os, pathlib, sys
args = iter(sys.argv[1:])
url = output = None
for arg in args:
    if arg == "-o": output = next(args)
    elif arg in ("--connect-timeout", "--max-time"): next(args)
    elif arg.startswith("https://"): url = arg
if "/releases/download/" in url:
    relative = "OpenWrt-SHA256SUMS"
else:
    relative = url.split("/OpenWrt/", 1)[1]
if os.environ.get("HAUT_FAIL_DOWNLOAD") == relative:
    if output: pathlib.Path(output).write_text("partial")
    sys.exit(22)
data = (pathlib.Path(os.environ["HAUT_FAKE_REMOTE"]) / relative).read_bytes()
if output: pathlib.Path(output).write_bytes(data)
else: sys.stdout.buffer.write(data)
''', executable=True)
        self.write(self.bin / "mv", "#!" + sys.executable + r'''
import os, pathlib, subprocess, sys
args = sys.argv[1:]
if os.environ.get("HAUT_FAIL_MOVE") == "1":
    source, target = pathlib.Path(args[-2]), pathlib.Path(args[-1])
    if source.name.startswith(".haut-network-guard.") and target.name == "haut-network-guard":
        sys.exit(71)
sys.exit(subprocess.call([os.environ["HAUT_REAL_MV"], *args]))
''', executable=True)
        self.write(self.remote / "files/usr/lib/haut-network-guard/version.lua",
                   'return "1.3.18"\n')
        for name in ("crypto.lua", "api.lua", "log.lua", "protocol.lua", "session.lua"):
            self.write(self.remote / "files/usr/lib/haut-network-guard" / name,
                       'error("语法检查不得执行模块")\nreturn {}\n')
        self.write(self.remote / "files/usr/lib/haut-network-guard/main.lua",
                   'local VERSION = "1.3.18"\nerror("语法检查不得启动守护程序")\n')
        self.write(self.remote / "files/etc/init.d/haut-network-guard", self.service("new"))
        self.write(self.remote / "files/etc/config/haut-network-guard", "config main\n")
        manifest = []
        for path in sorted(self.remote.rglob("*")):
            if path.is_file():
                relative = path.relative_to(self.remote).as_posix()
                if relative.startswith("files/") or relative.endswith(".sh"):
                    digest = hashlib.sha256(path.read_bytes()).hexdigest()
                    manifest.append(f"{digest}  OpenWrt/{relative}")
        self.write(self.remote / "OpenWrt-SHA256SUMS", "\n".join(manifest) + "\n")

    def write(self, path, content, executable=False):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755 if executable else 0o644)

    def service(self, version):
        return '#!/bin/sh\nVERSION="' + version + r'''"
printf '%s:%s\n' "$VERSION" "$1" >> "$HAUT_FAKE_EVENTS"
    case "$1" in
    enable)
        if [ "$VERSION" = new ] && [ "$HAUT_FAIL_ENABLE" = 1 ]; then exit 1; fi
        printf enabled > "$HAUT_FAKE_ENABLED" ;;
    disable) rm -f "$HAUT_FAKE_ENABLED" ;;
    start)
        if [ "$VERSION" = new ] && [ "$HAUT_FAIL_START" = 1 ]; then exit 1; fi
        printf running > "$HAUT_FAKE_RUNNING" ;;
    stop)
        if [ "$HAUT_FAIL_STOP" = 1 ]; then exit 72; fi
        rm -f "$HAUT_FAKE_RUNNING" ;;
    status)
        if [ "$VERSION" = new ] && [ "$HAUT_FAIL_HEALTH" = 1 ]; then exit 1; fi
        test -f "$HAUT_FAKE_RUNNING" ;;
    *) exit 2 ;;
esac
'''

    def seed_old(self, running=True):
        self.write(self.program / "version.lua", 'return "0.9.0"\n')
        for name in ("crypto.lua", "api.lua", "log.lua", "protocol.lua", "session.lua"):
            self.write(self.program / name, "return { old = true }\n")
        self.write(self.program / "main.lua", 'local VERSION = "0.9.0"\n')
        self.write(self.init, self.service("old"), executable=True)
        self.write(self.config, "config main\n    option password 'test-only'\n")
        self.config.chmod(0o600)
        if running:
            Path(self.env["HAUT_FAKE_RUNNING"]).touch()

    def snapshot(self):
        return {
            str(p.relative_to(self.root)): (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
            for p in self.root.rglob("*") if p.is_file()
        }

    def run_script(self, script, success=True, ref="v1.3.18"):
        result = subprocess.run(["sh", str(ROOT / "OpenWrt" / script), ref],
                                env=self.env, cwd=ROOT, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def run_local_script(self, success=True):
        env = dict(self.env)
        env["HAUT_SOURCE_ROOT"] = str(self.remote)
        result = subprocess.run(["sh", str(ROOT / "OpenWrt" / "install.sh")],
                                env=env, cwd=ROOT, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def run_uninstall(self, script="uninstall.sh", purge=False, success=True):
        env = dict(self.env)
        args = ["sh", str(ROOT / "OpenWrt" / script)]
        if purge:
            args.append("--purge-config")
        result = subprocess.run(args, env=env, cwd=ROOT,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def events(self):
        path = Path(self.env["HAUT_FAKE_EVENTS"])
        return path.read_text().splitlines() if path.exists() else []

    def assert_no_temporary_files(self):
        residue = [str(p) for p in self.root.rglob("*")
                   if ".backup." in p.name or p.name.startswith(".haut-") or p.suffix == ".tmp"]
        self.assertEqual(residue, [], "安装失败或成功后不应遗留临时文件")

    def test_fresh_install(self):
        self.run_script("install-online.sh")
        self.assertEqual(self.events(), ["new:enable"])

    def test_fresh_install_creates_missing_system_directories(self):
        shutil.rmtree(self.root / "etc")
        shutil.rmtree(self.root / "tmp")
        self.run_script("install-online.sh")
        self.assertEqual(self.events(), ["new:enable"])
        self.assertTrue(self.init.is_file())
        self.assertTrue(self.config.is_file())
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertTrue(os.access(self.init, os.X_OK))
        self.assertEqual((self.program / "main.lua").read_bytes(),
                         (self.remote / "files/usr/lib/haut-network-guard/main.lua").read_bytes())
        self.assert_no_temporary_files()

    def test_tag_version_mismatch_is_rejected(self):
        version_file = self.remote / "files/usr/lib/haut-network-guard/version.lua"
        version_file.write_text('return "1.3.19"\n')
        result = self.run_script("install-online.sh", False)
        self.assertIn("tag 与程序版本不一致", result.stdout)
        self.assert_no_temporary_files()

    def test_upgrade_tag_version_mismatch_is_rejected(self):
        self.seed_old()
        version_file = self.remote / "files/usr/lib/haut-network-guard/version.lua"
        version_file.write_text('return "1.3.19"\n')
        result = self.run_script("upgrade-online.sh", False)
        self.assertIn("tag 与远端程序版本不一致", result.stdout)
        self.assertEqual(self.events(), [])
        self.assertEqual((self.program / "version.lua").read_text(), 'return "0.9.0"\n')

    def test_reinstall_preserves_config(self):
        self.seed_old()
        old_config = self.config.read_bytes()
        self.run_script("install-online.sh")
        self.assertEqual(self.config.read_bytes(), old_config)
        self.assert_no_temporary_files()

    def test_local_fresh_install_is_atomic(self):
        self.run_local_script()
        self.assertEqual(self.events(), ["new:enable"])
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertTrue(os.access(self.init, os.X_OK))
        self.assertEqual((self.program / "main.lua").read_bytes(),
                         (self.remote / "files/usr/lib/haut-network-guard/main.lua").read_bytes())
        self.assert_no_temporary_files()

    def test_local_enable_failure_restores_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_ENABLE"] = "1"
        self.run_local_script(False)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_temporary_files()

    def test_local_uninstall_preserves_config_by_default(self):
        self.seed_old()
        self.run_uninstall()
        self.assertFalse(self.program.exists())
        self.assertFalse(self.init.exists())
        self.assertTrue(self.config.exists())
        self.assertIn("old:stop", self.events())
        self.assertIn("old:disable", self.events())

    def test_online_uninstall_purge_removes_config(self):
        self.seed_old()
        self.run_uninstall("uninstall-online.sh", purge=True)
        self.assertFalse(self.program.exists())
        self.assertFalse(self.init.exists())
        self.assertFalse(self.config.exists())

    def test_uninstall_stop_failure_keeps_install(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_STOP"] = "1"
        self.run_uninstall(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_failed_download_keeps_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_DOWNLOAD"] = "files/usr/lib/haut-network-guard/api.lua"
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.events(), [])

    def test_partial_init_download_is_removed(self):
        self.env["HAUT_FAIL_DOWNLOAD"] = "files/etc/init.d/haut-network-guard"
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), {})
        self.assert_no_temporary_files()

    def test_invalid_lua_keeps_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.write(self.remote / "files/usr/lib/haut-network-guard/api.lua", "not valid !")
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)

    def test_checksum_mismatch_keeps_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.write(self.remote / "files/usr/lib/haut-network-guard/api.lua", "tampered\n")
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.events(), [])

    def test_missing_release_manifest_keeps_install_and_service(self):
        self.seed_old()
        before = self.snapshot()
        (self.remote / "OpenWrt-SHA256SUMS").unlink()
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.events(), [])
        self.run_script("upgrade-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.events(), [])

    def test_upgrade_checksum_mismatch_keeps_old_service(self):
        self.seed_old()
        before = self.snapshot()
        self.write(self.remote / "files/usr/lib/haut-network-guard/api.lua", "tampered\n")
        self.run_script("upgrade-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.events(), [])

    def test_enable_failure_rolls_back_existing(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_ENABLE"] = "1"
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)

    def test_enable_failure_removes_fresh_install(self):
        self.env["HAUT_FAIL_ENABLE"] = "1"
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), {})

    def test_commit_failure_restores_old_install(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_MOVE"] = "1"
        self.run_script("install-online.sh", False)
        self.assertEqual(self.snapshot(), before)

    def test_upgrade_success_preserves_config(self):
        self.seed_old()
        before = self.config.read_bytes()
        self.run_script("upgrade-online.sh")
        self.assertEqual(before, self.config.read_bytes())
        self.assertIn("new:status", self.events())
        self.assertTrue(Path(self.env["HAUT_FAKE_RUNNING"]).exists())
        self.assert_no_temporary_files()

    def test_upgrade_creates_missing_custom_tmp_directory(self):
        self.seed_old()
        shutil.rmtree(self.root / "tmp")
        self.run_script("upgrade-online.sh")
        self.assertIn("new:status", self.events())
        self.assertTrue((self.root / "tmp").is_dir())
        self.assert_no_temporary_files()

    def test_backup_cleanup_failure_keeps_new_install(self):
        self.seed_old()
        self.env["HAUT_FAIL_BACKUP_CLEANUP"] = "1"
        self.run_script("install-online.sh")
        self.assertEqual((self.program / "main.lua").read_bytes(),
                         (self.remote / "files/usr/lib/haut-network-guard/main.lua").read_bytes())
        self.assertIn('VERSION="new"', self.init.read_text())
        self.assertTrue(list(self.program.parent.glob("*.backup.*")))

    def test_upgrade_keeps_stopped_service_stopped(self):
        self.seed_old(running=False)
        self.run_script("upgrade-online.sh")
        self.assertFalse(Path(self.env["HAUT_FAKE_RUNNING"]).exists())
        self.assertNotIn("new:start", self.events())

    def test_upgrade_download_failure_does_not_stop_service(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_DOWNLOAD"] = "files/usr/lib/haut-network-guard/api.lua"
        self.run_script("upgrade-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn("old:stop", self.events())

    def test_upgrade_health_failure_restores_old_service(self):
        self.seed_old()
        before = self.snapshot()
        self.env["HAUT_FAIL_HEALTH"] = "1"
        self.run_script("upgrade-online.sh", False)
        self.assertEqual(self.snapshot(), before)
        self.assertIn("old:start", self.events())
        self.assertTrue(Path(self.env["HAUT_FAKE_RUNNING"]).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
