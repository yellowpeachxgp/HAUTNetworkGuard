#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 卸载脚本
# 用法: sudo ./uninstall.sh [--purge-config]

set -e

PURGE_CONFIG=0
if [ "$1" = "--purge-config" ]; then
    PURGE_CONFIG=1
fi

INSTALL_DIR="/usr/lib/haut-network-guard"
CONFIG_FILE="/etc/haut-network-guard.conf"
SERVICE_FILE="/etc/systemd/system/haut-network-guard.service"

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行 (sudo ./uninstall.sh)"
    exit 1
fi

echo "[1/4] 停止并禁用服务..."
systemctl stop haut-network-guard 2>/dev/null || true
systemctl disable haut-network-guard 2>/dev/null || true

echo "[2/4] 移除 systemd 服务..."
rm -f "$SERVICE_FILE"
systemctl daemon-reload 2>/dev/null || true

echo "[3/4] 移除程序文件..."
rm -rf "$INSTALL_DIR"

echo "[4/4] 处理配置..."
if [ "$PURGE_CONFIG" = "1" ]; then
    rm -f "$CONFIG_FILE"
    echo "      配置已删除: $CONFIG_FILE"
else
    echo "      配置已保留: $CONFIG_FILE (如需删除请加 --purge-config)"
fi

echo "卸载完成"
