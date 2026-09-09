#!/usr/bin/env python3
"""通过隔离的 rc.common/uci 运行 OpenWrt diagnose 行为回归。"""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INIT = ROOT / "OpenWrt/files/etc/init.d/haut-network-guard"
SHELL = "/bin/sh"


class DiagnoseTests(unittest.TestCase):
    def run_diagnose(
        self,
        values=None,
        commands=("lua", "curl", "uci"),
        service_state="running",
        dispatcher="new",
    ):
        values = values or {}
        with tempfile.TemporaryDirectory(prefix="haut-diagnose-") as directory:
            base = Path(directory)
            bin_dir = base / "bin"
            bin_dir.mkdir()
            program = base / "main.lua"
            program.write_text("-- test program\n", encoding="utf-8")
            call_log = base / "calls.log"

            for name in commands:
                path = bin_dir / name
                if name == "uci":
                    script = r'''#!/bin/sh
printf 'uci:%s\n' "$*" >> "$HAUT_CALL_LOG"
case "${3-}" in
  haut-network-guard.main.enabled) printf '%s\n' "${HAUT_UCI_ENABLED-}" ;;
  haut-network-guard.main.username) printf '%s\n' "${HAUT_UCI_USERNAME-}" ;;
  haut-network-guard.main.password) printf '%s\n' "${HAUT_UCI_PASSWORD-}" ;;
  haut-network-guard.main.interval) printf '%s\n' "${HAUT_UCI_INTERVAL-}" ;;
  haut-network-guard.main.log_level) printf '%s\n' "${HAUT_UCI_LOG_LEVEL-}" ;;
  *) exit 1 ;;
esac
'''
                else:
                    # 依赖命令只要被真正执行就留下记录；正常 diagnose 不应执行它们。
                    script = r'''#!/bin/sh
printf '%s:%s\n' "$0" "$*" >> "$HAUT_CALL_LOG"
exit 0
'''
                path.write_text(script, encoding="utf-8")
                path.chmod(0o755)

            # 模拟新版 rc.common 的 extra_command 注册及命令分发。
            if dispatcher == "new":
                rc_script = r'''#!/bin/sh
initscript="$1"
action="${2:-help}"
shift 2
ALL_COMMANDS="start stop restart"
extra_command() { ALL_COMMANDS="$ALL_COMMANDS $1"; }
service_running() {
    case "${HAUT_SERVICE_STATE:-unknown}" in
        running) return 0 ;;
        stopped) return 1 ;;
        *) return 2 ;;
    esac
}
. "$initscript"
case " $ALL_COMMANDS " in
    *" $action "*) ;;
    *) printf 'unknown action: %s\n' "$action" >&2; exit 2 ;;
esac
"$action" "$@"
'''
            else:
                # 模拟仍使用 EXTRA_COMMANDS 的旧版 rc.common。
                rc_script = r'''#!/bin/sh
initscript="$1"
action="${2:-help}"
shift 2
ALL_COMMANDS="start stop restart"
service_running() {
    case "${HAUT_SERVICE_STATE:-unknown}" in
        running) return 0 ;;
        stopped) return 1 ;;
        *) return 2 ;;
    esac
}
. "$initscript"
ALL_COMMANDS="$ALL_COMMANDS ${EXTRA_COMMANDS:-}"
case " $ALL_COMMANDS " in
    *" $action "*) ;;
    *) printf 'unknown action: %s\n' "$action" >&2; exit 2 ;;
esac
"$action" "$@"
'''
            rc_common = base / "rc.common"
            rc_common.write_text(rc_script, encoding="utf-8")
            rc_common.chmod(0o755)

            # 替换运行文件路径，避免触碰主机 /usr/lib；通过 /bin/sh 直接调用
            # 隔离 dispatcher，PATH 可完全收窄以验证缺依赖分支。
            init_script = INIT.read_text(encoding="utf-8").replace(
                "PROG=/usr/lib/haut-network-guard/main.lua",
                f"PROG={shlex.quote(str(program))}",
            )
            init_copy = base / "haut-network-guard.init"
            init_copy.write_text(init_script, encoding="utf-8")
            init_copy.chmod(0o755)

            env = {
                "PATH": str(bin_dir),
                "HAUT_CALL_LOG": str(call_log),
                "HAUT_SERVICE_STATE": service_state,
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
            }
            env.update(
                {
                    "HAUT_UCI_ENABLED": str(values.get("enabled", "")),
                    "HAUT_UCI_USERNAME": str(values.get("username", "")),
                    "HAUT_UCI_PASSWORD": str(values.get("password", "")),
                    "HAUT_UCI_INTERVAL": str(values.get("interval", "")),
                    "HAUT_UCI_LOG_LEVEL": str(values.get("log_level", "")),
                }
            )
            result = subprocess.run(
                [SHELL, str(rc_common), str(init_copy), "diagnose"],
                env=env,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=5,
            )
            calls = call_log.read_text(encoding="utf-8").splitlines() if call_log.exists() else []
            return result, calls

    def test_valid_configuration_uses_dispatcher_and_never_executes_network_tools(self):
        result, calls = self.run_diagnose(
            {"username": "student-account", "password": "secret", "interval": "60", "log_level": "info"}
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("结果: 通过", result.stdout)
        self.assertIn("[通过] 服务状态: 正在运行", result.stdout)
        self.assertNotIn("student-account", result.stdout + result.stderr)
        self.assertNotIn("secret", result.stdout + result.stderr)
        self.assertEqual(len(calls), 5)
        self.assertTrue(all(line.startswith("uci:") for line in calls), calls)

    def test_invalid_configuration_reports_service_dependency_and_safe_hints(self):
        account = "student-account-123"
        password = "super-secret"
        result, calls = self.run_diagnose(
            {
                "enabled": "maybe",
                "username": account,
                "password": password,
                "interval": "999999999999999999999",
                "log_level": "password=should-not-echo",
            },
            commands=("uci",),
            service_state="stopped",
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[失败] 缺少依赖: lua", output)
        self.assertIn("[失败] 缺少依赖: curl", output)
        self.assertIn("[失败] 服务状态: 未运行，请执行 start", output)
        self.assertIn("登录功能配置: 值无效", output)
        self.assertIn("检测间隔: 值过大", output)
        self.assertIn("日志级别无效", output)
        self.assertIn("结果: 发现问题", output)
        self.assertNotIn(account, output)
        self.assertNotIn(password, output)
        self.assertNotIn("should-not-echo", output)
        self.assertEqual(len(calls), 5)

    def test_missing_uci_is_reported_without_misleading_credential_checks(self):
        result, calls = self.run_diagnose(
            commands=("lua", "curl"),
            service_state="unknown",
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[失败] 配置: 无法读取 UCI", output)
        self.assertIn("[提示] 服务状态: 未知（无法查询 procd）", output)
        self.assertNotIn("用户名: 未配置", output)
        self.assertNotIn("密码: 未配置", output)
        self.assertEqual(calls, [])

    def test_disabled_login_is_a_hint_and_old_dispatcher_registers_command(self):
        result, calls = self.run_diagnose(
            {"enabled": "0", "username": "student", "password": "secret", "interval": "30"},
            dispatcher="old",
            service_state="stopped",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("登录功能配置: 已禁用", result.stdout)
        self.assertIn("服务状态: 未运行（登录功能已禁用）", result.stdout)
        self.assertIn("结果: 通过", result.stdout)
        self.assertNotIn("student", result.stdout)
        self.assertNotIn("secret", result.stdout)
        self.assertEqual(len(calls), 5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
