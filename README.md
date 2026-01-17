# HAUT Network Guard

河南工业大学校园网自动登录工具 - 支持 macOS、Windows 和 OpenWrt 三平台

## 功能特性

- **自动监控**: 每3秒自动检测网络连接状态
- **自动重连**: 检测到断线后自动尝试重新登录
- **开机自启**: 支持开机自动启动，保持网络始终连接
- **系统托盘**: 最小化到系统托盘/菜单栏，静默运行
- **系统通知**: 登录/注销状态变化时推送通知
- **配置保存**: 安全存储凭据，支持记住密码
- **更新检测**: 可视化更新窗口，显示版本号和更新日志

## 系统要求

### macOS
- macOS 11.0 (Big Sur) 或更高版本

### Windows
- Windows 10 或更高版本
- 64位系统

### OpenWrt
- OpenWrt 19.07 或更高版本
- 需要安装: lua, curl, openssl-util

## 下载安装

前往 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面下载最新版本。

### macOS

1. 下载 `HAUTNetworkGuard-macOS.dmg`
2. 打开 DMG 文件，将应用拖入 Applications 文件夹
3. 双击运行

> **注意**: 如果首次打开时提示"文件已损坏"或"无法验证开发者"，请在终端执行：
> ```bash
> xattr -cr /Applications/HAUTNetworkGuard.app
> ```
> 然后重新打开应用即可。

### Windows

1. 下载 `HAUTNetworkGuard-Windows.exe`
2. 双击运行即可（无需安装）

### OpenWrt

详见 [OpenWrt/README.md](OpenWrt/README.md)

**一键安装：**
```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh
```

**配置并启动：**
```bash
uci set haut-network-guard.main.username='你的学号'
uci set haut-network-guard.main.password='你的密码'
uci commit haut-network-guard
/etc/init.d/haut-network-guard start
```

## 使用说明

1. **首次运行**: 会弹出设置窗口，输入学号和密码
2. **开机自启动**: 在设置中勾选"开机自启动"选项
3. **状态图标**:
   - 绿色：已连接
   - 红色：未连接
4. **右键菜单** (macOS):
   - 查看当前状态、IP、流量、在线时长
   - 手动登录/注销
   - 立即检测
   - 修改账号设置
   - 检查更新

### 更新检测窗口

点击"检查更新"后，会弹出更新窗口显示：
- 当前版本号
- 最新版本号
- GitHub Release 更新日志
- 立即更新 / 稍后更新 按钮

## 从源码构建

### macOS

```bash
cd macOS
./build.sh

# 创建 DMG 安装包
./create-dmg.sh
```

### Windows

需要安装 Rust 工具链：

```bash
# 安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 构建
cd Windows
cargo build --release

# 输出位于 target/release/haut-network-guard.exe
```

#### 从 macOS 交叉编译 Windows

```bash
# 安装 Windows 目标和 mingw-w64
rustup target add x86_64-pc-windows-gnu
brew install mingw-w64

# 交叉编译
cd Windows
cargo build --release --target x86_64-pc-windows-gnu
```

## 项目结构

```
HAUTNetworkGuard/
├── macOS/                      # macOS 版本 (Swift)
│   ├── Sources/
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── Config.swift
│   │   ├── Encryption.swift
│   │   ├── SrunAPI.swift
│   │   ├── StatusBarController.swift
│   │   ├── SettingsWindow.swift
│   │   ├── AboutWindow.swift
│   │   ├── UpdateChecker.swift
│   │   ├── UpdateWindow.swift
│   │   └── LaunchManager.swift    # 开机自启动管理
│   ├── Info.plist
│   ├── build.sh
│   ├── create-dmg.sh
│   ├── install.sh
│   └── uninstall.sh
│
├── Windows/                    # Windows 版本 (Rust)
│   ├── src/
│   │   ├── main.rs            # 主程序 + egui GUI
│   │   ├── api.rs             # 网络 API
│   │   ├── config.rs          # 配置管理 (注册表 + 开机自启)
│   │   ├── encryption.rs      # SRUN3K 加密
│   │   └── update.rs          # 更新检测
│   ├── Cargo.toml
│   └── build.rs
│
├── OpenWrt/                    # OpenWrt 版本 (Lua)
│   ├── files/
│   │   ├── usr/lib/haut-network-guard/
│   │   │   ├── main.lua       # 主程序
│   │   │   ├── api.lua        # API 模块
│   │   │   └── crypto.lua     # 加密模块
│   │   ├── etc/init.d/        # 服务脚本
│   │   └── etc/config/        # UCI 配置
│   ├── install.sh
│   ├── uninstall.sh
│   └── README.md
│
└── README.md
```

## 技术栈

| 组件 | macOS | Windows | OpenWrt |
|-----|-------|---------|---------|
| 语言 | Swift | Rust | Lua |
| GUI | AppKit | egui + eframe | CLI |
| HTTP | URLSession | reqwest | curl |
| 加密 | SRUN3K | SRUN3K | SRUN Portal |
| 配置存储 | UserDefaults | Windows 注册表 | UCI |
| 开机自启 | LaunchAgent | 注册表 Run 键 | procd |
| 构建 | swiftc | cargo | - |

## 卸载

### macOS

```bash
cd macOS
./uninstall.sh
```

或手动删除：
1. 删除 `/Applications/HAUTNetworkGuard.app`
2. 删除 `~/Library/LaunchAgents/cn.ehaut.networkguard.plist`

### Windows

1. 删除 `HAUTNetworkGuard-Windows.exe`
2. （可选）运行 `regedit`，删除：
   - `HKEY_CURRENT_USER\Software\HAUTNetworkGuard`
   - `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` 下的 `HAUTNetworkGuard` 项

### OpenWrt

```bash
cd OpenWrt
./uninstall.sh
```

## 版本历史

### v1.2.4 (2026-01)
- **OpenWrt**: 修复 bit 库加载问题，支持多种环境（bit/bit32/nixio.bit/纯Lua回退）
- **OpenWrt**: 服务无法启动的问题已修复
- **全平台**: 版本号同步更新为 1.2.4

### v1.2.3 (2026-01)
- **Windows**: 新增系统托盘功能，支持右键菜单（显示窗口/退出程序）
- **Windows**: 程序运行时在任务栏托盘区域显示绿色图标
- **全平台**: 版本号同步更新为 1.2.3

### v1.2.2 (2026-01)
- **OpenWrt**: 修复 Lua 5.1 兼容性问题，解决 `unexpected symbol near '~'` 语法错误
- **Windows**: 改进开机自启动后的自动登录逻辑，增加 5 秒启动延迟等待网络就绪
- **macOS**: 优化构建脚本，添加 SDK 路径自动检测和模块缓存清理
- **全平台**: 统一版本号为 1.2.2

### v1.1.4 (2025-01)
- 新增开机自启动功能 (macOS/Windows)
- 设置窗口增加"开机自启动"复选框
- 完善技术文档

### v1.1.3 (2025-01)
- Windows 版本修复中文字体显示
- Windows 版本更新检测功能修复

### v1.1.2 (2025-01)
- 重构更新检测模块，支持三态结果
- 新增可视化更新窗口

### v1.0.0 (2024)
- 初始版本发布

## 作者

**YellowPeach**

- 项目地址: https://github.com/yellowpeachxgp/HAUTNetworkGuard
- QQ群: 789860526

## 许可证

MIT License
