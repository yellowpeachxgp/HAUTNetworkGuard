# HAUTNetworkGuard 当前基线与执行计划

日期：2026-09-08。当前开发基于 v1.3.18，完整交付目标见 [产品路线图](PRODUCT_COMPLETION_ROADMAP.md)，执行状态见 [台账](IMPLEMENTATION_LEDGER.md)。

## 代码与仓库事实

- 调研起点及保留的本地 main：`e4f553e6e5bcddd33d644eaa60716d85188a897e`。
- 远端 main：`51edcd0515a1ffb398e6e1e7bdf3abbefa9aa922`，同为 v1.3.18。原本双方各差 3 个等价提交，快照只差 macOS/build.sh 的执行位。
- 已建立 `goal/student-ready-integration` 集成分支，将本次增量提交移到 origin/main 之后；当前集成提交为 `53a99b3`。原始 main 未改写，变基前完整工作树快照保留在 `backup/student-ready-before-rebase`（`35d2b91`），执行位恢复后与该快照逐文件比较一致。
- 开始调研时的 14 个未提交文件属于既有工作，已保留；后续代码、测试和文档继续在该工作树演进，不能把当时的文件数量当作当前状态。
- 已检查的社区 PR 为 #2 和 #3；#3 已进入集成提交，#2 核心修复早已生效，见 [PR 审查记录](PR_REVIEW_2026-09-08.md)。本次原生 CI 将通过集成分支的草稿 PR 验证。
- 没有发布新版本，没有执行真实校园网登录/注销，也没有运行安装/卸载脚本修改本机服务。

## 平台结构

- macOS：Swift/AppKit 菜单栏；DirectHTTPClient 物理接口直连；LaunchAgent；Keychain 存储，配置和存储后端可注入。
- Windows：Qt 6/C++17；QNetworkAccessManager；QSettings 设置和 DPAPI 密码；托盘与注册表自启。
- OpenWrt：Lua/procd、UCI、curl；协议/日志模块；安装和升级事务。
- 共享：VERSION、协议向量、文档与版本契约、CI、状态契约和产品台账。

## 当前可确认的验证

macOS 主机具备原生 SDK，匹配 Xcode 工具链后，隔离凭据/Keychain、完整应用构建、UI smoke、ad-hoc 签名、DMG 只读挂载及包内文件核对均通过。Lua 5.1/5.3 模块与请求/循环回放均通过；安装/升级使用真实 Lua、临时根目录和模拟 curl/procd 边界，每种解释器 15 项、共 30 项故障注入通过。

这些验证不等于 Windows 原生执行、OpenWrt 真机运行、Gatekeeper 公证、校园网连接或长期稳定性验收。具体证据与命令见 [验证记录](VALIDATION_2026-09-08.md)。

## 当前未收口事项

1. 桌面与 OpenWrt 状态策略已接入：共用 9 场景、各 142 条断言，macOS 正式控制器及 Qt 正式主窗口回放通过，OpenWrt `session.lua` 19 条断言和守护循环回放通过。三端空响应语义、真机重启与睡眠唤醒仍需收口。
2. Windows 目录已在 macOS / Qt 6.11.1 与 Windows Server 2022 / Qt 6.6 CI 原生编译并执行 CTest，包含实际 DPAPI 回读。真实 Windows 桌面、原生自启动和跨账号迁移，以及 macOS 分发升级和卸载仍需端到端检查。
3. 响应正文已统一改为长度摘要，并通过三端多格式隐私测试；其他日志字段及卸载输出的全路径审计尚未完成。
4. OpenWrt 在线事务已通过故障注入，但仍需并发/磁盘限制/真机验证；下载端尚未消费 Release 哈希清单。
5. VERSION 仍与多个源码字面量共存，需要完整生成或直接消费机制。
6. 完整学生旅程、跨端自启动、单实例、无障碍及 7 天稳定性尚未完成。

保留 2026-04-11 文档作为历史快照。当前进度按台账持续推进，不能通过缩小路线图范围宣布产品完成。
