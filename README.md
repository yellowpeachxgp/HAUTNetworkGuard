# HAUT Network Guard

河南工业大学校园网自动登录工具 - 支持 macOS、Windows 和 OpenWrt 三平台

## 功能特性

- **自动监控**: 默认每30秒自动检测网络连接状态（可调 30-300 秒）
- **自动重连**: 检测到断线后自动尝试重新登录
- **开机自启**: 支持开机自动启动，保持网络始终连接
- **系统托盘**: 最小化到系统托盘/菜单栏，静默运行
- **系统通知**: 登录/注销状态变化时推送通知
- **配置保存**: 按平台使用 Keychain、DPAPI 或受限 UCI 配置存储凭据，支持记住密码
- **更新检测**: 可视化更新窗口，显示版本号和更新日志

## 系统要求

### macOS
- macOS 11.0 (Big Sur) 或更高版本

### Windows
- Windows 10 或更高版本
- 64位系统

### OpenWrt
- OpenWrt 19.07 或更高版本
- 建议安装: lua, curl

## 下载安装

前往 [Releases](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases) 页面下载最新版本。

下一版正式 Release 将同时提供 `SHA256SUMS` 和 `OpenWrt-SHA256SUMS`。已发布的 v1.3.18 是历史资产，当前没有这两个清单；请不要把 v1.3.18 的桌面文件当作已完成的可审计发布。具体回读见 [发布资产审计](docs/RELEASE_ASSET_AUDIT_2026-09-09.md)。

### macOS

1. 下载 `HAUTNetworkGuard.dmg`
2. 打开 DMG 文件，将应用拖入 Applications 文件夹
3. 双击运行

> **注意**: 首次打开可能提示"无法验证开发者"，请使用以下任一方法解决：
>
> **方法一（推荐）**: 右键点击应用 → 选择"打开" → 在弹窗中点击"打开"
>
> **方法二**: 在终端执行：
> ```bash
> xattr -cr /Applications/HAUTNetworkGuard.app
> ```
> 然后重新打开应用即可。

### Windows

1. 下载 `HAUTNetworkGuard-Windows.zip`
2. 解压后运行 `HAUTNetworkGuard.exe`（无需安装）

> **技术栈**: Windows 版本使用 Qt 6 (C++) 开发，提供原生系统托盘支持。
> 
> 构建方式: GitHub Actions 自动编译，推送 tag 时自动发布。

### OpenWrt

详见 [OpenWrt/README.md](OpenWrt/README.md)

**固定版本安装（推荐生产环境）：**
```bash
wget -qO- https://raw.githubusercontent.com/yellowpeachxgp/HAUTNetworkGuard/v1.3.19/OpenWrt/install-online.sh | sh -s -- v1.3.19
```

> v1.3.19 起正式 Release 提供 `OpenWrt-SHA256SUMS`，固定版本安装会在切换前校验完整清单。

**安装最新 main（适合测试）：**
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

### 开发中版本的自动重连行为

当前工作树正在整合下一版，以下行为尚未发布到现有下载资产：

- Windows 和 macOS 启动时先检测校园网状态，检测异常时等待下一轮；确认离线后才尝试自动登录。
- 登录失败后至少等待 60 秒再自动重试，连续失败时逐步延长至 5 分钟。修改凭据后可以立即手动登录。
- 状态接口返回空正文或无法解析的内容时显示异常并等待下一轮检测，不会直接当作离线触发自动登录；只有明确返回“当前不在线”才会进入自动登录判断。
- 手动注销会暂停本次运行期间的自动重连，包括网关返回“当前未在线”的情况。点击“立即登录”解除暂停；自动登录开关仍然有效。
- 不勾选“记住密码”时，本次会话可以使用已输入密码重连；退出后需要重新输入。Windows 的手动登录也会读取当前“记住密码”选项。

实现与验收范围见 [状态机契约](docs/STATE_MACHINE_CONTRACT.md)、[工程台账](docs/IMPLEMENTATION_LEDGER.md) 和[三端真实设备验收矩阵](docs/REAL_DEVICE_ACCEPTANCE_MATRIX.md)。

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

以下为当前核心结构示意，非穷举清单：

```
HAUTNetworkGuard/
├── macOS/                      # macOS 版本 (Swift)
│   ├── Sources/
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── Config.swift
│   │   ├── Logger.swift
│   │   ├── Encryption.swift
│   │   ├── SrunProtocol.swift
│   │   ├── SrunAPI.swift
│   │   ├── StatusBarController.swift
│   │   ├── SettingsWindow.swift
│   │   ├── AboutWindow.swift
│   │   ├── UpdateChecker.swift
│   │   ├── UpdateWindow.swift
│   │   └── LaunchManager.swift
│   ├── Info.plist
│   ├── build.sh
│   ├── tests/
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
│   │   ├── protocol_utils.h/cpp # 响应分类/状态解析纯逻辑
│   │   ├── logger.h/cpp       # 文件日志与脱敏
│   │   └── trayicon.h/cpp     # 系统托盘
│   ├── tests/
│   │   └── windows_smoke_tests.cpp
│   ├── CMakeLists.txt
│   └── AIREADME.md
│
├── Windows-Rust-Deprecated/    # ⚠️ 已弃用的历史实现，仅供参考
│   ├── src/
│   ├── Cargo.toml
│   └── DEPRECATED.md
│
├── OpenWrt/                    # OpenWrt 版本 (Lua)
│   ├── files/
│   │   ├── usr/lib/haut-network-guard/
│   │   │   ├── main.lua
│   │   │   ├── api.lua
│   │   │   ├── log.lua
│   │   │   ├── protocol.lua
│   │   │   └── crypto.lua
│   │   ├── etc/init.d/
│   │   └── etc/config/
│   ├── install.sh
│   ├── install-online.sh
│   ├── upgrade-online.sh
│   ├── uninstall.sh
│   └── README.md
│
├── docs/
│   ├── LOGGING_CONTRACT.md
│   ├── SRUN3K_PROTOCOL_SPEC.md
│   └── PROJECT_BASELINE_AND_PLAN_2026-04-11.md
│
├── tests/
│   ├── fixtures/protocol_vectors.json
│   ├── test_protocol_contract.py
│   ├── test_docs_contract.py
│   ├── test_version_contract.py
│   ├── test_release_contract.py
│   ├── test_logging_contract.py
│   ├── test_session_policy.py
│   ├── test_macos_uninstall.py
│   ├── test_openwrt_installation.py
│   ├── test_openwrt_modules.lua
│   ├── test_openwrt_runtime.lua
│   ├── test_openwrt_session.lua
│   └── test_openwrt_log.lua
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
| 加密 | SRUN3K | SRUN3K | SRUN3K |
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
3. 执行 `macOS/uninstall.sh` 可同时清理 Keychain 凭据和应用配置

### Windows

1. 删除解压后的 `HAUTNetworkGuard-Windows/` 目录
2. （可选）运行 `regedit`，删除：
   - `HKEY_CURRENT_USER\Software\HAUTNetworkGuard`
   - `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` 下的 `HAUTNetworkGuard` 项

### OpenWrt

```bash
cd OpenWrt
./uninstall.sh
```

## 版本历史

### v1.3.19 (2026-09)

- **Windows 学生流程**
  - 修复开机自启但尚未配置账号时直接隐藏到托盘的问题；现在会显示首次配置窗口。
  - 保存学号和密码成功后立即发起一次状态检测，不需要额外点击或等待定时器。
  - 新增启动行为契约测试，并加入 CI 校验。
- **三端状态机与网络可靠性**
  - 状态检查、登录、注销统一串行处理，过期回调不会覆盖当前状态。
  - 明确区分在线、离线、异常响应和网络失败；无法解析的空响应不会误触发自动登录。
  - 登录失败采用有界退避，手动注销会暂停当前进程内自动重连，手动登录可恢复。
  - macOS 直连客户端增加物理接口选择、连接超时、HTTP 状态行和非 2xx 响应校验。
- **协议与 OpenWrt**
  - 收紧 JSONP/CSV 数字、IPv4、空字段、尾随字段和错误优先级边界。
  - 接受社区 PR #3，修复 Lua 5.3 浮点格式化导致的运行时崩溃，并完成 Lua 5.1/5.3 回归。
  - OpenWrt 安装、升级、回滚、卸载和配置保留路径采用 staging 与原子切换，日志对账号、密码和编码字段兜底脱敏。
- **凭据与隐私**
  - macOS 使用 Keychain，Windows 使用 DPAPI，关闭“记住密码”时删除持久化密码并保留其他设置。
  - 凭据写入、回读和删除失败会安全中止，不覆盖旧配置；诊断信息和请求日志不包含密码或完整账号。
- **桌面体验**
  - macOS 首次配置、菜单栏窗口、设置保存、托盘恢复和无障碍焦点链路完成回放测试。
  - Windows 主窗口、托盘显示/隐藏、键盘焦点、错误提示和配置保存失败路径完成 Qt 回放测试。
- **安装与发布**
  - `VERSION` 成为三端统一版本源，Windows、macOS、OpenWrt、文档和 User-Agent 保持一致。
  - Release 同时提供 `SHA256SUMS` 和 `OpenWrt-SHA256SUMS`，固定版本 OpenWrt 安装/升级会校验清单后再切换。
  - GitHub Actions 完成 Windows ZIP、macOS DMG、OpenWrt 文件清单和三端基础测试后自动创建 Release。
- **验证结果**
  - Windows Qt CTest 5/5 通过；macOS 协议、凭据和 UI smoke 通过；OpenWrt Lua 5.1/5.3 模块、运行时和会话测试通过。
  - 本版本未把真实校园网设备和长期运行记录冒充为自动化测试结果，现场验证仍按设备环境执行。

### v1.3.18 (2026-04)
- **macOS**: 修复菜单栏“账号设置”窗口无法稳定打开的问题
  - 修正 `SettingsWindowController` 的构造路径，避免错误落入 `NSWindowController(window: nil)` 导致窗口控制器存在但实际无窗口
  - 菜单栏实用窗口统一走受控展示链路，补齐激活策略切换、前台激活、跨 Space 展示与关闭后恢复 `accessory` 状态
  - 关于窗口、更新窗口与账号设置窗口共用同一套生命周期管理，减少窗口复开和前后台切换边界问题
- **macOS**: 新增真实 UI smoke test，覆盖设置/关于/更新窗口主链路
  - 新增 `macOS/tests/run_ui_smoke_tests.sh`
  - 新增窗口打开、关闭、激活策略恢复的自动化断言
  - GitHub Actions macOS job 接入 UI smoke test，发版前自动验证菜单栏窗口链路
- **全平台**: 版本号与文档同步更新为 1.3.18
  - Windows / macOS / OpenWrt 显示版本、User-Agent、安装命令、AI 文档和契约测试全部对齐

### v1.3.17 (2026-04)
- **macOS**: 修复更新检测在代理/PAC/TLS 环境下的 HTTP2/安全连接失败
  - 更新检测主链路改为 `curl --http1.1 --noproxy '*'`，避免被本地 `127.0.0.1:7890` 等系统代理链路劫持
  - 新增更新检测 transport mode、代理快照、底层错误链与回退结果日志
  - 保留 `URLSession` 作为失败回退，提升复杂网络环境下的兼容性
- **macOS**: 修复校园网直连客户端超时与错误可观测性
  - `DirectHTTPClient` 改为非阻塞 `connect + poll` 超时控制，避免状态检查异常拖到约 75 秒
  - `send/recv/connect` 错误统一映射为可读日志，不再退化为 `error 0/2`
  - 补充主机解析、接口绑定、响应长度等诊断字段，便于后续排障
- **全平台**: 版本号与文档同步更新为 1.3.17
  - Windows / macOS / OpenWrt 显示版本、User-Agent、安装命令、AI 文档和契约测试全部对齐

### v1.3.16 (2026-04)
- **Windows**: 修复开机自启动与交互状态机收口问题
  - 自启动改为注册表 `Run` 主链路，避免与 Startup 兜底脚本双重触发导致双实例竞争
  - 手动注销对 `not_online` 结果不再错误进入“保持离线”状态
  - 主窗口与托盘菜单统一在线/离线/忙碌态，托盘图标新增在线/离线状态标识
- **macOS**: 修复首次运行与菜单栏生命周期边界
  - 首次运行关闭设置窗口时改为安全退出，避免 `LSUIElement` 模式下进入不可恢复隐藏状态
  - 手动注销对“当前未在线”结果不再误伤自动登录
  - 修复关于窗口控制器释放、更新检查重复触发和物理网卡解析冷启动竞态
- **OpenWrt**: 强化网络错误分类、升级幂等与脚本安全性
  - `curl` 退出码进入日志与状态分类，空状态响应重新按协议判定为离线
  - 升级脚本新增版本方向提示、分阶段下载和失败回滚
  - 卸载脚本默认保留配置，需显式 `--purge-config` 才删除
- **协议/测试**: 收紧三端 CSV 状态解析，避免脏响应被误判为在线
  - Windows/macOS/OpenWrt 协议解析统一校验 IPv4 和数值字段
  - 新增跨平台异常 CSV 响应回归用例
- **全平台**: 版本号同步更新为 1.3.16

### v1.3.15 (2026-04)
- **文档**: 修正文档与当前代码、Release 资产和安装链路的不一致
  - 主 README 修正为实际发布资产 `HAUTNetworkGuard-Windows.zip` 和 `HAUTNetworkGuard.dmg`
  - OpenWrt 文档同时提供 `main` 跟随安装和固定版本安装示例
  - Windows/macOS 平台内部技术文档更新到当前架构与版本
- **日志**: 统一三端请求日志字段与账号脱敏规则
  - 统一 `action / phase / class / elapsed_ms` 语义
  - 修复 Windows 用户名加密日志泄漏原始账号的问题
  - OpenWrt 补充 `curl` 耗时和 HTTP 状态码日志
- **测试/CI**: 新增协议、文档和 OpenWrt 纯逻辑 contract tests
  - 增加共享协议向量、OpenWrt 配置清洗与登录响应分类测试
  - CI 新增 docs/protocol contract 校验，并扩大 OpenWrt shell 校验范围
- **架构**: 提炼共享规范与可测试纯逻辑
  - macOS 日志模块拆分为独立 `Logger.swift`
  - OpenWrt 配置清洗与登录响应分类抽离到 `protocol.lua`
- **全平台**: 版本号同步更新为 1.3.15

### v1.3.14 (2026-04)
- **Release/OpenWrt**: 修复版本发布与一键安装链路漂移
  - Release 页面中的 OpenWrt 安装命令改为固定到当前 tag，避免发布页安装到未来的 `main` 内容
  - `install-online.sh` 支持按版本参数拉取对应文件，并在下载失败时立即终止
- **CI**: 增加 OpenWrt 脚本校验
  - GitHub Actions 新增 Lua 语法检查和 Shell 语法检查，发布前即可发现 OpenWrt 脚本错误
- **全平台**: 版本号同步更新为 1.3.14

### v1.3.13 (2026-04)
- **Windows**: 修复“未勾选记住密码仍被持久化”的问题
  - 配置保存现在遵循 `记住密码` 开关，关闭时仅保留当前会话密码
- **Windows**: 收紧 API 调试日志并补充请求级追踪
  - 为登录/注销/状态检测增加请求 ID、耗时、响应分类和并发状态日志
  - 移除认证请求体预览，避免编码后的认证字段进入日志
- **全平台**: 版本号同步更新为 1.3.13

### v1.3.12 (2026-04)
- **OpenWrt**: 修复特定固件环境下自动登录循环报 `E2531: User not found`
  - 自动登录每轮重读并清洗 UCI 配置，去除 BOM、CRLF 和首尾空白
  - 登录 POST 改为临时文件 + `curl --data-binary`，避免 shell 拼接污染请求体
  - 新增更详细的配置快照、请求摘要、响应预览和离线判定日志
- **Windows**: 修复开机自启动不稳定问题
  - 保留注册表 `Run` 自启动，同时写入 `Startup` 目录脚本做兜底
  - 新增注册表回读、自启动脚本状态、启动来源与托盘初始化日志
- **macOS**: 强化 LaunchAgent 管理
  - 设置开机自启动时同步执行 `launchctl load/unload`
  - 新增启动配置、状态检测、自动登录与窗口动作调试日志
- **文档**: 修正 OpenWrt 依赖和协议描述，统一版本号到 1.3.12

### v1.3.11 (2026-03)
- **Windows**: 开机自启动场景改为静默后台运行，不再弹出主窗口
  - 自启动注册表命令新增 `--startup` 参数
  - 程序启动时识别 `--startup` 后直接托盘常驻
  - 已开启自启动的旧配置会自动迁移到新命令
- **全平台**: 版本号同步更新为 1.3.11

### v1.3.10 (2026-03)
- **全平台**: 连通性检测限频，默认/最小检测间隔统一为 30 秒
  - Windows 检测间隔调整为 30-300 秒
  - macOS 检测间隔调整为 30-300 秒
  - OpenWrt 启动时对配置间隔做 30-300 秒钳制
- **macOS**: 修复设置窗口生命周期问题，检测间隔滑条与保存动作可正常生效
- **文档**: 更新检测频率说明为默认 30 秒（可调 30-300 秒）

### v1.3.6 (2026-03)
- **macOS**: 修复 DMG 安装后提示"文件已损坏"
  - 构建流程添加 ad-hoc 代码签名，Gatekeeper 不再报"已损坏"
  - 用户可通过右键打开或 `xattr -cr` 绕过"无法验证开发者"提示
- **CI/CD**: macOS 构建环境固定为 `macos-14` (ARM64)
- **CI/CD**: Release 说明新增 macOS Gatekeeper 绕过指引
- **全平台**: 版本号同步更新为 1.3.6

### v1.3.5 (2026-01)
- **Windows/macOS**: 改进 IP 和时间显示
  - 使用 JSONP 格式解析状态响应（与 OpenWrt 一致）
  - 使用 `online_ip`、`sum_bytes`、`sum_seconds` 字段
  - 保留 CSV 格式回退支持
- **全平台**: 版本号同步更新为 1.3.5

### v1.3.4 (2026-01)
- **Windows**: 修复密码加密算法
  - 修正密钥索引方向（正向 → 反向）
  - 修正位编码算法（0x61 → 0x36/0x63）
  - 修正奇偶位交替逻辑
- **Windows**: 修复自动登录功能
  - 新增启动时自动登录
  - 新增断线自动重连开关
- **Windows/macOS**: 新增检测间隔设置
  - 支持 5-300 秒自定义间隔
  - 默认 30 秒（与 OpenWrt 一致）
- **全平台**: 版本号同步更新为 1.3.4

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
