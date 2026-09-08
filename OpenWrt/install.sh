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

# 安装依赖
echo "[1/5] 安装依赖..."
opkg update >/dev/null 2>&1 || true
opkg install lua curl >/dev/null 2>&1 || {
    echo "警告: 部分依赖可能已安装"
}

# 创建目录
echo "[2/5] 创建目录..."
mkdir -p /usr/lib/haut-network-guard

# 复制文件
echo "[3/5] 复制文件..."
if ! command -v lua >/dev/null 2>&1; then
    echo "错误: 未安装 Lua，无法验证程序"
    exit 1
fi
if command -v lua >/dev/null 2>&1; then
    for file in files/usr/lib/haut-network-guard/*.lua; do
        HAUT_VALIDATE_FILE="$file" lua -e 'assert(loadfile(os.getenv("HAUT_VALIDATE_FILE")))' </dev/null >/dev/null 2>&1 || {
            echo "错误: Lua 语法校验失败: $file"
            exit 1
        }
    done
fi
cp -f files/usr/lib/haut-network-guard/*.lua /usr/lib/haut-network-guard/
cp -f files/etc/init.d/haut-network-guard /etc/init.d/
if [ -f /etc/config/haut-network-guard ]; then
    echo "      检测到现有配置，保留 /etc/config/haut-network-guard"
else
    cp -f files/etc/config/haut-network-guard /etc/config/
fi

# 设置权限
echo "[4/5] 设置权限..."
chmod +x /etc/init.d/haut-network-guard
[ -f /etc/config/haut-network-guard ] && chmod 600 /etc/config/haut-network-guard

# 启用服务
echo "[5/5] 启用服务..."
/etc/init.d/haut-network-guard enable

echo ""
echo "=========================================="
echo "  安装完成! (v1.3.18)"
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
