#!/bin/sh
# HAUT Network Guard - OpenWrt 一键卸载脚本
# 用法: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/uninstall-online.sh | sh

set -e
ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac
INIT_FILE="$ROOT_PREFIX/etc/init.d/haut-network-guard"
PROGRAM_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
CONFIG_FILE="$ROOT_PREFIX/etc/config/haut-network-guard"

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

PURGE_CONFIG=0
case "${1:-}" in
    "") ;;
    --purge-config) PURGE_CONFIG=1 ;;
    *) echo "用法: $0 [--purge-config]"; exit 2 ;;
esac

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 卸载"
echo "=========================================="
echo "[1/3] 停止并禁用服务..."
if [ -e "$INIT_FILE" ]; then
    "$INIT_FILE" stop
    "$INIT_FILE" disable
else
    echo "      服务脚本不存在，跳过"
fi

echo "[2/3] 删除程序文件..."
rm -rf "$PROGRAM_DIR"
rm -f "$INIT_FILE"

echo "[3/3] 处理配置..."
if [ "$PURGE_CONFIG" = "1" ]; then
    rm -f "$CONFIG_FILE"
    echo "      已删除配置"
else
    echo "      保留配置：$CONFIG_FILE"
    echo "      如需一并删除，请追加: sh -s -- --purge-config"
fi

echo "卸载完成"
