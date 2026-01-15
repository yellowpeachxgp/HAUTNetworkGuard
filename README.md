# HAUT Network Guard

河南工业大学校园网自动登录工具 - 支持 macOS 和 Windows 双平台

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
└── README.md
```

## 技术栈

| 组件 | macOS | Windows |
|-----|-------|---------|
| 语言 | Swift | Rust |
| GUI | AppKit | egui + eframe |
| HTTP | URLSession | reqwest |
| 加密 | SRUN3K | SRUN3K |
| 配置存储 | UserDefaults | Windows 注册表 |
| 开机自启 | LaunchAgent | 注册表 Run 键 |
| 构建 | swiftc | cargo |

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

## 作者

**YellowPeach**

- 项目地址: https://github.com/yellowpeachxgp/HAUTNetworkGuard
- QQ群: 789860526

## 许可证

MIT License
