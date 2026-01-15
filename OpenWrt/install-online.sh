#!/bin/sh
# HAUT Network Guard - OpenWrt 一键安装脚本
# 用法: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh

set -e

REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt"
INSTALL_DIR="/usr/lib/haut-network-guard"

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 一键安装"
echo "=========================================="
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl openssl-util >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建目录
echo "[2/5] 创建目录..."
mkdir -p "$INSTALL_DIR"

# 下载文件
echo "[3/5] 下载程序文件..."
curl -sL "$REPO_URL/files/usr/lib/haut-network-guard/crypto.lua" -o "$INSTALL_DIR/crypto.lua"
curl -sL "$REPO_URL/files/usr/lib/haut-network-guard/api.lua" -o "$INSTALL_DIR/api.lua"
curl -sL "$REPO_URL/files/usr/lib/haut-network-guard/main.lua" -o "$INSTALL_DIR/main.lua"

echo "[4/5] 下载配置文件..."
curl -sL "$REPO_URL/files/etc/init.d/haut-network-guard" -o "/etc/init.d/haut-network-guard"
curl -sL "$REPO_URL/files/etc/config/haut-network-guard" -o "/etc/config/haut-network-guard"

# 设置权限
echo "[5/5] 设置权限..."
chmod +x /etc/init.d/haut-network-guard
chmod 600 /etc/config/haut-network-guard

# 启用服务
/etc/init.d/haut-network-guard enable >/dev/null 2>&1

echo ""
echo "=========================================="
echo "  安装完成!"
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
