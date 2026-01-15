#!/bin/sh
# HAUT Network Guard - OpenWrt 卸载脚本

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 卸载"
echo "=========================================="

# 停止服务
echo "[1/3] 停止服务..."
/etc/init.d/haut-network-guard stop 2>/dev/null
/etc/init.d/haut-network-guard disable 2>/dev/null

# 删除文件
echo "[2/3] 删除文件..."
rm -rf /usr/lib/haut-network-guard
rm -f /etc/init.d/haut-network-guard

# 删除配置 (可选)
echo "[3/3] 删除配置..."
rm -f /etc/config/haut-network-guard

echo ""
echo "卸载完成!"
