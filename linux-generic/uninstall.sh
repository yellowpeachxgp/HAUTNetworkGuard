#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 卸载脚本
# 用法: sudo ./linux-generic/uninstall.sh [--purge-config]

set -eu

ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac
SYSTEMCTL="${HAUT_SYSTEMCTL:-systemctl}"

INSTALL_DIR="$ROOT_PREFIX/usr/lib/haut-network-guard"
CONFIG_FILE="$ROOT_PREFIX/etc/haut-network-guard.conf"
SERVICE_FILE="$ROOT_PREFIX/etc/systemd/system/haut-network-guard.service"

PURGE_CONFIG=0
case "${1:-}" in
    "") ;;
    --purge-config) PURGE_CONFIG=1 ;;
    *) echo "用法: $0 [--purge-config]"; exit 2 ;;
esac

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行 (sudo ./linux-generic/uninstall.sh)"
    exit 1
fi

echo "=========================================="
echo "  HAUT Network Guard - 通用 Linux 卸载"
echo "=========================================="

echo "[1/4] 停止并禁用服务..."
if command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    if "$SYSTEMCTL" is-active --quiet haut-network-guard >/dev/null 2>&1; then
        "$SYSTEMCTL" stop haut-network-guard
    fi
    "$SYSTEMCTL" disable haut-network-guard >/dev/null 2>&1 || true
else
    echo "      未找到 systemctl，跳过服务管理"
fi

echo "[2/4] 移除 systemd 服务..."
rm -f "$SERVICE_FILE"
if command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    "$SYSTEMCTL" daemon-reload >/dev/null 2>&1 || true
fi

echo "[3/4] 移除程序文件..."
if [ -d "$INSTALL_DIR" ]; then
    trash="${INSTALL_DIR}.removing.$$"
    mv "$INSTALL_DIR" "$trash"
    rm -rf "$trash" || echo "警告: 程序目录未完全删除: $trash"
fi

echo "[4/4] 处理配置..."
if [ "$PURGE_CONFIG" = "1" ]; then
    rm -f "$CONFIG_FILE"
    echo "      配置已删除: $CONFIG_FILE"
else
    echo "      配置已保留: $CONFIG_FILE"
    echo "      如需删除请加 --purge-config"
fi

echo "卸载完成"
