#!/bin/sh
# HAUT Network Guard - OpenWrt 一键卸载脚本
# 用法: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/uninstall-online.sh | sh

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 卸载"
echo "=========================================="

# 停止并禁用服务
echo "[1/3] 停止服务..."
/etc/init.d/haut-network-guard stop 2>/dev/null
/etc/init.d/haut-network-guard disable 2>/dev/null

# 删除文件
echo "[2/3] 删除程序文件..."
rm -rf /usr/lib/haut-network-guard
rm -f /etc/init.d/haut-network-guard

# 删除配置
echo "[3/3] 删除配置..."
rm -f /etc/config/haut-network-guard

echo ""
echo "卸载完成!"
