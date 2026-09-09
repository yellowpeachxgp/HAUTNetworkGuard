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
- 建议安装: lua, curl

## 安装依赖

```bash
opkg update
opkg install lua curl
```

## 一键安装（推荐）

在路由器终端执行：

固定版本安装（推荐生产环境）：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.19/OpenWrt/install-online.sh | sh -s -- v1.3.19
```

安装最新 main（适合测试）：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
```

或使用 curl：

```bash
curl -sSL https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
```

离线安装脚本会先在临时目录校验全部 Lua 和服务脚本，再原子切换程序目录；启用失败会恢复旧版本，已有配置会保留。

v1.3.19 起正式 Release 提供 `OpenWrt-SHA256SUMS`，其中记录固定版本安装脚本和运行文件的哈希。固定 `v*` 安装和升级会在切换前下载该清单并逐个校验；`main` 开发引用不具备 Release 清单。旧版 v1.3.18 缺少该清单，固定版本命令会安全停止。

升级到固定版本：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.19/OpenWrt/upgrade-online.sh | sh -s -- v1.3.19
```

## 手动安装

```bash
# 上传文件到路由器后执行
chmod +x install.sh
./install.sh
```

## 配置

OpenWrt 密码保存在 `/etc/config/haut-network-guard`，安装脚本会设置文件权限为 `600`。拥有路由器 root 权限的用户仍可读取该配置。

```bash
# 设置用户名
uci set haut-network-guard.main.username='你的学号'

# 设置密码
uci set haut-network-guard.main.password='你的密码'

# 设置检测间隔 (秒，默认30)
uci set haut-network-guard.main.interval='30'

# 可选：覆盖校园网网关（默认 172.16.154.130:69，ac_id=1）
uci set haut-network-guard.main.gateway_host='172.16.154.130'
uci set haut-network-guard.main.gateway_port='69'
uci set haut-network-guard.main.ac_id='1'

# 可选: 设置日志级别 (debug/info/warn/error)
uci set haut-network-guard.main.log_level='info'

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

# 只读检查依赖和 UCI 配置（不发起校园网请求）
/etc/init.d/haut-network-guard diagnose

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

# 如需连配置一起删除：
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/uninstall-online.sh | sh -s -- --purge-config
```

或手动卸载：

```bash
chmod +x uninstall.sh
./uninstall.sh

# 如需连配置一起删除：
./uninstall.sh --purge-config
```

卸载会先停止并禁用服务；默认保留 UCI 配置，只有显式使用 `--purge-config` 才会删除密码配置。

## 文件结构

```
/usr/lib/haut-network-guard/
├── version.lua   # 运行时版本唯一来源
├── main.lua      # 主程序
├── api.lua       # API 模块
├── log.lua       # 日志与脱敏
├── protocol.lua  # 配置清洗/响应分类纯逻辑
└── crypto.lua    # 加密模块

/etc/init.d/haut-network-guard    # 服务脚本
/etc/config/haut-network-guard    # 配置文件
```

## 技术说明

本版本使用 SRUN3K 认证协议：
- 用户名 `{SRUN3}\r\n` + ASCII 偏移加密
- 密码 XOR + 位分割编码
- `POST /cgi-bin/srun_portal` 提交登录请求
- `GET /cgi-bin/rad_user_info` 检查在线状态

日志与协议规范参考：

- [`../docs/LOGGING_CONTRACT.md`](../docs/LOGGING_CONTRACT.md)
- [`../docs/SRUN3K_PROTOCOL_SPEC.md`](../docs/SRUN3K_PROTOCOL_SPEC.md)

## 调试建议

- 查看日志:
  - `logread | grep haut-network-guard`
- 遇到启动或重连问题时，先运行 `/etc/init.d/haut-network-guard diagnose`，根据“失败/提示”项补齐依赖或配置；诊断不会输出账号和密码内容。
- 临时提高日志级别:
  - `uci set haut-network-guard.main.log_level='debug'`
  - `uci commit haut-network-guard`
  - `/etc/init.d/haut-network-guard restart`
