#!/bin/sh
# HAUT Network Guard - Debian / Ubuntu 在线一键安装
# 用法:
#   sh -s --              # 跟随 main 分支（适合测试）
#   sh -s -- v1.3.21      # 固定 Release 版本（推荐生产环境）

set -eu

REF="${1:-main}"
case "$REF" in
    main) ;;
    v*)
        if ! printf '%s\n' "$REF" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "错误: 版本标签格式无效，应为 vX.Y.Z"
            exit 1
        fi
        ;;
    *)
        echo "错误: 仅支持 main 或 vX.Y.Z 版本标签"
        exit 1
        ;;
esac

ROOT_PREFIX="${HAUT_ROOT:-}"
case "$ROOT_PREFIX" in ""|/*) ;; *) echo "错误: HAUT_ROOT 必须为绝对路径"; exit 1 ;; esac

if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

for command_name in tar sed grep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "错误: 缺少依赖: $command_name"
        exit 1
    fi
done

TMP_DIR=$(mktemp -d)
cleanup() {
    status=$?
    rm -rf "$TMP_DIR"
    exit "$status"
}
trap cleanup EXIT

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" "$url"
    else
        echo "错误: 需要 curl 或 wget"
        return 1
    fi
    mv "$tmp" "$dest"
}

sha256_of() {
    file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk -F'= ' '{print $2}'
    else
        echo "错误: 缺少 sha256sum 或 openssl，无法校验发布文件" >&2
        return 1
    fi
}

echo "=========================================="
echo "  HAUT Network Guard - 通用 Linux 一键安装"
echo "=========================================="
echo ""
echo "源版本: $REF"
echo ""

case "$REF" in
    v*)
        echo "[1/4] 下载 Release 资产..."
        RELEASE_URL="https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases/download/$REF"
        download_file "$RELEASE_URL/HAUTNetworkGuard-Linux.tar.gz" "$TMP_DIR/HAUTNetworkGuard-Linux.tar.gz"
        download_file "$RELEASE_URL/SHA256SUMS" "$TMP_DIR/SHA256SUMS"
        expected=$(awk '$2 == "HAUTNetworkGuard-Linux.tar.gz" { print $1; exit }' "$TMP_DIR/SHA256SUMS")
        if [ -z "$expected" ]; then
            echo "错误: Release 清单缺少 HAUTNetworkGuard-Linux.tar.gz"
            exit 1
        fi
        actual=$(sha256_of "$TMP_DIR/HAUTNetworkGuard-Linux.tar.gz")
        if [ "$actual" != "$expected" ]; then
            echo "错误: Linux 发布包校验失败"
            exit 1
        fi
        echo "[2/4] 解压发布包..."
        mkdir -p "$TMP_DIR/src"
        tar -xzf "$TMP_DIR/HAUTNetworkGuard-Linux.tar.gz" -C "$TMP_DIR/src"
        SOURCE_ROOT="$TMP_DIR/src/HAUTNetworkGuard-Linux"
        ;;
    *)
        echo "[1/4] 下载 main 源码包..."
        download_file "https://github.com/yellowpeachxgp/HAUTNetworkGuard/archive/refs/heads/main.tar.gz" "$TMP_DIR/main.tar.gz"
        echo "[2/4] 解压源码包..."
        mkdir -p "$TMP_DIR/src"
        tar -xzf "$TMP_DIR/main.tar.gz" -C "$TMP_DIR/src"
        SOURCE_ROOT=$(find "$TMP_DIR/src" -maxdepth 1 -type d -name 'HAUTNetworkGuard-*' | head -n 1)
        ;;
esac

if [ ! -d "$SOURCE_ROOT/OpenWrt/files/usr/lib/haut-network-guard" ]; then
    echo "错误: 发布包结构不完整"
    exit 1
fi

echo "[3/4] 校验版本..."
VERSION=$(sed -n 's/^return "\([^"]*\)".*/\1/p' "$SOURCE_ROOT/OpenWrt/files/usr/lib/haut-network-guard/version.lua" 2>/dev/null || true)
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "错误: 无法读取有效程序版本"
    exit 1
fi
case "$REF" in
    v*)
        if [ "$VERSION" != "${REF#v}" ]; then
            echo "错误: tag 与程序版本不一致: $REF -> $VERSION"
            exit 1
        fi
        ;;
esac

echo "[4/4] 执行安装脚本..."
HAUT_SOURCE_ROOT="$SOURCE_ROOT" sh "$SOURCE_ROOT/linux-generic/install.sh"
