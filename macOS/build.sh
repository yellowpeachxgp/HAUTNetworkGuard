#!/bin/bash

# HAUT Network Guard 构建脚本
# 用于编译和打包 macOS 菜单栏应用

set -e

echo "=========================================="
echo "  HAUT Network Guard 构建脚本"
echo "=========================================="

# 项目目录
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="HAUTNetworkGuard"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# 清理旧构建
echo "[1/4] 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 编译 Swift 源文件
echo "[2/4] 编译 Swift 源文件..."
swiftc \
    -o "$BUILD_DIR/$APP_NAME" \
    -framework Cocoa \
    -framework UserNotifications \
    "$SOURCES_DIR/Config.swift" \
    "$SOURCES_DIR/Encryption.swift" \
    "$SOURCES_DIR/SrunAPI.swift" \
    "$SOURCES_DIR/UpdateChecker.swift" \
    "$SOURCES_DIR/UpdateWindow.swift" \
    "$SOURCES_DIR/SettingsWindow.swift" \
    "$SOURCES_DIR/AboutWindow.swift" \
    "$SOURCES_DIR/LaunchManager.swift" \
    "$SOURCES_DIR/StatusBarController.swift" \
    "$SOURCES_DIR/AppDelegate.swift" \
    "$SOURCES_DIR/main.swift"

# 创建 .app bundle
echo "[3/4] 创建应用包..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 复制 Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# 创建 PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "[4/4] 构建完成!"
echo ""
echo "应用位置: $APP_BUNDLE"
echo ""
echo "运行方式:"
echo "  1. 双击 $APP_BUNDLE 启动"
echo "  2. 或在终端运行: open \"$APP_BUNDLE\""
echo ""
echo "=========================================="
