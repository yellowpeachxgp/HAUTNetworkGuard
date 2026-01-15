# HAUT Network Guard - OpenWrt 版本

河南工业大学校园网自动登录工具 - OpenWrt 路由器版本

## 功能特性

- 自动检测网络状态
- 断线自动重连
- 开机自启动
- 系统日志记录
- UCI 配置管理

## 系统要求

- OpenWrt 19.07 或更高版本
- Lua 5.1+
- curl
- openssl-util

## 安装依赖

```bash
opkg update
opkg install lua curl openssl-util
```

## 一键安装（推荐）

在路由器终端执行：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
```

或使用 curl：

```bash
curl -sSL https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
```

## 手动安装

```bash
# 上传文件到路由器后执行
chmod +x install.sh
./install.sh
```

## 配置

```bash
# 设置用户名
uci set haut-network-guard.main.username='你的学号'

# 设置密码
uci set haut-network-guard.main.password='你的密码'

# 设置检测间隔 (秒，默认30)
uci set haut-network-guard.main.interval='30'

# 保存配置
uci commit haut-network-guard
```

## 服务管理

```bash
# 启动服务
/etc/init.d/haut-network-guard start

# 停止服务
/etc/init.d/haut-network-guard stop

# 重启服务
/etc/init.d/haut-network-guard restart

# 查看状态
/etc/init.d/haut-network-guard status

# 开机自启
/etc/init.d/haut-network-guard enable

# 禁用自启
/etc/init.d/haut-network-guard disable
```

## 查看日志

```bash
logread | grep haut-network-guard
```

## 卸载

一键卸载：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/uninstall-online.sh | sh
```

或手动卸载：

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## 文件结构

```
/usr/lib/haut-network-guard/
├── main.lua      # 主程序
├── api.lua       # API 模块
└── crypto.lua    # 加密模块

/etc/init.d/haut-network-guard    # 服务脚本
/etc/config/haut-network-guard    # 配置文件
```

## 技术说明

本版本使用 SRUN Portal 认证协议：
- XXTEA 加密用户信息
- HMAC-MD5 加密密码
- SHA1 生成校验和
- Custom Base64 编码
