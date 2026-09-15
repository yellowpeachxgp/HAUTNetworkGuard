#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 在线一键安装
# 用法:
#   sh -s -- <ref>      # ref 可为分支名(如 main)或标签(如 v1.3.19)
# 示例:
#   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/linux-generic/install-online.sh | sh
#   ... | sh -s -- v1.3.19

set -e

REF="${1:-main}"

case "$REF" in
    v*) ARCHIVE="https://github.com/yellowpeachxgp/HAUTNetworkGuard/archive/refs/tags/${REF}.tar.gz" ;;
    *)  ARCHIVE="https://github.com/yellowpeachxgp/HAUTNetworkGuard/archive/refs/heads/${REF}.tar.gz" ;;
esac

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "[1/3] 下载源码 ($REF)..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$ARCHIVE" -o "$TMPDIR/src.tar.gz"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMPDIR/src.tar.gz" "$ARCHIVE"
else
    echo "错误: 需要 curl 或 wget"
    exit 1
fi

echo "[2/3] 解压..."
tar -xzf "$TMPDIR/src.tar.gz" -C "$TMPDIR"
SRCDIR=$(find "$TMPDIR" -maxdepth 1 -type d -name 'HAUTNetworkGuard-*' | head -n 1)
if [ -z "$SRCDIR" ]; then
    echo "错误: 解压后未找到源码目录"
    exit 1
fi

echo "[3/3] 执行安装脚本..."
sh "$SRCDIR/linux-generic/install.sh"
