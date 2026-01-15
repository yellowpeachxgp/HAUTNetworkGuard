#!/bin/bash

# HAUT Network Guard DMG 打包脚本

set -e

echo "=========================================="
echo "  HAUT Network Guard DMG 打包脚本"
echo "=========================================="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="HAUTNetworkGuard"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
VOLUME_NAME="HAUT Network Guard"
TMP_DMG="$BUILD_DIR/tmp.dmg"

# 检查应用是否已构建
if [ ! -d "$APP_BUNDLE" ]; then
    echo "应用尚未构建，先执行构建..."
    ./build.sh
fi

# 清理旧的 DMG
rm -f "$DMG_PATH"
rm -f "$TMP_DMG"

echo ""
echo "[1/4] 创建临时 DMG..."
# 创建临时目录
TMP_DIR="$BUILD_DIR/dmg_temp"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 复制应用到临时目录
cp -R "$APP_BUNDLE" "$TMP_DIR/"

# 移除扩展属性，避免 Gatekeeper 标记为"已损坏"
xattr -cr "$TMP_DIR/$APP_NAME.app"

# 创建 Applications 快捷方式
ln -s /Applications "$TMP_DIR/Applications"

echo "[2/4] 创建 DMG 镜像..."
# 创建 DMG
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov -format UDRW \
    "$TMP_DMG"

echo "[3/4] 转换为压缩 DMG..."
# 转换为压缩格式
hdiutil convert "$TMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

echo "[4/4] 清理临时文件..."
rm -rf "$TMP_DIR"
rm -f "$TMP_DMG"

echo ""
echo "=========================================="
echo "  DMG 打包完成!"
echo "=========================================="
echo ""
echo "DMG 文件: $DMG_PATH"
echo "文件大小: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
