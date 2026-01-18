#!/bin/sh
# HAUT Network Guard - OpenWrt 安装脚本

echo "=========================================="
echo "  HAUT Network Guard - OpenWrt 安装"
echo "=========================================="

# 检查是否为 root
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl openssl-util >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建目录
echo "[2/5] 创建目录..."
mkdir -p /usr/lib/haut-network-guard

# 复制文件
echo "[3/5] 复制文件..."
cp -f files/usr/lib/haut-network-guard/*.lua /usr/lib/haut-network-guard/
cp -f files/etc/init.d/haut-network-guard /etc/init.d/
cp -f files/etc/config/haut-network-guard /etc/config/

# 设置权限
echo "[4/5] 设置权限..."
chmod +x /etc/init.d/haut-network-guard
chmod 600 /etc/config/haut-network-guard

# 启用服务
echo "[5/5] 启用服务..."
/etc/init.d/haut-network-guard enable

echo ""
echo "=========================================="
echo "  安装完成!"
echo "=========================================="
echo ""
echo "配置方法:"
echo "  uci set haut-network-guard.main.username='你的学号'"
echo "  uci set haut-network-guard.main.password='你的密码'"
echo "  uci commit haut-network-guard"
echo ""
echo "启动服务:"
echo "  /etc/init.d/haut-network-guard start"
echo ""
