#!/bin/bash
# HAUT Network Guard macOS 卸载脚本

set -euo pipefail

LAUNCH_AGENT="${HAUT_LAUNCH_AGENT:-$HOME/Library/LaunchAgents/cn.ehaut.networkguard.plist}"
APP_PATH="${HAUT_APP_PATH:-/Applications/HAUTNetworkGuard.app}"
KEYCHAIN_SERVICE="${HAUT_KEYCHAIN_SERVICE:-cn.ehaut.networkguard}"
KEYCHAIN_ACCOUNT="${HAUT_KEYCHAIN_ACCOUNT:-default}"
CONFIG_DOMAIN="${HAUT_CONFIG_DOMAIN:-cn.ehaut.networkguard}"

fail() {
    echo "错误: $*" >&2
    exit 1
}

printf '%s\n' "==========================================" \
    "  HAUT Network Guard macOS 卸载" \
    "=========================================="

echo "[1/4] 停止服务..."
if [[ -e "$LAUNCH_AGENT" ]]; then
    launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || fail "无法停止 LaunchAgent: $LAUNCH_AGENT"
fi

echo "[2/4] 清理本地凭据..."
if command -v security >/dev/null 2>&1; then
    if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
        security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1 \
            || fail "无法删除 Keychain 凭据，请解锁钥匙串后重试"
    else
        find_status=$?
        # security 对“条目不存在”返回 errSecItemNotFound=44；其他错误可能表示钥匙串锁定或不可用。
        [[ "$find_status" -eq 44 ]] || fail "无法确认 Keychain 凭据状态，请解锁钥匙串后重试"
    fi
fi
if command -v defaults >/dev/null 2>&1; then
    defaults delete "$CONFIG_DOMAIN" >/dev/null 2>&1 || true
fi

rm -f "$LAUNCH_AGENT"

echo "[3/4] 删除应用..."
rm -rf "$APP_PATH"

if [[ -e "$LAUNCH_AGENT" ]]; then
    fail "LaunchAgent 删除后仍存在: $LAUNCH_AGENT"
fi
if [[ -e "$APP_PATH" ]]; then
    fail "应用删除后仍存在: $APP_PATH"
fi

echo "[4/4] 完成"
echo "卸载完成；Keychain 凭据和应用配置已请求清理。"
