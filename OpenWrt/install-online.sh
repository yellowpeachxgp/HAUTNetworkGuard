#!/bin/sh
# HAUT Network Guard - OpenWrt 一键安装脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.18/OpenWrt/install-online.sh | sh -s -- v1.3.18

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac
INSTALL_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
INIT_FILE="$ROOT_PREFIX/etc/init.d/haut-network-guard"
CONFIG_FILE="$ROOT_PREFIX/etc/config/haut-network-guard"
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
    [ -n "$INIT_STAGE" ] && rm -f "$INIT_STAGE" "$INIT_STAGE.tmp"
    [ -n "$CONFIG_STAGE" ] && rm -f "$CONFIG_STAGE" "$CONFIG_STAGE.tmp"
    exit "$status"
}

trap cleanup EXIT

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

validate_program_dir() {
    dir="$1"
    for file in crypto.lua api.lua log.lua protocol.lua main.lua; do
        if [ ! -s "$dir/$file" ]; then
            echo "错误: 缺少或为空的程序文件: $file"
            return 1
        fi
        if command -v lua >/dev/null 2>&1; then
            HAUT_VALIDATE_FILE="$dir/$file" lua -e 'assert(loadfile(os.getenv("HAUT_VALIDATE_FILE")))' </dev/null >/dev/null 2>&1 || {
                echo "错误: Lua 语法校验失败: $file"
                return 1
            }
        else
            echo "错误: 未安装 Lua，无法验证程序"
            return 1
        fi
    done
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 一键安装"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建同文件系统临时目录，完成全部下载后再切换
echo "[2/5] 准备临时目录..."
mkdir -p "$(dirname "$INSTALL_DIR")"
STAGE_DIR="$(mktemp -d "$(dirname "$INSTALL_DIR")/.haut-network-guard-install.XXXXXX")"

# 下载文件
echo "[3/5] 下载程序文件..."
mkdir -p "$STAGE_DIR/program"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/crypto.lua" "$STAGE_DIR/program/crypto.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/api.lua" "$STAGE_DIR/program/api.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/log.lua" "$STAGE_DIR/program/log.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/protocol.lua" "$STAGE_DIR/program/protocol.lua"
download_file "$REPO_URL/files/usr/lib/haut-network-guard/main.lua" "$STAGE_DIR/program/main.lua"

echo "[4/5] 下载配置文件..."
INIT_STAGE="$ROOT_PREFIX/etc/init.d/.haut-network-guard.$$"
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "$INIT_STAGE"
if [ -f "$CONFIG_FILE" ]; then
    echo "      检测到现有配置，保留 /etc/config/haut-network-guard"
else
    CONFIG_STAGE="$ROOT_PREFIX/etc/config/.haut-network-guard.$$"
    download_file "$REPO_URL/files/etc/config/haut-network-guard" "$CONFIG_STAGE"
fi

# 校验临时文件后切换程序目录和服务脚本
echo "[5/5] 设置权限..."
validate_program_dir "$STAGE_DIR/program"
test -s "$INIT_STAGE"
sh -n "$INIT_STAGE"
chmod +x "$INIT_STAGE"

if [ -d "$INSTALL_DIR" ]; then
    OLD_INSTALL_DIR="${INSTALL_DIR}.backup.$$"
    mv "$INSTALL_DIR" "$OLD_INSTALL_DIR"
fi
mv "$STAGE_DIR/program" "$INSTALL_DIR"
PROGRAM_CREATED=1

if [ -f "$INIT_FILE" ]; then
    OLD_INIT_FILE="$INIT_FILE.backup.$$"
    mv "$INIT_FILE" "$OLD_INIT_FILE"
fi
mv "$INIT_STAGE" "$INIT_FILE"
INIT_STAGE=""
INIT_CREATED=1

if [ -n "$CONFIG_STAGE" ]; then
    chmod 600 "$CONFIG_STAGE"
    mv "$CONFIG_STAGE" "$CONFIG_FILE"
    CONFIG_STAGE=""
    CONFIG_CREATED=1
fi

chmod +x "$INIT_FILE"
[ -f "$CONFIG_FILE" ] && chmod 600 "$CONFIG_FILE"

# 启用服务
"$INIT_FILE" enable >/dev/null 2>&1

# 服务启用成功即提交；清理旧备份失败不能回退或删除已安装的新程序。
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
echo "  安装完成! (v1.3.18)"
echo "=========================================="
echo ""
echo "下一步 - 配置账号:"
echo ""
echo "  uci set haut-network-guard.main.username='你的学号'"
echo "  uci set haut-network-guard.main.password='你的密码'"
echo "  uci commit haut-network-guard"
echo "  /etc/init.d/haut-network-guard start"
echo ""
echo "查看日志: logread | grep haut-network-guard"
echo ""
