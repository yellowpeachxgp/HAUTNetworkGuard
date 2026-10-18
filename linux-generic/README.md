# HAUT Network Guard - 通用 Linux 版本 (Debian / Ubuntu)

河南工业大学校园网自动登录工具 - 通用 Linux 版本。

本目录复用 `OpenWrt/` 下的同一套 Lua 核心，仅补充 Debian / Ubuntu 的部署适配：
把 OpenWrt 的 **UCI 配置** 与 **procd 服务** 替换为 **纯文本配置文件** 与 **systemd 服务**。

## 系统要求

- Debian 11+ / Ubuntu 20.04+（或其它使用 systemd 的发行版）
- Lua 5.1+（推荐 lua5.1；同时兼容 5.3 / 5.4）
- curl
- systemd
- root 权限

## 工作原理

核心逻辑（`api.lua` / `crypto.lua` / `protocol.lua` / `session.lua`）与平台无关。
`config.lua` 在运行时探测环境：

- 存在 `/etc/config/haut-network-guard` 或 `/etc/openwrt_release`，且系统提供 `uci` → 使用 UCI；
- 否则 → 读取 `/etc/haut-network-guard.conf`。

因此 OpenWrt 和通用 Linux 共用同一份核心代码，不需要维护两套协议实现。

## 安装

### 固定版本安装（推荐生产环境）

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.21/linux-generic/install-online.sh | sh -s -- v1.3.21
```

安装脚本会从 Release 下载 `HAUTNetworkGuard-Linux.tar.gz`，使用 `SHA256SUMS` 校验后再安装。

### 跟随 main 安装（适合测试）

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/linux-generic/install-online.sh | sh
```

### 仓库内安装

```bash
git clone https://github.com/yellowpeachxgp/HAUTNetworkGuard.git
cd HAUTNetworkGuard
sudo ./linux-generic/install.sh
```

安装脚本会先校验全部 Lua 文件，再原子切换程序目录和服务文件；启用失败会恢复旧版本。
已有 `/etc/haut-network-guard.conf` 会保留，不会被覆盖。

## 配置

编辑 `/etc/haut-network-guard.conf`（权限 `600`，仅 root 可读）：

```ini
enabled=1
username=你的学号
password=你的密码
interval=30
log_level=info

# 可选：覆盖校园网网关
gateway_host=172.16.154.130
gateway_port=69
ac_id=1
```

字段含义与 OpenWrt 的 UCI 配置一一对应：

| 字段 | 说明 | 默认 |
|------|------|------|
| `enabled` | 是否启用自动登录 | `1` |
| `username` | 学号 | 空 |
| `password` | 密码 | 空 |
| `interval` | 检测间隔（秒，30-300） | `30` |
| `log_level` | 日志级别（debug/info/warn/error） | `info` |
| `gateway_host` | 校园网网关 IPv4 | `172.16.154.130` |
| `gateway_port` | 登录端口 | `69` |
| `ac_id` | 认证 ac_id | `1` |

> 配置支持整行注释（`#` 或 `;`）和用单/双引号包裹的值。密码包含 `#`、`;`、空格或引号时请使用双引号包裹。
>
> 配置文件保存的是明文密码，仅通过 `600` 权限限制为 root 可读；拥有 root 权限的用户仍可读取。请勿把该文件提交到版本库或发送给他人。

修改配置后重启服务生效：

```bash
sudo systemctl restart haut-network-guard
```

## 服务管理

```bash
sudo systemctl start haut-network-guard      # 启动
sudo systemctl stop haut-network-guard       # 停止
sudo systemctl restart haut-network-guard    # 重启
sudo systemctl status haut-network-guard     # 状态
sudo systemctl enable haut-network-guard     # 开机自启
sudo systemctl disable haut-network-guard    # 取消开机自启
sudo journalctl -u haut-network-guard -f     # 实时日志
```

服务单元启用了 `NoNewPrivileges`、`PrivateTmp`、`ProtectHome` 和 `ProtectSystem=full` 等基础加固；
程序只读取配置文件、访问校园网网关，并在私有 `/tmp` 中写请求临时文件。

## 卸载

```bash
sudo ./linux-generic/uninstall.sh

# 同时删除配置（包含密码）
sudo ./linux-generic/uninstall.sh --purge-config
```

在线卸载：

```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.21/linux-generic/uninstall.sh | sudo sh
```

卸载会先停止并禁用服务；停止失败时保留程序文件，避免留下无法管理的服务。
默认保留配置，只有显式使用 `--purge-config` 才会删除密码配置。

## 目录结构

```
linux-generic/
├── README.md                                   # 本文档
├── config.example                              # 配置模板
├── install.sh                                  # 本地安装脚本
├── install-online.sh                           # 在线安装脚本
├── uninstall.sh                                # 卸载脚本
└── systemd/
    └── haut-network-guard.service              # systemd 服务模板
```

安装后：

```
/usr/lib/haut-network-guard/                    # 共享 Lua 核心
/etc/haut-network-guard.conf                    # 配置（600）
/etc/systemd/system/haut-network-guard.service  # systemd 服务
```

## 与其它平台的一致性

| 组件 | OpenWrt | 通用 Linux |
|------|---------|-----------|
| 语言 | Lua 5.1+ | Lua 5.1+ |
| HTTP | curl | curl |
| 加密 | SRUN3K | SRUN3K |
| 配置存储 | UCI (`/etc/config/`) | 纯文本 (`/etc/haut-network-guard.conf`) |
| 服务管理 | procd | systemd |

协议实现与日志契约与其它平台保持一致，详见 [`../docs/SRUN3K_PROTOCOL_SPEC.md`](../docs/SRUN3K_PROTOCOL_SPEC.md) 与 [`../docs/LOGGING_CONTRACT.md`](../docs/LOGGING_CONTRACT.md)。

## 排查

1. 查看服务状态：`systemctl status haut-network-guard`
2. 查看日志：`journalctl -u haut-network-guard -n 100 --no-pager`
3. 确认配置权限：`stat -c '%a %U:%G' /etc/haut-network-guard.conf` 应为 `600 root:root`
4. 临时提高日志级别：把 `log_level` 改为 `debug` 后重启服务
5. 确认 `curl` 可访问网关：`curl -v --max-time 5 http://172.16.154.130`
