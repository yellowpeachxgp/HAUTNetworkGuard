#!/bin/sh
# HAUT Network Guard - OpenWrt 离线安装脚本

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_ROOT="${HAUT_SOURCE_ROOT:-$SCRIPT_DIR}"
ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac

INSTALL_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
INIT_FILE="$ROOT_PREFIX/etc/init.d/haut-network-guard"
CONFIG_FILE="$ROOT_PREFIX/etc/config/haut-network-guard"
SOURCE_DIR="$SOURCE_ROOT/files/usr/lib/haut-network-guard"
SOURCE_INIT="$SOURCE_ROOT/files/etc/init.d/haut-network-guard"
SOURCE_CONFIG="$SOURCE_ROOT/files/etc/config/haut-network-guard"
# 当前发布基线为 v1.3.18；安装提示从主程序版本字段读取。
VERSION=""
STAGE_DIR=""
INIT_STAGE=""
CONFIG_STAGE=""
OLD_INSTALL_DIR=""
OLD_INIT_FILE=""
PROGRAM_CREATED=0
INIT_CREATED=0
CONFIG_CREATED=0
INSTALL_COMMITTED=0

cleanup() {
    status=$?
    if [ "$INSTALL_COMMITTED" -ne 1 ]; then
        if [ -n "$OLD_INSTALL_DIR" ] && [ -d "$OLD_INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
            mv "$OLD_INSTALL_DIR" "$INSTALL_DIR" || true
        elif [ "$PROGRAM_CREATED" -eq 1 ]; then
            rm -rf "$INSTALL_DIR"
        fi
        if [ -n "$OLD_INIT_FILE" ] && [ -f "$OLD_INIT_FILE" ]; then
            rm -f "$INIT_FILE"
            mv "$OLD_INIT_FILE" "$INIT_FILE" || true
        elif [ "$INIT_CREATED" -eq 1 ]; then
            rm -f "$INIT_FILE"
        fi
        if [ "$CONFIG_CREATED" -eq 1 ]; then
            rm -f "$CONFIG_FILE"
        fi
    fi
    [ -n "$STAGE_DIR" ] && rm -rf "$STAGE_DIR"
    [ -n "$INIT_STAGE" ] && rm -f "$INIT_STAGE"
    [ -n "$CONFIG_STAGE" ] && rm -f "$CONFIG_STAGE"
    exit "$status"
}
trap cleanup EXIT

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 离线安装"
echo "=========================================="

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

echo "[1/5] 检查依赖..."
if ! command -v lua >/dev/null 2>&1; then
    echo "错误: 未安装 Lua，无法验证程序"
    exit 1
fi
if ! command -v cp >/dev/null 2>&1 || ! command -v mv >/dev/null 2>&1; then
    echo "错误: 缺少 cp 或 mv，无法安全安装"
    exit 1
fi

echo "[2/5] 准备临时目录..."
mkdir -p "$(dirname "$INSTALL_DIR")" "$(dirname "$INIT_FILE")" "$(dirname "$CONFIG_FILE")"
STAGE_DIR="$(mktemp -d "$(dirname "$INSTALL_DIR")/.haut-network-guard-install.XXXXXX")"
mkdir -p "$STAGE_DIR/program"

echo "[3/5] 校验并复制程序文件..."
for name in crypto.lua api.lua log.lua protocol.lua session.lua main.lua; do
    source="$SOURCE_DIR/$name"
    target="$STAGE_DIR/program/$name"
    if [ ! -s "$source" ]; then
        echo "错误: 缺少或为空的程序文件: $name"
        exit 1
    fi
    HAUT_VALIDATE_FILE="$source" lua -e 'assert(loadfile(os.getenv("HAUT_VALIDATE_FILE")))' </dev/null >/dev/null 2>&1 || {
        echo "错误: Lua 语法校验失败: $name"
        exit 1
    }
    cp "$source" "$target"
done
VERSION=$(sed -n 's/^local VERSION = "\([^"]*\)".*/\1/p' "$SOURCE_DIR/main.lua")
[ -n "$VERSION" ] || { echo "错误: 无法读取程序版本"; exit 1; }

echo "[4/5] 校验服务和配置..."
if [ ! -s "$SOURCE_INIT" ] || ! sh -n "$SOURCE_INIT"; then
    echo "错误: 服务脚本缺失或语法校验失败"
    exit 1
fi
INIT_STAGE="$STAGE_DIR/haut-network-guard.init"
cp "$SOURCE_INIT" "$INIT_STAGE"
chmod +x "$INIT_STAGE"
if [ -f "$CONFIG_FILE" ]; then
    echo "      检测到现有配置，保留 $CONFIG_FILE"
else
    if [ ! -s "$SOURCE_CONFIG" ]; then
        echo "错误: 默认配置文件缺失或为空"
        exit 1
    fi
    CONFIG_STAGE="$STAGE_DIR/haut-network-guard.config"
    cp "$SOURCE_CONFIG" "$CONFIG_STAGE"
    chmod 600 "$CONFIG_STAGE"
fi

echo "[5/5] 原子切换并启用服务..."
if [ -d "$INSTALL_DIR" ]; then
    OLD_INSTALL_DIR="${INSTALL_DIR}.backup.$$"
    mv "$INSTALL_DIR" "$OLD_INSTALL_DIR"
fi
mv "$STAGE_DIR/program" "$INSTALL_DIR"
PROGRAM_CREATED=1

if [ -f "$INIT_FILE" ]; then
    OLD_INIT_FILE="${INIT_FILE}.backup.$$"
    mv "$INIT_FILE" "$OLD_INIT_FILE"
fi
mv "$INIT_STAGE" "$INIT_FILE"
INIT_STAGE=""
INIT_CREATED=1

if [ -n "$CONFIG_STAGE" ]; then
    mv "$CONFIG_STAGE" "$CONFIG_FILE"
    CONFIG_STAGE=""
    CONFIG_CREATED=1
fi
chmod +x "$INIT_FILE"
[ -f "$CONFIG_FILE" ] && chmod 600 "$CONFIG_FILE"

"$INIT_FILE" enable >/dev/null 2>&1

INSTALL_COMMITTED=1
if [ -n "$OLD_INSTALL_DIR" ]; then
    rm -rf "$OLD_INSTALL_DIR" || echo "警告: 旧程序备份未清理: $OLD_INSTALL_DIR"
fi
if [ -n "$OLD_INIT_FILE" ]; then
    rm -f "$OLD_INIT_FILE" || echo "警告: 旧服务备份未清理: $OLD_INIT_FILE"
fi
OLD_INSTALL_DIR=""
OLD_INIT_FILE=""

echo ""
echo "=========================================="
echo "  安装完成! (v$VERSION)"
echo "=========================================="
echo "配置账号: uci set haut-network-guard.main.username='你的学号'"
echo "启动服务: /etc/init.d/haut-network-guard start"
