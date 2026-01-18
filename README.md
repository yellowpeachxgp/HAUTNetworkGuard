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

> **技术栈**: Windows 版本使用 Qt 6 (C++) 开发，提供原生系统托盘支持。
> 
> 构建方式: GitHub Actions 自动编译，推送 tag 时自动发布。

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

### Windows (Qt 6)

Windows 版本使用 Qt 6 构建，通过 GitHub Actions 自动编译：

```bash
# 本地构建 (需要 Qt 6 SDK)
cd Windows
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

> **推荐方式**: 推送 tag 到 GitHub，自动触发构建并发布
>
> ```bash
> git tag v1.x.x
> git push origin v1.x.x
> ```

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
│   │   └── LaunchManager.swift
│   ├── Info.plist
│   ├── build.sh
│   ├── create-dmg.sh
│   ├── install.sh
│   └── uninstall.sh
│
├── Windows/                    # Windows 版本 (Qt 6 C++)
│   ├── src/
│   │   ├── main.cpp           # 入口点
│   │   ├── mainwindow.h/cpp   # 主窗口 UI
│   │   ├── config.h/cpp       # 配置管理 (QSettings)
│   │   ├── api.h/cpp          # 网络 API
│   │   ├── encryption.h/cpp   # SRUN3K 加密
│   │   └── trayicon.h/cpp     # 系统托盘
│   ├── CMakeLists.txt
│   └── AIREADME.md
│
├── Windows-Rust-Deprecated/    # ⚠️ 已弃用的 Rust 版本
│   ├── src/
│   ├── Cargo.toml
│   └── DEPRECATED.md
│
├── OpenWrt/                    # OpenWrt 版本 (Lua)
│   ├── files/
│   │   ├── usr/lib/haut-network-guard/
│   │   │   ├── main.lua
│   │   │   ├── api.lua
│   │   │   └── crypto.lua
│   │   ├── etc/init.d/
│   │   └── etc/config/
│   ├── install.sh
│   ├── uninstall.sh
│   └── README.md
│
├── .github/workflows/          # GitHub Actions CI/CD
│   └── build.yml
│
└── README.md
```

## 技术栈

| 组件 | macOS | Windows | OpenWrt |
|-----|-------|---------|------------|
| 语言 | Swift | **C++ (Qt 6)** | Lua |
| GUI | AppKit | **Qt Widgets** | CLI |
| HTTP | URLSession | **QNetworkAccessManager** | curl |
| 加密 | SRUN3K | SRUN3K | SRUN Portal |
| 配置存储 | UserDefaults | **QSettings** | UCI |
| 系统托盘 | NSStatusItem | **QSystemTrayIcon** | - |
| 开机自启 | LaunchAgent | 注册表 Run 键 | procd |
| 构建 | swiftc | **CMake + MSVC** | - |
| CI/CD | GitHub Actions | **GitHub Actions** | - |

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

### v1.3.3 (2026-01)
- **Windows**: 修复编译问题
  - 修复 MSVC "most vexing parse" 语法歧义
  - 使用中间变量避免函数声明歧义
- **全平台**: 版本号同步更新为 1.3.3

### v1.3.2 (2026-01)
- **Windows**: 修复登录超时问题
  - 修正 API 服务器地址 (`172.20.255.2` → `172.16.154.130`)
  - 修正 HTTP 请求方式 (GET → POST)
  - 修正登录端口 (80 → 69)
  - 优化响应解析逻辑，与 Rust 版本保持一致
- **全平台**: 版本号同步更新为 1.3.2

### v1.3.1 (2026-01)
- **Windows**: 修复独立运行问题
  - 构建时打包 Qt 运行时库 (DLL)
  - 发布为 ZIP 压缩包，解压即可运行
  - 无需安装 Qt 运行库
- **CI/CD**: 完善发布流程
  - 自动生成完整的更新日志
  - Release 包含详细安装说明
- **全平台**: 版本号同步更新为 1.3.1

### v1.3.0 (2026-01)
- **Windows**: 使用 Qt 6 (C++) 完全重写
  - 原生 `QSystemTrayIcon` 系统托盘，更稳定
  - `QSettings` 管理配置，标准化存储
  - 异步 HTTP 请求 (`QNetworkAccessManager`)
  - 更好的 Windows 原生集成
- **CI/CD**: 新增 GitHub Actions 自动构建
  - 推送 tag 时自动编译 Windows (Qt) 和 macOS (Swift)
  - 自动上传二进制文件到 GitHub Release
- **说明**: 原 Rust 版本已弃用，代码保留在 `Windows-Rust-Deprecated/` 目录

### v1.2.6 (2026-01)
- **OpenWrt**: 修复服务启动崩溃问题 (感谢 @1826013250 提交 PR #2)
  - 修复 `string.format` 时间戳格式错误 (`%d` → `%.0f`)
  - 修复密码 `{MD5}` 未正确 URL 编码的问题
  - 修复 JSON 解析正则表达式对空格的容错
  - 安装脚本自动安装依赖 (lua, curl, openssl-util)
- **Windows**: 修复系统托盘功能
  - 关闭窗口正确最小化到托盘
  - 托盘菜单可正确唤出/退出程序
- **全平台**: 版本号同步更新为 1.2.6

### v1.2.5 (2026-01)
- **Windows**: 修复系统托盘功能
  - 点击关闭按钮现在正确最小化到托盘而不是退出
  - 托盘右键菜单「显示窗口」可正确唤出主窗口
  - 托盘右键菜单「退出程序」正确退出应用
- **OpenWrt**: 进一步改进 bit 库加载逻辑，添加调试日志
- **全平台**: 版本号同步更新为 1.2.5

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
