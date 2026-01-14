# HAUT Network Guard - Windows

河南工业大学校园网自动登录工具 (Windows 版)

## 功能特性

- 🔄 **自动监控**: 每3秒自动检测网络状态
- 🔁 **自动重连**: 检测到掉线时自动重新登录
- 📊 **可视化面板**: 显示网络状态、流量、在线时长
- 🔔 **系统通知**: 登录/注销状态通过气泡通知提醒
- 🔄 **自动更新**: 每24小时检测GitHub Release更新
- 💾 **配置保存**: 凭据安全存储在Windows注册表

## 系统要求

- Windows 10 或更高版本
- 64位系统

## 下载

从 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面下载最新版本的 `HAUTNetworkGuard.exe`

## 使用方法

1. 双击运行 `HAUTNetworkGuard.exe`
2. 首次运行时输入学号和密码
3. 点击"保存并启动"
4. 程序将最小化到系统托盘，自动监控网络状态

### 托盘菜单

右键点击系统托盘图标可以:
- 查看当前网络状态
- 手动登录/注销
- 打开可视化面板
- 修改账号设置
- 检查更新
- 退出程序

## 从源码构建

### 前置要求

- Visual Studio 2019/2022 (含 C++ 桌面开发工作负载)
- CMake 3.20+

### 构建步骤

1. 打开 "Developer Command Prompt for VS"
2. 进入项目目录
3. 运行构建脚本:

```batch
build.bat
```

或者使用 CMake:

```batch
mkdir build && cd build
cmake -G "Visual Studio 17 2022" -A x64 ..
cmake --build . --config Release
```

## 项目结构

```
HAUTNetworkGuard-Windows/
├── CMakeLists.txt          # CMake配置
├── build.bat               # 构建脚本
├── src/
│   ├── main.cpp            # 入口点
│   ├── Application.h/cpp   # 应用主类
│   ├── core/               # 核心业务
│   │   ├── SrunEncryption.h    # 加密算法
│   │   ├── SrunAPI.h           # API封装
│   │   ├── NetworkStatus.h     # 状态结构
│   │   └── UpdateChecker.h     # 更新检测
│   ├── config/             # 配置管理
│   │   └── AppConfig.h
│   ├── ui/                 # 界面
│   │   ├── BaseWindow.h
│   │   ├── TrayIcon.h
│   │   ├── SettingsWindow.h
│   │   ├── AboutWindow.h
│   │   ├── UpdateWindow.h
│   │   └── DashboardWindow.h/cpp
│   ├── utils/              # 工具类
│   │   ├── Logger.h
│   │   ├── StringUtils.h
│   │   └── HttpClient.h
│   └── resource/           # 资源
│       ├── resource.h
│       ├── resource.rc
│       └── manifest.xml
```

## 作者

YellowPeach

## 许可证

MIT License

## 相关链接

- [macOS 版本](https://github.com/yellowpeachxgp/HAUTNetworkGuard)
- [QQ群: 789860526](https://qm.qq.com/q/789860526)
