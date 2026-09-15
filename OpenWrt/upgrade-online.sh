#!/bin/sh
# HAUT Network Guard - OpenWrt 一键升级脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/upgrade-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.18/OpenWrt/upgrade-online.sh | sh -s -- v1.3.18

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
INSTALL_DIR="/usr/lib/haut-network-guard"
MAIN_LUA="$INSTALL_DIR/main.lua"
TMP_DIR=""
BACKUP_DIR=""
UPGRADE_SUCCESS=0

# 需要更新的核心模块（新增模块时必须在此追加，确保与 install-online.sh 保持一致）
MODULES="crypto api log config protocol main"

version_cmp() {
    awk -v a="$1" -v b="$2" '
        BEGIN {
            na = split(a, aa, ".")
            nb = split(b, bb, ".")
            n = (na > nb) ? na : nb
            for (i = 1; i <= n; i++) {
                x = (aa[i] == "" ? 0 : aa[i]) + 0
                y = (bb[i] == "" ? 0 : bb[i]) + 0
                if (x > y) { print 1; exit }
                if (x < y) { print -1; exit }
            }
            print 0
        }
    '
}

cleanup() {
    status=$?
    if [ "$UPGRADE_SUCCESS" -ne 1 ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        echo ""
        echo "升级失败，正在回滚到原版本..."
        for module in $MODULES; do
            [ -f "$BACKUP_DIR/${module}.lua" ] && cp -f "$BACKUP_DIR/${module}.lua" "$INSTALL_DIR/${module}.lua" || true
        done
        if [ -f "$BACKUP_DIR/haut-network-guard.init" ]; then
            cp -f "$BACKUP_DIR/haut-network-guard.init" /etc/init.d/haut-network-guard || true
            chmod +x /etc/init.d/haut-network-guard || true
        fi
        /etc/init.d/haut-network-guard start 2>/dev/null || true
    fi

    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    [ -n "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
    exit "$status"
}

trap cleanup EXIT

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 升级检查"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 获取本地版本
LOCAL_VERSION="未安装"
if [ -f "$MAIN_LUA" ]; then
    LOCAL_VERSION=$(grep -o 'VERSION = "[^"]*"' "$MAIN_LUA" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="未知"
fi
echo "本地版本: $LOCAL_VERSION"

# 获取远端版本
echo "正在检查最新版本..."
REMOTE_MAIN=$(curl -fsSL --connect-timeout 10 "$REPO_URL/files/usr/lib/haut-network-guard/main.lua")
if [ -z "$REMOTE_MAIN" ]; then
    echo "错误: 无法连接到 GitHub，请检查网络"
    exit 1
fi

REMOTE_VERSION=$(echo "$REMOTE_MAIN" | grep -o 'VERSION = "[^"]*"' | grep -o '"[^"]*"' | tr -d '"')
if [ -z "$REMOTE_VERSION" ]; then
    echo "错误: 无法解析远端版本号"
    exit 1
fi
echo "最新版本: $REMOTE_VERSION"
echo ""

# 比较版本
if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    echo "当前已是最新版本，无需升级。"
    exit 0
fi

if [ "$LOCAL_VERSION" = "未安装" ]; then
    echo "未检测到安装，请先运行安装脚本。"
    exit 1
fi

COMPARE_RESULT="$(version_cmp "$REMOTE_VERSION" "$LOCAL_VERSION")"
if [ "$COMPARE_RESULT" -gt 0 ]; then
    echo "发现新版本: $LOCAL_VERSION -> $REMOTE_VERSION"
else
    echo "目标版本变更: $LOCAL_VERSION -> $REMOTE_VERSION"
fi
echo "正在升级..."
echo ""

# 停止服务
echo "[1/4] 停止服务..."
/etc/init.d/haut-network-guard stop 2>/dev/null || true

TMP_DIR="$(mktemp -d /tmp/haut-network-guard-upgrade.XXXXXX)"
BACKUP_DIR="$(mktemp -d /tmp/haut-network-guard-backup.XXXXXX)"

for module in $MODULES; do
    cp -f "$INSTALL_DIR/${module}.lua" "$BACKUP_DIR/${module}.lua"
done
cp -f /etc/init.d/haut-network-guard "$BACKUP_DIR/haut-network-guard.init"

# 下载新文件（不覆盖配置）
echo "[2/4] 下载程序文件..."
for module in $MODULES; do
    download_file "$REPO_URL/files/usr/lib/haut-network-guard/${module}.lua" "$TMP_DIR/${module}.lua"
done

echo "[3/4] 更新服务脚本..."
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "$TMP_DIR/haut-network-guard.init"

for module in $MODULES; do
    cp -f "$TMP_DIR/${module}.lua" "$INSTALL_DIR/${module}.lua"
done
cp -f "$TMP_DIR/haut-network-guard.init" "/etc/init.d/haut-network-guard"
chmod +x /etc/init.d/haut-network-guard

# 重启服务
echo "[4/4] 重启服务..."
/etc/init.d/haut-network-guard start
UPGRADE_SUCCESS=1

echo ""
echo "=========================================="
echo "  升级完成! ($LOCAL_VERSION -> $REMOTE_VERSION)"
echo "=========================================="
echo ""
echo "配置文件已保留，无需重新配置。"
echo "查看日志: logread | grep haut-network-guard"
echo ""
