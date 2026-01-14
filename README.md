# HAUT Network Guard

河南工业大学校园网自动登录工具 - 支持 macOS 和 Windows 双平台

## 功能特性

- **自动监控**: 每3秒自动检测网络连接状态
- **自动重连**: 检测到断线后自动尝试重新登录
- **系统托盘**: 最小化到系统托盘/菜单栏，静默运行
- **系统通知**: 登录/注销状态变化时推送通知
- **配置保存**: 安全存储凭据，支持记住密码
- **自动更新**: 检测 GitHub Release 新版本

### 平台特有功能

| 功能 | macOS | Windows |
|-----|-------|---------|
| 系统托盘 | 菜单栏图标 | 系统托盘图标 |
| 可视化面板 | - | 详细网络状态面板 |
| 开机自启 | LaunchAgent | - |
| 配置存储 | UserDefaults | Windows 注册表 |

## 系统要求

### macOS
- macOS 11.0 (Big Sur) 或更高版本

### Windows
- Windows 10 或更高版本
- 64位系统

## 下载安装

### macOS

1. 前往 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面
2. 下载最新版本的 `HAUTNetworkGuard.dmg`
3. 打开 DMG 文件，将应用拖入 Applications 文件夹
4. 双击运行

### Windows

1. 前往 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面
2. 下载最新版本的 `HAUTNetworkGuard.exe`
3. 双击运行即可

## 使用说明

1. **首次运行**: 会弹出设置窗口，输入学号和密码
2. **状态图标**:
   - 绿色/WiFi图标：已连接
   - 红色/斜杠WiFi：未连接
   - 灰色/循环箭头：检测中
3. **右键菜单**:
   - 查看当前状态、IP、流量、在线时长
   - 手动登录/注销
   - 立即检测
   - 修改账号设置
   - 检查更新

### Windows 可视化面板

Windows 版本新增可视化面板功能，可在托盘菜单中打开，显示：
- 连接状态和在线指示
- IP 地址
- 已用流量（带进度条）
- 在线时长
- 快捷操作按钮

## 从源码构建

### macOS

```bash
cd macOS
./build.sh

# 安装（可选，包含开机自启）
./install.sh
```

### Windows

需要安装：
- Visual Studio 2019/2022 (含 C++ 桌面开发工作负载)
- CMake 3.20+

```batch
cd Windows

:: 方式一：使用构建脚本
build.bat

:: 方式二：使用 CMake
mkdir build && cd build
cmake -G "Visual Studio 17 2022" -A x64 ..
cmake --build . --config Release
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
│   │   └── UpdateChecker.swift
│   ├── Info.plist
│   ├── build.sh
│   ├── install.sh
│   └── uninstall.sh
│
├── Windows/                    # Windows 版本 (C++)
│   ├── src/
│   │   ├── main.cpp
│   │   ├── Application.h/cpp
│   │   ├── core/               # 核心业务
│   │   ├── config/             # 配置管理
│   │   ├── ui/                 # 界面
│   │   ├── utils/              # 工具类
│   │   └── resource/           # 资源文件
│   ├── CMakeLists.txt
│   └── build.bat
│
└── README.md                   # 本文件
```

## 技术栈

| 组件 | macOS | Windows |
|-----|-------|---------|
| 语言 | Swift | C++17 |
| 框架 | AppKit | Win32 API |
| HTTP | URLSession | WinHTTP |
| 加密 | SRUN3K | SRUN3K |
| 构建 | swiftc | CMake + MSVC |

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

1. 删除 `HAUTNetworkGuard.exe`
2. 运行 `regedit`，删除 `HKEY_CURRENT_USER\Software\HAUTNetworkGuard`

## 作者

**YellowPeach**

- 项目地址: https://github.com/yellowpeachxgp/HAUTNetworkGuard
- QQ群: 789860526

## 许可证

MIT License
