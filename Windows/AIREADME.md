# HAUT Network Guard - Windows C++ 技术文档

此文档供AI助手快速理解项目架构和实现细节。

## 项目概述

- **语言**: C++17
- **框架**: 纯 Win32 API (无第三方GUI库)
- **目标**: 极致性能、最小资源占用
- **版本**: 1.0.0

## 核心技术实现

### 1. SRUN3K 加密算法

完全对标 macOS 版本实现:

```cpp
// 用户名加密: ASCII + 4, 前缀 {SRUN3}\r\n
std::string SrunEncryption::encryptUsername(const std::string& username) {
    std::string encrypted;
    for (char c : username) {
        encrypted += static_cast<char>(static_cast<unsigned char>(c) + 4);
    }
    return "{SRUN3}\r\n" + encrypted;
}

// 密码加密: XOR + 位拆分
// 密钥: "1234567890"
// 密钥索引反向: key.length - 1 - (i % key.length)
// 低4位 = (xor_result & 0x0f) + 0x36
// 高4位 = ((xor_result >> 4) & 0x0f) + 0x63
// 偶数位置: 低+高, 奇数位置: 高+低
```

### 2. 网络API

- 状态检测: GET `http://172.16.154.130/cgi-bin/rad_user_info`
- 登录: POST `http://172.16.154.130:69/cgi-bin/srun_portal`
- 注销: POST (action=logout)

### 3. HTTP请求 (WinHTTP)

使用 WinHTTP API 实现同步/异步请求:
- `WinHttpOpen` - 创建会话
- `WinHttpConnect` - 连接服务器
- `WinHttpOpenRequest` - 创建请求
- `WinHttpSendRequest` - 发送请求
- `WinHttpReceiveResponse` - 接收响应

### 4. 系统托盘 (Shell_NotifyIcon)

```cpp
NOTIFYICONDATAW m_nid;
m_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
m_nid.uCallbackMessage = WM_TRAYICON;
Shell_NotifyIconW(NIM_ADD, &m_nid);
```

### 5. 配置存储 (Windows Registry)

路径: `HKEY_CURRENT_USER\Software\HAUTNetworkGuard`

键值:
- `Username` - 用户名
- `Password` - 密码 (简单XOR混淆)
- `AutoSave` - 是否记住密码
- `HasConfigured` - 是否已配置
- `SkippedVersion` - 跳过的版本
- `LastUpdateCheck` - 上次检查更新时间

### 6. 线程模型

- 主线程: 消息循环 + UI更新
- 工作线程: HTTP请求 (std::thread)
- 同步: PostMessage 回调主线程

```cpp
// 工作线程完成后回调主线程
LoginResponse* pResult = new LoginResponse(result);
PostMessage(m_hwndMain, WM_LOGIN_RESULT, 0, reinterpret_cast<LPARAM>(pResult));
```

## 类架构

```
Application (单例)
├── TrayIcon         - 系统托盘图标
├── SrunAPI          - 网络API
│   ├── HttpClient   - HTTP请求
│   └── SrunEncryption - 加密
├── AppConfig (单例) - 配置管理
├── UpdateChecker (单例) - 更新检测
└── Windows
    ├── SettingsWindow   - 设置
    ├── AboutWindow      - 关于
    ├── UpdateWindow     - 更新提示
    └── DashboardWindow  - 可视化面板
```

## 消息定义

```cpp
#define WM_TRAYICON         (WM_USER + 1)   // 托盘图标消息
#define WM_UPDATE_STATUS    (WM_USER + 2)   // 状态更新
#define WM_LOGIN_RESULT     (WM_USER + 3)   // 登录结果
#define WM_LOGOUT_RESULT    (WM_USER + 4)   // 注销结果
#define WM_UPDATE_AVAILABLE (WM_USER + 5)   // 发现更新

#define TIMER_STATUS_CHECK  1               // 状态检测定时器
#define TIMER_UPDATE_CHECK  2               // 更新检测定时器

#define STATUS_CHECK_INTERVAL   3000        // 3秒
#define UPDATE_CHECK_INTERVAL   86400000    // 24小时
```

## 编译配置

```cmake
# 静态链接CRT (单文件exe)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# Windows子系统 (无控制台)
set(CMAKE_WIN32_EXECUTABLE ON)

# 链接库
target_link_libraries(${PROJECT_NAME} PRIVATE
    winhttp comctl32 shell32 advapi32 gdi32 user32 ole32 uuid
)
```

## 与 macOS 版本对比

| 功能 | macOS | Windows |
|------|-------|---------|
| 系统托盘 | NSStatusItem | Shell_NotifyIcon |
| 菜单 | NSMenu | CreatePopupMenu |
| 窗口 | NSWindow | CreateWindowEx |
| HTTP | URLSession | WinHTTP |
| 配置存储 | UserDefaults | Registry |
| 通知 | UNUserNotificationCenter | NIF_INFO 气泡 |
| 编程语言 | Swift | C++ |

## 新增功能 (相比 macOS)

1. **可视化面板** (DashboardWindow)
   - 详细网络状态显示
   - 流量进度条
   - 快捷操作按钮

## 文件清单

| 文件 | 用途 |
|------|------|
| src/main.cpp | 入口点 |
| src/Application.h/cpp | 应用主类 |
| src/core/SrunEncryption.h | SRUN3K加密 |
| src/core/SrunAPI.h | 网络API |
| src/core/NetworkStatus.h | 状态结构 |
| src/core/UpdateChecker.h | 更新检测 |
| src/config/AppConfig.h | 配置管理 |
| src/ui/BaseWindow.h | 窗口基类 |
| src/ui/TrayIcon.h | 系统托盘 |
| src/ui/SettingsWindow.h | 设置窗口 |
| src/ui/AboutWindow.h | 关于窗口 |
| src/ui/UpdateWindow.h | 更新窗口 |
| src/ui/DashboardWindow.h/cpp | 可视化面板 |
| src/utils/Logger.h | 日志 |
| src/utils/StringUtils.h | 字符串工具 |
| src/utils/HttpClient.h | HTTP客户端 |
| src/resource/resource.h | 资源ID |
| src/resource/resource.rc | 资源脚本 |
| src/resource/manifest.xml | 应用清单 |

## 开发注意事项

1. 所有字符串使用宽字符 (wchar_t, std::wstring)
2. Win32 API 统一使用 W 后缀版本
3. HTTP响应为 UTF-8，需转换为宽字符
4. 工作线程不能直接操作UI，必须通过 PostMessage
5. 内存分配后通过 PostMessage 传递指针，接收方负责释放

## 调试方法

1. 使用 Debug 版本构建: `build.bat debug`
2. 日志输出到 OutputDebugString
3. 使用 DebugView 或 VS 调试器查看日志
