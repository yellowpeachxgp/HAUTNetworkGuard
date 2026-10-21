# v1.3.22 验证记录（2026-10-21）

目标：修复 Windows 用户截图中的标签裁切/控件重叠，并改善开机自启过慢的问题。

## 1. Windows 布局

新增/扩展 `Windows/tests/layout_tests.cpp`，覆盖：

- 放大字体（至少 15pt）后所有 QLabel 高度不小于 `fontMetrics().height()`；
- 自动换行标签高度不小于 `heightForWidth`；
- 同一父级叶子控件不重叠；
- 顶层卡片（hero / 网络状态 / 账号设置）不重叠；
- 切换“自动登录”最长提示文案后仍不重叠；
- 字体再放大 6pt 后仍不重叠；
- 窗口压到 560px 时出现纵向滚动条且不重叠；
- 延迟 UI 构建：`deferUi=true` 时不创建窗口内容，`show()` 后按需构建。

本地结果：

```text
Windows 布局回归通过：128 个断言，窗口 460x740，内容高 1073，视口高 740，延迟构建 10ms
Windows 布局回归通过：128 个断言，窗口 460x560，内容高 1073，视口高 560，延迟构建 10ms
```

说明：窗口 740/560 高、内容 1073 高时，滚动区域接管溢出；标签不再被压缩。

## 2. Windows Qt 测试

```bash
cmake -B /tmp/haut-qt-v1322 -S Windows -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/haut-qt-v1322 --parallel
ctest --test-dir /tmp/haut-qt-v1322 --output-on-failure
```

结果：**7/7 通过**：

- session_policy_tests
- windows_smoke_tests
- controller_session_tests
- credential_failure_tests
- instance_guard_tests
- layout_tests
- autolaunch_tests

稳定性：`ctest --repeat until-fail:15` 全部通过（105 次测试）。

## 3. Windows 开机自启

新增 `Windows/tests/autolaunch_tests.cpp`（18 条断言）：

- 计划任务参数包含 `/Create`、`/TN HAUTNetworkGuard`、`/SC ONLOGON`、`/RL LIMITED`、`/TR` 和 `--startup`；
- 查询/删除参数正确；
- 计划任务不存在时：查询 → 创建 → 回读；
- 创建失败时回退，不误报任务存在；
- 计划任务已存在时不重复创建。

本地测试输出：

```text
Windows 自启策略回归通过：18 个断言
```

说明：真实 Windows 上 `schtasks` 是否允许当前用户创建 ONLOGON 任务取决于系统策略；
失败会自动回退注册表 Run / Startup 脚本，不影响功能。

## 4. 启动路径

代码层验证：

- `--startup` 构造 `MainWindow(true)`，不构建完整 UI；`showWindow()` 时才构建。
- 托盘图标在构造函数最前面创建并显示。
- `QNetworkInformation::loadDefaultBackend()` 延迟 1.5s。
- `Config::repairAutoLaunchIfNeeded()` 延迟 2s。
- Logger 保持文件打开，避免每条日志重复开关文件。
- 启动日志新增 qapp/config/window/事件循环阶段耗时。

本地延迟构建回放：`deferredElapsed = 10ms`（不含 Qt 平台初始化）。

## 5. 其他平台回归

- Lua 5.1.5 / 5.3.6：模块、配置、运行时、会话、日志全部通过。
- OpenWrt 安装/升级/卸载故障注入：25 项 ×2 Lua 通过。
- 通用 Linux 安装/重装/卸载故障注入：15 项 ×2 Lua 通过。
- macOS：协议、Keychain、控制器 32 条断言、UI smoke 通过；v1.3.22 DMG 构建与 `hdiutil verify` 通过。
- Python 协议、文档、版本、发布、日志、启动、会话、四端验收矩阵契约全部通过。
- 本地 Release dry-run：Linux tar.gz 包含 `VERSION`、`config.lua`、`install.sh`，SHA-256 回读通过。

## 6. 仍需现场验证

- 真实 Windows 10/11 + 微软雅黑 + 125%/150% 缩放下的截图复测；
- 真实 Windows 登录耗时（对比计划任务与注册表 Run）；
- 真实 Windows 通知区域/Explorer 重启；
- OpenWrt 真机、通用 Linux systemd 真机、校园网现场和 7 天连续运行。
