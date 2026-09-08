# 本地验证记录

本记录描述 2026-09-09 工作树的已执行验证，不代表正式 Release 或全部产品路线图完成。

## macOS

- 实际主机：Darwin / ARM64，具备 Xcode 和 Command Line Tools。
- 完整构建所用工具链：Xcode Swift 6.2.4 + MacOSX26.2.sdk；通过同一 DEVELOPER_DIR 下的 xcrun 选择。
- 隔离测试：独立 UserDefaults 域、注入存储后端、随机 tests Keychain 服务名；正式应用单例不用于逻辑测试。
- 原生 Keychain 验证：直接回读、重建配置实例读取、迁移后清除旧值、取消记住密码、删除条目。
- 故障注入：读取失败后解锁重试、写入失败、假写入成功/回读不一致、删除失败时停止持久化读取。
- AppKit UI smoke：设置/关于/更新窗口打开、关闭、复开与 accessory 激活策略恢复，通过。
- 构建与 ad-hoc 签名：通过；`codesign --verify --strict` 通过。
- DMG：构建、`hdiutil verify`、只读挂载、包内严格签名检查、包内可执行文件与构建文件 SHA-256 比对通过，验证后已卸载挂载点。

执行入口：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash macOS/tests/run_smoke_tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash macOS/tests/run_ui_smoke_tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HAUT_BUILD_DIR="$PWD/macOS/build/goal-validation" bash macOS/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer HAUT_BUILD_DIR="$PWD/macOS/build/goal-validation" bash macOS/create-dmg.sh
codesign --verify --strict macOS/build/goal-validation/HAUTNetworkGuard.app
hdiutil verify macOS/build/goal-validation/HAUTNetworkGuard.dmg
```

历史基线 DMG SHA-256：`8805c182ef14c6d67406aeedccdb3c9a262b765d4ac1bed37113cc0eba35dd32`。
产物位于忽略目录 `macOS/build/goal-validation/`，对应状态机改造前的工作树，不包含本轮新的会话策略。它不是 GitHub Release 资产；ad-hoc 签名不代表 Developer ID 公证或 Gatekeeper 自动放行。

## 桌面会话策略与 Qt 本地验证

本轮新增的会话策略已接入正式控制器，测试没有调用校园网：

- 最新协议边界回归也通过：JSON 小数、负数和超出 `9007199254740991` 的计数回退为 0；quoted numeric 小数和 CSV 小数/负数标记为 `unparsed`；JSON 非法 IP 与空身份不再判定为在线。Swift smoke、Qt CTest、Lua 5.1/5.3 runtime、Python 向量均覆盖这一规则。
- Swift / C++ 使用同一份 `tests/fixtures/session_scenarios.txt`：9 个场景、每端 142 条事件断言通过。
- Swift/C++ 会话策略另完成加速模拟 7 天逐分钟 soak（10,080 次检测），断言无重叠操作、退避有界和最终状态空闲；不代表真实设备 7 天运行。
- macOS 正式 StatusBarController：27 条回放断言通过，覆盖检测/认证串行、手动失败后的退避、旧回调、注销后暂停和显式恢复，以及自动重试提示的实际剩余秒数；同一入口继续执行窗口生命周期 smoke，通过。
- 已通过 Homebrew 安装 Qt 6.11.1（qtbase 及依赖）。使用 AppleClang 17 + MacOSX26.2.sdk，Windows 目录的完整应用编译、Qt 元对象信号连接、配置测试和主窗口回放通过。
- CTest 共 5 项全部通过：`session_policy_tests`、`windows_smoke_tests`、`controller_session_tests`、`credential_failure_tests`、`instance_guard_tests`；正式 MainWindow 的 Qt 信号、按钮、首次空配置拒绝和保存失败回放为 64 条断言，另有单实例锁竞争断言。
- Windows 版本治理回归：CMake 从根目录 `VERSION` 读取版本，主程序、窗口和 User-Agent 使用同一编译宏；Qt 5 项 CTest 全部通过。
- macOS 版本治理回归：构建脚本从根目录 `VERSION` 生成 Swift 版本源并替换 Info.plist；逻辑/UI smoke、严格签名和包内版本回读通过。
- macOS 卸载脚本回归：临时 LaunchAgent、应用目录、Keychain/defaults 命令均使用隔离替身；停止失败时文件保持不变，成功时清理目标并复核残留。
- macOS 网络接口选择回归：UI smoke 覆盖有线优先、Wi‑Fi 回退、其他接口兜底和空接口返回 nil；未连接真实校园网。
- Qt 主窗口回放同时核对学号、密码、登录和注销控件的无障碍名称；设置了从凭据到诊断复制的明确 Tab 顺序。
- macOS 设置窗口为学号、密码、检测间隔、记住密码、开机自启动、自动登录和保存控件设置无障碍名称，并显式串联键盘焦点和首次焦点；完整编译与 UI smoke 通过，仍需人工辅助功能检查。
- Windows 配置测试及主窗口回放使用随机临时 INI，禁用系统自启动集成、正式日志和桌面通知。覆盖密码回读、取消记住密码、冷启动残留清理，以及点击登录时采用当前复选框；单实例锁测试确认第二个实例无法取得同一用户锁。
- `Q_OS_WIN` 分支在这台 macOS 主机不执行，但运行 34232164603 已在 Windows Server 2022 执行实际 DPAPI 保存/解码与独立配置回读；本机结果仍不能证明 Windows 注册表自启动、真实桌面交互或跨账号迁移。
- 凭据故障回放另有 20 条断言：编码失败、解码不符、真实 QSettings 自定义写入后端拒绝写盘、旧文件逐字节保留、运行配置恢复、同一实例故障恢复后重试、不可读旧凭据的保留与显式清除。测试存储后端使用临时目录。
- Qt 窗口保存失败会显示错误、保留输入、阻止提交登录；系统自启动变更延迟到配置保存成功之后。真实 Windows 注册表多键写入的失败恢复尚待原生验证。
- Swift、Qt 和 Lua 日志测试覆盖 JSON、CSV、表单、HTML、非结构化正文中的账号、密码和编码字段；正文只输出长度摘要。Lua 5.1/5.3 还检查传给系统 logger 的参数没有测试凭据。
- `tests/test_logging_contract.py` 已接入 CI，静态检查三端日志调用不会拼接密码、编码值或完整响应，并确认响应摘要保留 `<redacted>` 标记。
- macOS 菜单和 Windows 主窗口提供脱敏诊断复制；本地控制器测试检查诊断文本包含版本/状态信息且不含测试账号或密码。

执行入口（仓库根目录）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 tests/test_session_policy.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash macOS/tests/run_ui_smoke_tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -S Windows \
  -B macOS/tests/build/qt-validation -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qtbase \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk
cmake --build macOS/tests/build/qt-validation --parallel 4
ctest --test-dir macOS/tests/build/qt-validation --output-on-failure
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  HAUT_BUILD_DIR="$PWD/macOS/build/session-validation" bash macOS/build.sh
codesign --verify --deep --strict macOS/build/session-validation/HAUTNetworkGuard.app
```

Qt 原始结果保存在忽略目录 `macOS/tests/build/qt-validation/Testing/Temporary/LastTest.log`；Swift 最新应用构建日志为 `macOS/tests/build/session-build.log`。新的 App 和 DMG 位于 `macOS/build/session-validation/`，没有启动正式应用。

当前集成验证 App 可执行文件 SHA-256：`7b0c3db420668779850c37f6e1f8d26d57afe290efe90274820cfb3c0475bff8`；DMG SHA-256：`09acd6ea21b93cb4785b374df778dba38680db4a6bebbb10acfcffe5c936b7ac`。产物位于忽略目录 `macOS/build/session-validation/`，包含认证请求闸门；已通过严格签名和 `hdiutil verify`，不是 GitHub Release 资产。

## Lua 与 OpenWrt

Lua 源码来自 [官方下载区](https://www.lua.org/ftp/)，下载后核对官方 SHA-256：

| 版本 | 源码 SHA-256 |
|---|---|
| 5.1.5 | `2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333` |
| 5.3.6 | `fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60` |

构建于忽略目录 `macOS/tests/build/lua-runtimes/`，没有替换系统 Lua。两种解释器分别执行：

1. `tests/test_openwrt_modules.lua`：通过。
2. `tests/test_openwrt_runtime.lua`：通过，实际执行 API 和一轮 main 循环，curl/UCI/文件边界模拟；覆盖 PR #3 崩溃、小数流量/时长、JSON 空格、URL 编码、登录/注销、异常与网络失败。
3. `tests/test_openwrt_installation.py`：每种解释器 20 项通过，共 40 项。实际执行正式 Shell 脚本和真实 Lua 的安装/卸载路径，覆盖离线与在线场景，只对安装根目录、下载和服务边界注入临时环境。

故障注入覆盖：新装、重装保留配置、下载失败、半截 init 文件清理、非法 Lua、启用失败时恢复旧版本或移除新装、切换失败回滚、升级健康失败恢复、保持停止状态、下载失败不停止旧服务、备份清理失败不删除新安装。

校验 Lua 文件使用环境变量传递文件名，调用 `loadfile` 而不执行返回函数；不再把目标文件作为解释器脚本参数。该区别遵循 [Lua 解释器执行规则](https://www.lua.org/manual/5.1/manual.html#6)，故障注入中的 Lua 文件包含禁止执行的标记，误执行会使测试失败。

```bash
HAUT_TEST_LUA=lua5.1 python3 tests/test_openwrt_installation.py
HAUT_TEST_LUA=lua5.3 python3 tests/test_openwrt_installation.py
lua5.1 tests/test_openwrt_runtime.lua
lua5.3 tests/test_openwrt_runtime.lua
```

本地运行时将 lua5.1/lua5.3 替换为上述忽略目录中的绝对路径。离线安装与固定版本在线安装/升级现在都在切换前完成真实 Lua/服务脚本校验；卸载路径显式停止并禁用服务，默认保留配置并支持清除配置，停止失败时不会删除文件。在线路径消费 Release 的 `OpenWrt-SHA256SUMS`，两种解释器下各 20 项测试覆盖哈希篡改、下载失败、启用失败、回滚和卸载语义。在线安装完成提示从下载的 `version.lua` 读取，并由版本契约测试保护。路由器 procd、真实 UCI、存储耗尽/断电和校园网接口没有被这些测试替代。

## 契约与仍未验证内容

Python 协议、文档、版本契约检查已通过；Shell 语法与 git diff --check 已检查。CI 工作流现已加入 PR/main 触发及 Lua 5.1/5.3 模块、运行和安装故障回归。

尚未达到产品完成门禁的项目：真实 Windows/macOS 桌面重复启动与睡眠唤醒、OpenWrt 路由器重启和真实状态请求、OpenWrt 下载端消费 Release 哈希、Developer ID/公证、跨签名升级、完整日志字段审计、真实校园网首次登录/断线恢复/注销/重启、完整学生旅程和 7 天稳定性。

## 集成分支与原生 CI

- 草稿集成：[PR #4](https://github.com/yellowpeachxgp/HAUTNetworkGuard/pull/4)。当前分支与远端跟踪分支一致，`main` 没有被改写。
- [运行 34256596956](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34256596956) 对应协议身份边界提交 `4fd5634`：Windows、macOS、OpenWrt 三项 job 全部通过；非法 JSON IP 与空身份回归、Qt/macOS/Lua 协议测试、安装资产回读门禁通过。
- [运行 34254790864](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34254790864) 对应最新会话策略 7 天加速 soak 提交 `3c1242e2`：Windows、macOS、OpenWrt 三项 job 全部通过；会话策略、安装/升级/卸载矩阵及安装资产回读门禁通过。
- [运行 34253578251](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34253578251) 对应 Windows 首次空配置拒绝提交（Artifact 首次提交遇到中间层 403 后重跑成功）：Windows、macOS、OpenWrt 三项 job 全部通过；空配置回放、有线优先/Wi‑Fi 回退/其他接口兜底、卸载脚本隔离测试、双 Lua 安装/升级/卸载矩阵和安装资产回读门禁通过。
- [运行 34240638078](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34240638078) 已执行安装资产回读门禁：Windows ZIP 解压检查、macOS DMG 只读挂载/包内签名检查和 OpenWrt 双 Lua 全量测试均通过；Release job 因草稿 PR 按预期跳过。
- [运行 34240147670](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34240147670) 对应四端错误码边界提交：Windows、macOS、OpenWrt 三项 job 全部通过；短码和超长码回归已纳入协议契约。
- [运行 34237976134](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34237976134) 对应提交 `5bdb6ffad52d86debfc1c6715fc36fef13c229bc`：Windows、macOS、OpenWrt 三项 job 全部通过；Release job 因草稿 PR 按预期跳过。
- [运行 34235952524](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34235952524) 对应提交 `53a99b30bb446481a6722d2bbf3ddc5a03354e3f`：Windows、macOS、OpenWrt 三项 job 全部通过；Release job 因草稿 PR 按预期跳过。
- [运行 34234650584](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34234650584) 对应提交 `606419db821ec788cae788fe9a908fb905a6934a`：Windows、macOS、OpenWrt 三项 job 全部通过；Release job 因草稿 PR 按预期跳过。
- [运行 34234043075](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34234043075) 对应提交 `223251964a9421222b6e53e49d52982f03eeb7bf`：Windows、macOS、OpenWrt 三项 job 全部通过；固定版本 OpenWrt 清单校验、哈希篡改回滚和两种 Lua 安装/升级 15 项矩阵均通过。
- [运行 34232164603](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34232164603) 对应桌面详情改造提交 `bd53b39eb9dc533e28210ffa79885ed22d9b3c2c`：Windows、macOS、OpenWrt 三项 job 和 Release 前置门禁全部通过。
- [运行 34229762182](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34229762182) 对应协议安全范围改造提交 `66684f3837e67fe241225106af2517816c5ca3a6`：三平台构建、协议契约、OpenWrt 双版本回归和桌面测试全部通过。
- [运行 34231666520](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34231666520) 对应单实例与 OpenWrt 策略提交 `b29aebca796c6dcf0c975349daa9d79f4edf088a`：Windows、macOS、OpenWrt 全部通过。
- [运行 34226445948](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34226445948) 首次验证唯一 DMG 临时目录修复；Windows Server 2022 / Qt 6.6 原生构建、5 项 CTest、DPAPI 回读、运行库部署和 ZIP 上传均通过，macOS DMG 创建和签名也通过。
- 更早的 `windows-latest` 运行因镜像为 `windows-2025-vs2026` 而找不到 VS 2022 生成器；现已固定 `windows-2022`，其 [官方软件清单](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md#visual-studio-enterprise-2022)包含 VS 2022。
- 从运行 34226445948 下载的预览资产保存在忽略目录 `macOS/tests/build/ci-34226445948/`：Windows ZIP SHA-256 为 `17c96a7a82040f3d3fdd82131fc2a44c7db50abdfc97c2245b4f82b6b2d30938`，macOS DMG SHA-256 为 `33e4a674cc43db3b1ae67d71428fc41d309416ee977d1a1bb3c183c13e9c4b01`。ZIP 回读确认包含可执行文件、Qt Core/Gui/Network/Widgets DLL 和 `platforms/qwindows.dll`；没有在本机启动 Windows 资产。
- 运行 34225154211 曾在 macOS 打包阶段触发 `Resource busy`，唯一临时目录修复已由后续运行验证。所有 CI 运行的 Release job 因草稿 PR 按预期跳过；没有合并到 `main`，没有发布新版本。
