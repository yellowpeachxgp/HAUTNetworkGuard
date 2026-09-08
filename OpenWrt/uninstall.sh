#!/bin/sh
# HAUT Network Guard - OpenWrt 卸载脚本

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 卸载"
echo "=========================================="

PURGE_CONFIG=0
if [ "${1:-}" = "--purge-config" ]; then
    PURGE_CONFIG=1
fi

# 停止服务
echo "[1/3] 停止服务..."
/etc/init.d/haut-network-guard stop 2>/dev/null
/etc/init.d/haut-network-guard disable 2>/dev/null

# 删除文件
echo "[2/3] 删除文件..."
rm -rf /usr/lib/haut-network-guard
rm -f /etc/init.d/haut-network-guard

# 删除配置 (可选)
echo "[3/3] 处理配置..."
if [ "$PURGE_CONFIG" = "1" ]; then
    rm -f /etc/config/haut-network-guard
    echo "      已删除 /etc/config/haut-network-guard"
else
    echo "      保留 /etc/config/haut-network-guard"
    echo "      如需一并删除，请使用: ./uninstall.sh --purge-config"
fi

echo ""
echo "卸载完成!"
