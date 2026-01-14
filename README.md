# HAUT Network Guard

河南工业大学校园网自动登录工具 - macOS 菜单栏应用

## 功能特性

- 🔄 **自动监控**: 实时检测网络连接状态
- 🔌 **自动重连**: 断线后自动尝试重新登录
- 🔔 **系统通知**: 登录状态变化时推送通知
- ⚙️ **首次配置**: 首次运行时弹出设置窗口
- 🚀 **开机自启**: 支持开机自动运行

## 系统要求

- macOS 11.0 (Big Sur) 或更高版本
- 连接到河南工业大学校园网

## 安装方法

### 方法一：直接下载 (推荐)

1. 前往 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面
2. 下载最新版本的 `HAUTNetworkGuard.dmg`
3. 打开 DMG 文件，将应用拖入 Applications 文件夹
4. 双击运行

### 方法二：从源码编译

```bash
# 克隆仓库
git clone https://github.com/yellowpeachxgp/HAUTNetworkGuard.git
cd HAUTNetworkGuard

# 编译
./build.sh

# 安装（可选，包含开机自启）
./install.sh
```

## 使用说明

1. 首次运行时会弹出设置窗口，输入学号和密码
2. 应用会在菜单栏显示网络状态图标：
   - 📶 WiFi 图标：已连接
   - 📵 斜杠 WiFi：未连接
   - 🔄 循环箭头：检测中
3. 点击菜单栏图标可以：
   - 查看当前状态、IP、流量、在线时长
   - 手动登录/注销
   - 立即检测
   - 修改账号设置

## 卸载方法

```bash
./uninstall.sh
```

或手动删除：
1. 删除 `/Applications/HAUTNetworkGuard.app`
2. 删除 `~/Library/LaunchAgents/cn.ehaut.networkguard.plist`

## 项目结构

```
HAUTNetworkGuard/
├── Sources/
│   ├── main.swift              # 应用入口
│   ├── AppDelegate.swift       # 应用代理
│   ├── Config.swift            # 配置管理
│   ├── Encryption.swift        # 加密模块
│   ├── SrunAPI.swift           # API 封装
│   ├── StatusBarController.swift # 菜单栏控制器
│   ├── SettingsWindow.swift    # 设置窗口
│   └── AboutWindow.swift       # 关于窗口
├── Info.plist                  # 应用配置
├── cn.ehaut.networkguard.plist # LaunchAgent 配置
├── build.sh                    # 构建脚本
├── install.sh                  # 安装脚本
└── uninstall.sh                # 卸载脚本
```

## 作者

**YellowPeach**

- 项目地址: https://github.com/yellowpeachxgp/HAUTNetworkGuard
- QQ群: 789860526

## 许可证

MIT License
