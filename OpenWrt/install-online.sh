#!/bin/sh
# HAUT Network Guard - OpenWrt 一键安装脚本
# 用法:
#   最新 main: wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
#   固定版本:   wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.18/OpenWrt/install-online.sh | sh -s -- v1.3.18

set -e

REPO_REF="${1:-main}"
REPO_URL="https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/${REPO_REF}/OpenWrt"
INSTALL_DIR="/usr/lib/haut-network-guard"

# 需要下载/更新的核心模块（新增模块时必须在此追加，确保与 upgrade-online.sh 保持一致）
MODULES="crypto api log config protocol main"

download_file() {
    url="$1"
    dest="$2"
    tmp="${dest}.tmp"

    curl -fsSL "$url" -o "$tmp"
    mv "$tmp" "$dest"
}

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 一键安装"
echo "=========================================="
echo ""
echo "源版本: $REPO_REF"
echo ""

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建目录
echo "[2/5] 创建目录..."
mkdir -p "$INSTALL_DIR"

# 下载文件
echo "[3/5] 下载程序文件..."
for module in $MODULES; do
    download_file "$REPO_URL/files/usr/lib/haut-network-guard/${module}.lua" "$INSTALL_DIR/${module}.lua"
done

echo "[4/5] 下载配置文件..."
download_file "$REPO_URL/files/etc/init.d/haut-network-guard" "/etc/init.d/haut-network-guard"
if [ -f /etc/config/haut-network-guard ]; then
    echo "      检测到现有配置，保留 /etc/config/haut-network-guard"
else
    download_file "$REPO_URL/files/etc/config/haut-network-guard" "/etc/config/haut-network-guard"
fi

# 设置权限
echo "[5/5] 设置权限..."
chmod +x /etc/init.d/haut-network-guard
[ -f /etc/config/haut-network-guard ] && chmod 600 /etc/config/haut-network-guard

# 启用服务
/etc/init.d/haut-network-guard enable >/dev/null 2>&1

echo ""
echo "=========================================="
echo "  安装完成! (v1.3.18)"
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
