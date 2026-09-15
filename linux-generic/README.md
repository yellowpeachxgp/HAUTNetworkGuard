# HAUT Network Guard - 通用 Linux 版本 (Debian / Ubuntu)

河南工业大学校园网自动登录工具 - 通用 Linux 版本。

本目录复用 `OpenWrt/` 下的同一套 Lua 核心，仅补充 Debian / Ubuntu 的部署适配：
将 OpenWrt 的 **UCI 配置** 与 **procd 服务** 替换为通用 Linux 的 **纯文本配置文件** 与 **systemd 服务**。

## 系统要求

- Debian 11+ / Ubuntu 20.04+（或其它带 systemd 的发行版）
- Lua 5.1+
- curl
- systemd

## 工作原理

核心逻辑（`api.lua` / `crypto.lua` / `protocol.lua`）与平台无关，无需修改。
`config.lua` 会在运行时探测 `uci` 命令：

- 若存在 `uci`（OpenWrt）→ 优先读取 UCI 配置，行为与 OpenWrt 版完全一致；
- 若不存在 `uci`（通用 Linux）→ 回退读取 `/etc/haut-network-guard.conf`。

因此三端共用同一份核心代码，避免逻辑重复。

## 安装

### 方式一：仓库内安装

```bash
git clone https://github.com/yellowpeachxgp/HAUTNetworkGuard.git
cd HAUTNetworkGuard
sudo ./linux-generic/install.sh
```

### 方式二：在线一键安装

```bash
# 跟随 main 分支
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/linux-generic/install-online.sh | sh

# 固定版本
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/linux-generic/install-online.sh | sh -s -- v1.3.19
```

## 配置

编辑 `/etc/haut-network-guard.conf`：

```ini
enabled=1
username=你的学号
password=你的密码
interval=30
log_level=info
```

字段含义与 OpenWrt 版的 UCI 配置一一对应：

| 字段 | 说明 | 默认 |
|------|------|------|
| `enabled` | 是否启用自动登录 | `1` |
| `username` | 学号 | 空 |
| `password` | 密码 | 空 |
| `interval` | 检测间隔（秒，30-300） | `30` |
| `log_level` | 日志级别（debug/info/warn/error） | `info` |

> 配置文件默认权限为 `600`，仅 root 可读。

## 常用命令

```bash
systemctl start haut-network-guard      # 启动
systemctl stop haut-network-guard       # 停止
systemctl restart haut-network-guard    # 重启
systemctl status haut-network-guard     # 状态
systemctl enable haut-network-guard     # 开机自启
journalctl -u haut-network-guard -f     # 实时日志
```

## 卸载

```bash
sudo ./linux-generic/uninstall.sh
# 如需同时删除配置
sudo ./linux-generic/uninstall.sh --purge-config
```

## 目录结构

```
linux-generic/
├── README.md                                   # 本文档
├── config.example                              # 配置模板
├── install.sh                                  # 本地安装脚本
├── install-online.sh                           # 在线安装脚本
├── uninstall.sh                                # 卸载脚本
└── systemd/
    └── haut-network-guard.service              # systemd 服务单元
```

## 与其它平台的一致性

| 组件 | OpenWrt | 通用 Linux |
|------|---------|-----------|
| 语言 | Lua 5.1 | Lua 5.1 |
| HTTP | curl | curl |
| 加密 | SRUN3K | SRUN3K |
| 配置存储 | UCI (`/etc/config/`) | 纯文本 (`/etc/haut-network-guard.conf`) |
| 服务管理 | procd | systemd |

协议实现与日志契约与其它平台保持一致，详见 [`../docs/SRUN3K_PROTOCOL_SPEC.md`](../docs/SRUN3K_PROTOCOL_SPEC.md) 与 [`../docs/LOGGING_CONTRACT.md`](../docs/LOGGING_CONTRACT.md)。
