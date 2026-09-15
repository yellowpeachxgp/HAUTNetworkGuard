#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 安装脚本
# 用法: sudo ./install.sh

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$REPO_ROOT/OpenWrt/files/usr/lib/haut-network-guard"

INSTALL_DIR="/usr/lib/haut-network-guard"
CONFIG_FILE="/etc/haut-network-guard.conf"
SERVICE_FILE="/etc/systemd/system/haut-network-guard.service"

echo "=========================================="
echo "  HAUT Network Guard - Linux 安装"
echo "=========================================="

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行 (sudo ./install.sh)"
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 未找到 Lua 核心目录: $SRC_DIR"
    echo "请在仓库克隆目录内运行本脚本。"
    exit 1
fi

echo "[1/5] 检查依赖..."
if ! command -v lua5.1 >/dev/null 2>&1 && ! command -v lua >/dev/null 2>&1; then
    echo "      未检测到 Lua，尝试通过 apt 安装 lua5.1..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y || true
        apt-get install -y lua5.1
    else
        echo "      请手动安装 Lua 5.1 后重试。"
        exit 1
    fi
fi
if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        echo "      未检测到 curl，尝试安装..."
        apt-get install -y curl || true
    fi
fi

LUA_BIN=$(command -v lua5.1 || command -v lua)
echo "      使用 Lua: $LUA_BIN"

echo "[2/5] 安装核心文件到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp -f "$SRC_DIR"/*.lua "$INSTALL_DIR/"

echo "[3/5] 写入配置 $CONFIG_FILE ..."
if [ -f "$CONFIG_FILE" ]; then
    echo "      检测到现有配置，保留不覆盖"
else
    cp -f "$SCRIPT_DIR/config.example" "$CONFIG_FILE"
fi
chmod 600 "$CONFIG_FILE"

echo "[4/5] 安装 systemd 服务 ..."
sed "s#/usr/bin/lua5.1#$LUA_BIN#" "$SCRIPT_DIR/systemd/haut-network-guard.service" > "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

echo "[5/5] 启用服务 ..."
systemctl daemon-reload
systemctl enable haut-network-guard >/dev/null 2>&1 || true

cat <<'EOF'

==========================================
  安装完成!
==========================================

下一步:
  1. 编辑配置: nano /etc/haut-network-guard.conf  (填写 username / password)
  2. 启动服务: systemctl start haut-network-guard
  3. 查看日志: journalctl -u haut-network-guard -f
EOF
