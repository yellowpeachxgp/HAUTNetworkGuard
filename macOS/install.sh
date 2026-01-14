#!/bin/bash

# HAUT Network Guard 安装脚本

set -e

echo "=========================================="
echo "  HAUT Network Guard 安装脚本"
echo "=========================================="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/HAUTNetworkGuard.app"
INSTALL_DIR="/Applications"
LAUNCH_AGENT_SRC="$PROJECT_DIR/cn.ehaut.networkguard.plist"
LAUNCH_AGENT_DST="$HOME/Library/LaunchAgents/cn.ehaut.networkguard.plist"

# 检查是否已构建
if [ ! -d "$APP_BUNDLE" ]; then
    echo "错误: 应用尚未构建，请先运行 ./build.sh"
    exit 1
fi

echo ""
echo "[1/3] 复制应用到 /Applications..."
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
echo "      完成"

echo ""
echo "[2/3] 安装开机自启配置..."
mkdir -p "$HOME/Library/LaunchAgents"
cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST"
echo "      完成"

echo ""
echo "[3/3] 加载 LaunchAgent..."
launchctl unload "$LAUNCH_AGENT_DST" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_DST"
echo "      完成"

echo ""
echo "=========================================="
echo "  安装完成!"
echo "=========================================="
echo ""
echo "应用已安装到: $INSTALL_DIR/HAUTNetworkGuard.app"
echo "开机自启已配置"
echo ""
echo "现在可以在菜单栏看到网络状态图标"
echo ""
