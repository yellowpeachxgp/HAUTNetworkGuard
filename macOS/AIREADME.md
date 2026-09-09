# HAUT Network Guard - AI 技术文档 (macOS)

> 本文件用于后续开发快速理解当前 macOS 版本实现。内容已对齐 `v1.3.20`。

## 项目概述

HAUT Network Guard macOS 版本是常驻菜单栏应用，负责状态监控、自动登录、更新检测和开机自启动。

### 当前版本

- **版本号**: 1.3.20
- **最后更新**: 2026-04
- **构建方式**: `swiftc` + `build.sh`

## 当前实现

### 固定端点

- 状态检查: `http://172.16.154.130/cgi-bin/rad_user_info`
- 登录/注销: `http://172.16.154.130:69/cgi-bin/srun_portal`

### 关键模块

- `Sources/Logger.swift`
  - 文件日志
  - `HAUT_LOG_LEVEL` 日志级别
  - 请求 ID 与账号脱敏
- `Sources/SrunAPI.swift`
  - 状态检查、登录、注销
  - 响应分类与请求级日志
- `Sources/SrunProtocol.swift`
  - 登录响应分类
  - JSONP/CSV 状态解析
- `Sources/DirectHTTPClient.swift`
  - 使用物理接口直连校园网网关
  - 尽量绕过代理/TUN 路由影响
- `Sources/StatusBarController.swift`
  - 菜单栏 UI
  - 自动登录状态机
  - 更新入口与通知
- `Sources/LaunchManager.swift`
  - LaunchAgent 管理
  - `launchctl load/unload`
  - stdout/stderr 落盘
- `Sources/SettingsWindow.swift`
  - 凭据、自动登录、开机自启动、检测间隔配置

## 当前行为约定

### 自动登录

- 启动先检测；只有协议解析为离线时才考虑自动登录，错误响应不触发。
- `SessionPolicy.swift` 串行管理检测、登录和注销，并拒绝过期回调。
- 手动和自动登录失败均从完成时起冷却，基础间隔至少 60 秒，连续失败逐步增加至 300 秒；用户可手动纠正后立即登录。
- 手动注销在当前进程内暂停自动重连，包括返回当前未在线或注销失败；后续检测不撤销暂停，手动登录解除暂停。自动登录总开关仍然有效。
- `tests/run_ui_smoke_tests.sh` 同时回放正式控制器的网络事件和窗口生命周期；使用独立配置、模拟服务和时钟。

### 开机自启动

- 使用 LaunchAgent:
  - `~/Library/LaunchAgents/cn.ehaut.networkguard.plist`
- 可执行路径:
  - 默认使用当前应用自身的 `Bundle.main.executablePath`
  - 正式安装场景通常为 `/Applications/HAUTNetworkGuard.app/Contents/MacOS/HAUTNetworkGuard`
- 日志路径:
  - `~/Library/Logs/HAUTNetworkGuard/launchd.stdout.log`
  - `~/Library/Logs/HAUTNetworkGuard/launchd.stderr.log`

### 凭据存储

- 用户名持久化到 `UserDefaults`
- 密码在 `记住密码` 关闭时仅保留会话态；开启时保存到 macOS Keychain，旧 UserDefaults 密码仅在安全写入并回读成功后删除。失败会反馈给设置窗口。
- 自动测试注入独立配置域和存储后端；原生 Keychain 测试及 UI smoke 使用每次随机的 tests 服务名，不访问正式密码条目。
- 卸载脚本会删除 Keychain 凭据和 `cn.ehaut.networkguard` UserDefaults 配置

## 调试与排障

应用日志位于:

- `~/Library/Logs/HAUTNetworkGuard/app.log`

统一请求日志字段:

- `action`
- `phase`
- `class`
- `elapsed_ms`
- `account`

更新检测:

- 使用 GitHub Releases API
- 主链路优先走 `curl --http1.1 --noproxy '*'`
- 会记录 `transport_start/transport_ok/transport_error` 与系统代理快照
- 默认 24 小时检查一次
- 手动检测无论结果如何都回调 UI

## 构建与发布

### 本地构建

```bash
cd macOS
./build.sh
./create-dmg.sh
```

### 当前编译顺序

`build.sh` 目前显式编译以下核心文件，后续以 `build.sh` 为唯一事实源:

- `AppRuntime.swift`
- `Logger.swift`
- `Config.swift`
- `Encryption.swift`
- `SrunProtocol.swift`
- `DirectHTTPClient.swift`
- `SrunAPI.swift`
- `UpdateChecker.swift`
- `UpdateWindow.swift`
- `SettingsWindow.swift`
- `AboutWindow.swift`
- `LaunchManager.swift`
- `StatusBarController.swift`
- `AppDelegate.swift`
- `main.swift`

### Release 产物

- `HAUTNetworkGuard.dmg`
- `macOS/tests/run_smoke_tests.sh` 在 CI 中先于正式构建执行
- `macOS/tests/run_ui_smoke_tests.sh` 在 CI 中用于验证菜单栏窗口主链路

## 后续开发注意事项

1. 不要修改 `DirectHTTPClient` 的接口绑定语义，任何调整都需要做真实网络复测。
2. `Logger.swift` 是横切模块，后续不要再把日志实现塞回业务文件。
3. 菜单栏窗口相关修改后，必须同时更新 `run_ui_smoke_tests.sh` 覆盖的新路径。
4. 修改协议、更新逻辑或 LaunchAgent 行为后，同步更新主 README、本文件和 contract tests。
