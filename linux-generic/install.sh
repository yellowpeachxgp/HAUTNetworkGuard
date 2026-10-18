#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 安装脚本
# 用法: sudo ./linux-generic/install.sh
#
# 测试/容器场景可设置：
#   HAUT_ROOT=/tmp/root          安装到临时根目录
#   HAUT_SOURCE_ROOT=/path/repo  指定包含 OpenWrt/ 的源码根目录
#   HAUT_SYSTEMCTL=/path/fake    替换 systemctl 命令
#   HAUT_LUA=/path/lua           指定 Lua 解释器

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_ROOT="${HAUT_SOURCE_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}"
ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac

INSTALL_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
CONFIG_FILE="$ROOT_PREFIX/etc/haut-network-guard.conf"
SERVICE_FILE="$ROOT_PREFIX/etc/systemd/system/haut-network-guard.service"
SOURCE_DIR="$SOURCE_ROOT/OpenWrt/files/usr/lib/haut-network-guard"
SYSTEMCTL="${HAUT_SYSTEMCTL:-systemctl}"
LUA_BIN=""

STAGE_DIR=""
OLD_INSTALL_DIR=""
OLD_SERVICE_FILE=""
PROGRAM_CREATED=0
SERVICE_CREATED=0
CONFIG_CREATED=0
WAS_RUNNING=0
COMMITTED=0

cleanup() {
    status=$?
    if [ "$COMMITTED" -ne 1 ]; then
        if [ "$WAS_RUNNING" -eq 1 ] && command -v "$SYSTEMCTL" >/dev/null 2>&1; then
            "$SYSTEMCTL" stop haut-network-guard >/dev/null 2>&1 || true
        fi
        if [ -n "$OLD_INSTALL_DIR" ] && [ -d "$OLD_INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
            mv "$OLD_INSTALL_DIR" "$INSTALL_DIR" || true
        elif [ "$PROGRAM_CREATED" -eq 1 ]; then
            rm -rf "$INSTALL_DIR"
        fi
        if [ -n "$OLD_SERVICE_FILE" ] && [ -f "$OLD_SERVICE_FILE" ]; then
            rm -f "$SERVICE_FILE"
            mv "$OLD_SERVICE_FILE" "$SERVICE_FILE" || true
        elif [ "$SERVICE_CREATED" -eq 1 ]; then
            rm -f "$SERVICE_FILE"
        fi
        if [ "$CONFIG_CREATED" -eq 1 ]; then
            rm -f "$CONFIG_FILE"
        fi
        if command -v "$SYSTEMCTL" >/dev/null 2>&1; then
            "$SYSTEMCTL" daemon-reload >/dev/null 2>&1 || true
            if [ "$WAS_RUNNING" -eq 1 ]; then
                "$SYSTEMCTL" start haut-network-guard >/dev/null 2>&1 || true
            fi
        fi
    fi
    [ -n "$STAGE_DIR" ] && rm -rf "$STAGE_DIR"
    exit "$status"
}
trap cleanup EXIT

find_lua() {
    if [ -n "${HAUT_LUA:-}" ]; then
        printf '%s\n' "$HAUT_LUA"
        return 0
    fi
    for candidate in lua5.1 lua5.3 lua5.4 lua; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

validate_lua() {
    file="$1"
    HAUT_VALIDATE_FILE="$file" "$LUA_BIN" -e 'assert(loadfile(os.getenv("HAUT_VALIDATE_FILE")))' \
        </dev/null >/dev/null 2>&1 || {
        echo "错误: Lua 语法校验失败: $file"
        return 1
    }
}

echo "=========================================="
echo "  HAUT Network Guard - 通用 Linux 安装"
echo "=========================================="

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行 (sudo ./linux-generic/install.sh)"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "错误: 未找到 Lua 核心目录: $SOURCE_DIR"
    echo "请在仓库克隆目录内运行，或设置 HAUT_SOURCE_ROOT。"
    exit 1
fi

echo "[1/6] 检查依赖..."
if ! LUA_BIN=$(find_lua); then
    echo "错误: 未找到 Lua 5.1+，请先安装（例如 apt-get install -y lua5.1）。"
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "错误: 未找到 curl，请先安装（例如 apt-get install -y curl）。"
    exit 1
fi
if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    echo "错误: 未找到 systemctl，当前系统可能未使用 systemd。"
    exit 1
fi
echo "      Lua: $LUA_BIN"
echo "      systemctl: $SYSTEMCTL"

VERSION=$(sed -n 's/^return "\([^"]*\)".*/\1/p' "$SOURCE_DIR/version.lua" 2>/dev/null || true)
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "错误: 无法读取有效程序版本"
    exit 1
fi

echo "[2/6] 准备临时目录..."
mkdir -p "$(dirname "$INSTALL_DIR")" "$(dirname "$CONFIG_FILE")" "$(dirname "$SERVICE_FILE")"
STAGE_DIR=$(mktemp -d "$(dirname "$INSTALL_DIR")/.haut-network-guard-install.XXXXXX")
mkdir -p "$STAGE_DIR/program"

echo "[3/6] 校验并复制程序文件..."
for name in version.lua crypto.lua api.lua log.lua protocol.lua session.lua config.lua main.lua; do
    source="$SOURCE_DIR/$name"
    target="$STAGE_DIR/program/$name"
    if [ ! -s "$source" ]; then
        echo "错误: 缺少或为空的程序文件: $name"
        exit 1
    fi
    validate_lua "$source"
    cp "$source" "$target"
done
chmod 755 "$STAGE_DIR/program"
chmod 644 "$STAGE_DIR/program"/*.lua

echo "[4/6] 生成 systemd 服务..."
SERVICE_TEMPLATE="$SCRIPT_DIR/systemd/haut-network-guard.service"
if [ ! -s "$SERVICE_TEMPLATE" ]; then
    echo "错误: systemd 服务模板缺失: $SERVICE_TEMPLATE"
    exit 1
fi
sed -e "s|@LUA@|$LUA_BIN|g" -e "s|@INSTALL_DIR@|$INSTALL_DIR|g" \
    "$SERVICE_TEMPLATE" > "$STAGE_DIR/haut-network-guard.service"
if ! grep -q '^ExecStart=' "$STAGE_DIR/haut-network-guard.service"; then
    echo "错误: systemd 服务模板缺少 ExecStart"
    exit 1
fi
chmod 644 "$STAGE_DIR/haut-network-guard.service"

if [ -f "$CONFIG_FILE" ]; then
    echo "[5/6] 检测到现有配置，保留 $CONFIG_FILE"
else
    echo "[5/6] 写入默认配置..."
    if [ ! -s "$SCRIPT_DIR/config.example" ]; then
        echo "错误: 配置模板缺失: $SCRIPT_DIR/config.example"
        exit 1
    fi
    cp "$SCRIPT_DIR/config.example" "$STAGE_DIR/haut-network-guard.conf"
    chmod 600 "$STAGE_DIR/haut-network-guard.conf"
fi

echo "[6/6] 原子切换并启用服务..."
if "$SYSTEMCTL" is-active --quiet haut-network-guard >/dev/null 2>&1; then
    WAS_RUNNING=1
    if ! "$SYSTEMCTL" stop haut-network-guard; then
        echo "错误: 停止旧服务失败，已保留原安装"
        exit 1
    fi
fi

if [ -d "$INSTALL_DIR" ]; then
    OLD_INSTALL_DIR="$INSTALL_DIR.backup.$$"
    mv "$INSTALL_DIR" "$OLD_INSTALL_DIR"
fi
mv "$STAGE_DIR/program" "$INSTALL_DIR"
PROGRAM_CREATED=1

if [ -f "$SERVICE_FILE" ]; then
    OLD_SERVICE_FILE="$SERVICE_FILE.backup.$$"
    mv "$SERVICE_FILE" "$OLD_SERVICE_FILE"
fi
mv "$STAGE_DIR/haut-network-guard.service" "$SERVICE_FILE"
SERVICE_CREATED=1

if [ -f "$STAGE_DIR/haut-network-guard.conf" ]; then
    mv "$STAGE_DIR/haut-network-guard.conf" "$CONFIG_FILE"
    CONFIG_CREATED=1
fi
chmod 600 "$CONFIG_FILE"

if ! "$SYSTEMCTL" daemon-reload; then
    echo "错误: systemctl daemon-reload 失败"
    exit 1
fi
if ! "$SYSTEMCTL" enable haut-network-guard >/dev/null; then
    echo "错误: 启用 haut-network-guard 服务失败"
    exit 1
fi
if [ "$WAS_RUNNING" -eq 1 ]; then
    if ! "$SYSTEMCTL" start haut-network-guard; then
        echo "错误: 启动 haut-network-guard 服务失败"
        exit 1
    fi
    attempt=0
    while [ "$attempt" -lt 5 ]; do
        if "$SYSTEMCTL" is-active --quiet haut-network-guard; then break; fi
        attempt=$((attempt + 1))
        sleep 1
    done
    if ! "$SYSTEMCTL" is-active --quiet haut-network-guard; then
        echo "错误: 服务启动后未进入运行状态"
        exit 1
    fi
fi

COMMITTED=1
if [ -n "$OLD_INSTALL_DIR" ]; then
    rm -rf "$OLD_INSTALL_DIR" || echo "警告: 旧程序备份未清理: $OLD_INSTALL_DIR"
fi
if [ -n "$OLD_SERVICE_FILE" ]; then
    rm -f "$OLD_SERVICE_FILE" || echo "警告: 旧服务备份未清理: $OLD_SERVICE_FILE"
fi

echo ""
echo "=========================================="
echo "  安装完成! (v$VERSION)"
echo "=========================================="
echo ""
echo "下一步:"
echo "  1. 编辑配置: nano $CONFIG_FILE"
echo "  2. 启动服务: $SYSTEMCTL start haut-network-guard"
echo "  3. 查看日志: journalctl -u haut-network-guard -f"
