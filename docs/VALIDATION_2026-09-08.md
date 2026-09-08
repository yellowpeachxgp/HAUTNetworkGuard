# 本地验证记录

本记录描述 2026-09-08 工作树的已执行验证，不代表正式 Release 或全部产品路线图完成。

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

- 最新协议边界回归也通过：JSON 小数、负数和超出 `9007199254740991` 的计数回退为 0；quoted numeric 小数和 CSV 小数/负数标记为 `unparsed`。Swift smoke、Qt CTest、Lua 5.1/5.3 runtime、Python 向量均覆盖这一规则。
- Swift / C++ 使用同一份 `tests/fixtures/session_scenarios.txt`：9 个场景、每端 142 条事件断言通过。
- macOS 正式 StatusBarController：26 条回放断言通过，覆盖检测/认证串行、手动失败后的退避、旧回调、注销后暂停和显式恢复；同一入口继续执行窗口生命周期 smoke，通过。
- 已通过 Homebrew 安装 Qt 6.11.1（qtbase 及依赖）。使用 AppleClang 17 + MacOSX26.2.sdk，Windows 目录的完整应用编译、Qt 元对象信号连接、配置测试和主窗口回放通过。
- CTest 共 5 项全部通过：`session_policy_tests`、`windows_smoke_tests`、`controller_session_tests`、`credential_failure_tests`、`instance_guard_tests`；正式 MainWindow 的 Qt 信号、按钮和保存失败回放为 62 条断言，另有单实例锁竞争断言。
- Windows 配置测试及主窗口回放使用随机临时 INI，禁用系统自启动集成、正式日志和桌面通知。覆盖密码回读、取消记住密码、冷启动残留清理，以及点击登录时采用当前复选框；单实例锁测试确认第二个实例无法取得同一用户锁。
- `Q_OS_WIN` 分支在这台 macOS 主机不执行，因此上述结果不能证明 DPAPI 或注册表自启动通过。
- 凭据故障回放另有 20 条断言：编码失败、解码不符、真实 QSettings 自定义写入后端拒绝写盘、旧文件逐字节保留、运行配置恢复、同一实例故障恢复后重试、不可读旧凭据的保留与显式清除。测试存储后端使用临时目录。
- Qt 窗口保存失败会显示错误、保留输入、阻止提交登录；系统自启动变更延迟到配置保存成功之后。真实 Windows 注册表多键写入的失败恢复尚待原生验证。
- Swift、Qt 和 Lua 日志测试覆盖 JSON、CSV、表单、HTML、非结构化正文中的账号、密码和编码字段；正文只输出长度摘要。Lua 5.1/5.3 还检查传给系统 logger 的参数没有测试凭据。

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

Qt 原始结果保存在忽略目录 `macOS/tests/build/qt-validation/Testing/Temporary/LastTest.log`；Swift 最新应用构建日志为 `macOS/tests/build/session-build.log`。新的 App 位于 `macOS/build/session-validation/`，没有启动正式应用，没有重新制作该工作树的 DMG。

当前集成验证 App 可执行文件 SHA-256：`66b6721b565425e2daed14b97e28a3bbb0535eba9ebffb433487f404614794f6`；DMG SHA-256：`bbf8f2c51778504558521ee46358f33afe8cadbb8d6c683f1971becb8c29fccf`。产物位于忽略目录 `macOS/build/session-validation/`，包含超大数值解析修复；已通过严格签名和 `hdiutil verify`，不是 GitHub Release 资产。

## Lua 与 OpenWrt

Lua 源码来自 [官方下载区](https://www.lua.org/ftp/)，下载后核对官方 SHA-256：

| 版本 | 源码 SHA-256 |
|---|---|
| 5.1.5 | `2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333` |
| 5.3.6 | `fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60` |

构建于忽略目录 `macOS/tests/build/lua-runtimes/`，没有替换系统 Lua。两种解释器分别执行：

1. `tests/test_openwrt_modules.lua`：通过。
2. `tests/test_openwrt_runtime.lua`：通过，实际执行 API 和一轮 main 循环，curl/UCI/文件边界模拟；覆盖 PR #3 崩溃、小数流量/时长、JSON 空格、URL 编码、登录/注销、异常与网络失败。
3. `tests/test_openwrt_installation.py`：每种解释器 13 项通过，共 26 项。实际执行正式 Shell 脚本和真实 Lua，只对安装根目录、下载和服务边界注入临时环境。

故障注入覆盖：新装、重装保留配置、下载失败、半截 init 文件清理、非法 Lua、启用失败时恢复旧版本或移除新装、切换失败回滚、升级健康失败恢复、保持停止状态、下载失败不停止旧服务、备份清理失败不删除新安装。

校验 Lua 文件使用环境变量传递文件名，调用 `loadfile` 而不执行返回函数；不再把目标文件作为解释器脚本参数。该区别遵循 [Lua 解释器执行规则](https://www.lua.org/manual/5.1/manual.html#6)，故障注入中的 Lua 文件包含禁止执行的标记，误执行会使测试失败。

```bash
HAUT_TEST_LUA=lua5.1 python3 tests/test_openwrt_installation.py
HAUT_TEST_LUA=lua5.3 python3 tests/test_openwrt_installation.py
lua5.1 tests/test_openwrt_runtime.lua
lua5.3 tests/test_openwrt_runtime.lua
```

本地运行时将 lua5.1/lua5.3 替换为上述忽略目录中的绝对路径。路由器 procd、真实 UCI、存储耗尽/断电和校园网接口没有被这些测试替代。

## 契约与仍未验证内容

Python 协议、文档、版本契约检查已通过；Shell 语法与 git diff --check 已检查。CI 工作流现已加入 PR/main 触发及 Lua 5.1/5.3 模块、运行和安装故障回归。

## 集成分支与原生 CI

- 草稿集成：[PR #4](https://github.com/yellowpeachxgp/HAUTNetworkGuard/pull/4)。
- 首轮提交：`7276a6c1dbc6e1f18fe5492e85e2eac0c91e2443`；推送后本地 HEAD、跟踪分支及 ls-remote 三方一致。
- [首轮运行 34224354585](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34224354585)：macOS 构建、原生测试、DMG 打包和签名通过；Linux OpenWrt 双版本测试通过；Windows 在 CMake 配置阶段失败，未执行编译和测试。

- [第五轮运行 34229762182](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34229762182) 对应协议安全范围提交 `66684f3837e67fe241225106af2517816c5ca3a6`：三平台构建、协议契约、OpenWrt 双版本回归和 Windows/macOS 测试全部通过。
- [第三轮运行 34225154211](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34225154211) 对应超大数值修复：Windows 和 OpenWrt 全部通过；macOS 编译、测试和签名通过，但固定 `tmp.dmg` 路径在创建阶段触发 `Resource busy`。已改为唯一临时目录并在本机验证。

- [第四轮运行 34226445948](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34226445948) 对应提交 `413d4efad1f6789d5e7b0f37a26f91373d306f1a`：macOS、Windows、OpenWrt 三项 job 全部通过。Windows Server 2022 / Qt 6.6 原生构建、4 项 CTest、DPAPI 回读、运行库部署和 ZIP 上传通过；macOS 编译、协议溢出回归、Keychain、UI smoke、DMG 创建、签名和上传通过；Release job 因草稿 PR 按预期跳过。

- 第五轮运行 34229762182 对应协议安全范围提交 `66684f3837e67fe241225106af2517816c5ca3a6`：三平台构建、协议契约、OpenWrt 双版本回归和 Windows/macOS 测试全部通过。
- Windows 失败原因：实际 `windows-latest` 镜像为 `windows-2025-vs2026`，现有生成器指定 VS 2022，找不到对应实例。已将作业固定到 `windows-2022`，其 [官方软件清单](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md#visual-studio-enterprise-2022) 包含 VS 2022；该问题已由第四轮 CI 验证通过。
- 原社区 PR #2/#3 未远程合并或关闭；本集成尚未合并到 main，没有执行 Release。

从第四轮 CI 下载并回读的集成预览资产保存在忽略目录 `macOS/tests/build/ci-34226445948/`：Windows ZIP SHA-256 为 `17c96a7a82040f3d3fdd82131fc2a44c7db50abdfc97c2245b4f82b6b2d30938`，macOS DMG SHA-256 为 `33e4a674cc43db3b1ae67d71428fc41d309416ee977d1a1bb3c183c13e9c4b01`。ZIP 回读确认包含 `HAUTNetworkGuard.exe`、Qt Core/Gui/Network/Widgets DLL 和 `platforms/qwindows.dll`；没有在本机启动 Windows 资产。

[第二轮运行 34224732221](https://github.com/yellowpeachxgp/HAUTNetworkGuard/actions/runs/34224732221) 对应 `f4ed6dc3070e5ccdfba5fb42dd6fe72be74a0fee`：Windows、macOS、OpenWrt 全部通过，Release 按预期跳过。Windows Server 2022 上完成 Qt 6.6 原生编译、4 项 CTest、运行库部署和 ZIP 打包；其中 smoke test 真实执行 DPAPI 加密、解码和独立配置回读。该结果仍不能替代真实用户桌面、自启动、跨账号升级和校园网验收。

等待 CI 时另发现并复现 macOS 协议解析缺陷：`sum_bytes=1e100` 在 `Double -> Int64` 转换时使进程以信号退出（本地复现退出码 -5）。已增加有限数及严格上界检查，超范围返回零，并添加正/负溢出、合法 Int64 最大值和超范围数字字符串回归；本地 macOS smoke 通过。该增量将由下一轮 CI 验证。

跨签名/跨账号升级、完整日志隐私审计、单实例/睡眠唤醒、OpenWrt 状态策略及下载清单验证、真实校园网、学生完整旅程与 7 天稳定性仍未完成。不得依据当前测试宣布产品完成。
