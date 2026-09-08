#!/bin/bash

# HAUT Network Guard 卸载脚本

echo "=========================================="
echo "  HAUT Network Guard 卸载脚本"
echo "=========================================="

LAUNCH_AGENT="$HOME/Library/LaunchAgents/cn.ehaut.networkguard.plist"
APP_PATH="/Applications/HAUTNetworkGuard.app"

echo ""
echo "[1/4] 停止服务..."
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
echo "      完成"

echo ""
echo "[2/4] 删除 LaunchAgent 配置..."
rm -f "$LAUNCH_AGENT"
echo "      完成"

echo ""
echo "[3/4] 清理本地凭据..."
/usr/bin/security delete-generic-password \
    -s "cn.ehaut.networkguard" \
    -a "default" 2>/dev/null || true
defaults delete "cn.ehaut.networkguard" 2>/dev/null || true
echo "      完成"

echo "[4/4] 删除应用..."
rm -rf "$APP_PATH"
echo "      完成"

echo ""
echo "=========================================="
echo "  卸载完成!"
echo "=========================================="
