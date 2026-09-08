# HAUTNetworkGuard 工程推进台账

更新日期：2026-09-09。完整目标仍为 [产品完成路线图](PRODUCT_COMPLETION_ROADMAP.md)，当前没有完成全部 M0-M6，也未发布新版本。

状态只对应表中列出的验证范围；原生编译、模拟设备边界和真实校园网验收不能互相替代。

| 任务 | 状态 | 当前证据 | 下一步 |
|---|---|---|---|
| M0-01 工作树边界 | 已对齐并推送 | 集成分支基于 origin/main；备份快照 35d2b91；原 main 及既有改动保留；草稿 PR #4 已建立；最新代码提交的三平台 CI 已全绿 | 完成后续任务与正式合并门禁 |
| M0-02 当前基线 | 已更新 | 当前基线已纠正主机、SDK 和远端旧结论 | 随后续实现继续维护 |
| M0-03 版本治理 | 部分实现 | Windows CMake 已从根目录 `VERSION` 读取版本并通过 `HAUT_VERSION_STRING` 注入主程序、窗口和 User-Agent；OpenWrt 运行文件统一消费 `version.lua`，安装/升级已纳入该文件，在线安装完成提示也从下载版本源读取；macOS 构建脚本生成 Swift 版本源并替换 Info.plist；VERSION、契约测试、Tag 一致性检查已加入，README/OpenWrt README/AIREADME 当前版本位置现做精确匹配 | README、AIREADME 等历史版本字面量仍需后续统一生成或消费机制 |
| M0-04/M0-05 仓库与证据 | 进行中 | 构建产物被忽略；测试独立临时目录；新增验证报告和 PR 来源记录 | 发布证据、最终提交和完整审计 |
| M1-01 至 M1-03 协议 | 部分验证 | 三平台 CI 协议测试通过；PR #3 崩溃已复现并修复；macOS 超大数值转换崩溃已复现并修复；JSON/CSV 小数、负数、超安全范围、非法 IP、空身份、空状态响应和尾随字段边界已加入 Swift/Qt/Lua/Python 回归；多登录标记优先级已加入四端回归 | 更多 JSON 编码和真实网关响应的跨端一致性 |
| M1-04 请求保护 | 部分实现 | 桌面控制器以 SessionPolicy 串行状态/认证；Windows Api 与 macOS SrunAPI 入口增加认证请求闸门；状态请求超时后可恢复；PR #3 修复日志导致请求崩溃 | 完整取消、并发竞态及物理接口切换测试 |
| M1-05 接口切换 | 部分实现 | macOS `DirectHTTPClient` 路径回调抽出有线优先、Wi‑Fi 回退和其他接口兜底选择器，UI smoke 覆盖三种输入 | Windows 路由变化、macOS 睡眠唤醒和真实接口切换现场验证 |
| M2 状态机和自动登录 | 桌面与 OpenWrt 策略已接入并局部验证 | Swift/C++ 共用 9 场景、各 142 条断言通过，并加速模拟 7 天逐分钟 soak；macOS 正式控制器 27 条回放和窗口测试通过；Windows 目录 Qt 完整构建及正式主窗口回放通过；OpenWrt `session.lua` 19 条断言和真实守护循环回放通过；串行请求、回调编号、手动失败退避和注销暂停已接入；空状态响应统一进入异常路径，不触发自动登录 | OpenWrt 真机/异常重启行为、真实桌面重复启动、睡眠唤醒和真实 7 天运行仍需验收 |
| M3 学生体验 | 部分实现 | 有错误映射；macOS 菜单详情加入最近检测时间、当前状态和自动重试提示并提供脱敏诊断复制；Windows 主窗口显示状态、最近检测和重试提示并提供脱敏诊断复制；空首次配置会被拒绝并显示提示；设置窗口能报告 Keychain/DPAPI 保存失败；macOS 设置控件已设置无障碍名称、明确 Tab 顺序和首次焦点，Qt 主窗口同样具备无障碍名称和键盘焦点顺序；Qt 正式主窗口回放新增关闭隐藏到托盘、托盘重新显示断言；真实 macOS 窗口 smoke 与 Qt 主窗口回放通过 | 首次引导、诊断内容人工检查、所有错误覆盖、托盘/菜单人工检查及无障碍完整验收 |
| M4-01 macOS 凭据 | 本地已验证 | 独立 Keychain 服务和 UserDefaults 域；原生写入、冷启动读取、迁移、删除通过；故障注入覆盖写失败/回读不符/删除失败/解锁重试 | 安装包跨签名升级、锁定钥匙串及卸载流程的端到端验证 |
| M4-02 Windows 凭据 | Windows CI 与本地回放通过 | Windows Server 2022 / Qt 6.6 原生编译及 5 项 CTest 通过，含实际 DPAPI 保存/解码回读；20 条凭据故障、64 条控制器和单实例锁断言；自启动写入延迟至配置保存后 | 跨账号解密失败、Windows 注册表原生多键写入恢复、真实桌面升级与自启动验收 |
| M4-03 至 M4-05 隐私 | 部分验证 | UCI 权限边界、macOS 卸载脚本已支持停止失败中止并复核残留；OpenWrt 本地/在线卸载显式停止并禁用服务，默认保留配置、`--purge-config` 清除配置；三端响应正文统一长度摘要，Swift/Qt/Lua 测试覆盖账号、密码、编码字段和多种异常格式；新增 `test_logging_contract.py` 静态检查日志调用，Lua 双版本日志脱敏通过 | 其他日志字段全路径审计、Keychain 真实卸载和三端清理验收 |
| M5-01 Release 资产安装测试 | 部分实现 | CI 在 Windows Server 2022 解压 ZIP 并检查主程序及 Qt DLL；macOS CI 只读挂载 DMG、检查包内可执行文件并复核签名；OpenWrt 固定版本安装路径由 48 项双 Lua 故障矩阵覆盖 | 干净设备实际安装启动、正式 Release 资产和 OpenWrt 真机启动 |
| M5-02 原子在线安装 | 本地与在线事务边界已验证 | 离线和在线脚本均先在 staging 目录完成真实 Lua/服务脚本校验，再原子切换；临时根目录测试覆盖中断、启用/切换失败、配置保留、哈希篡改、tag/版本不一致、备份清理失败和缺失系统临时目录；每种 Lua 24 项安装/升级/卸载测试通过 | 路由器存储限制、并发安装和断电恢复 |
| M5-03 升级健康检查 | 模拟边界已验证 | 下载期间不停旧服务；保持用户停止状态；逐文件清单校验、文件回读与失败恢复；两种 Lua 各 24 个安装/升级/卸载测试通过 | procd 真机和至少一轮校园网状态请求；当前 status 成功不代表联网成功 |
| M5-04 资产完整性 | 部分实现 | CI 哈希清单已加入；Release job 新增桌面资产 `sha256sum -c` 和 OpenWrt 清单文件覆盖回读；固定版本在线安装/升级消费 `OpenWrt-SHA256SUMS`，并拒绝 tag 与 `version.lua` 不一致；两种 Lua 各 24 项安装/升级/卸载测试通过；本地 macOS DMG 哈希/只读挂载/包内签名核对通过；CI 预览 ZIP/DMG 已下载、回读并核对哈希及关键文件 | OpenWrt 下载端消费清单、正式 Release 产物和来源验证 |
| M5-05 macOS 打包 | 本地已验证 | 匹配 Xcode SDK/编译器后构建、ad-hoc 签名、DMG 和窗口测试通过 | Developer ID/公证及干净设备首次启动未验证，ad-hoc 不等于 Gatekeeper 放行 |
| M5-06 发布说明一致性 | 自动契约已加入 | `tests/test_release_contract.py` 已接入 CI，校验 tag/VERSION、Release 依赖、桌面资产、双哈希清单和 OpenWrt 固定版本安装命令 | 真实 Release tag、资产上传和发布页面回读 |
| M6 现场和稳定性 | 未完成 | 已新增 [三端真实设备验收矩阵](REAL_DEVICE_ACCEPTANCE_MATRIX.md)，但没有新的校园网请求或 7 天运行证据 | 按矩阵完成 Windows/macOS/OpenWrt 真机、学生完整旅程、稳定性与最终发布门禁 |
| 社区 PR | 已审查并进入集成提交 | [PR 审查记录](PR_REVIEW_2026-09-08.md)：#3 已采纳并复现验证，提交记录保留来源；#2 保留已生效修复 | GitHub 社区 PR 尚未合并/关闭，新版本尚未发布 |

## 本轮验证

- Python 协议、文档、版本契约：通过。
- Release 发布契约：通过，自动检查 workflow 的 tag/VERSION 闸门、Windows/macOS 资产、双哈希清单和 OpenWrt 安装命令。
- macOS 隔离配置、存储故障注入、原生 Keychain：通过。
- macOS 完整 AppKit 构建、窗口生命周期测试、严格签名检查、DMG 校验/只读挂载/包内哈希：通过。
- Lua 5.1.5 和 5.3.6：模块测试、真实 API/守护循环回放通过；每个解释器下安装/升级/卸载故障注入 24 项通过，共 48 项。
- Swift/C++ 会话策略加速模拟 7 天逐分钟运行（10,080 次检测）通过，现场 7 天稳定性仍未替代。
- PR #4 的运行 34253578251（三平台构建与测试全部通过）验证了当前版本治理、首次空配置拒绝、安装/卸载、接口选择和资产门禁；Windows 镜像/VS 生成器不匹配和 macOS DMG 临时路径竞态均已修复，Windows 实际 DPAPI 测试不再缺席。Release job 因草稿 PR 按预期跳过；离线安装事务、严格版本格式、协议边界、OpenWrt 清单、`version.lua` 运行时版本源、macOS 生成版本源、macOS 接口选择与卸载失败保护、脱敏诊断和认证闸门已纳入验证。
- 具体命令和边界见 [验证记录](VALIDATION_2026-09-08.md)。

## 当前环境阻塞与先前结论纠正

- 主机实际是 macOS ARM64，具备 Xcode、Command Line Tools 和 SDK。先前“Linux、没有 xcrun/SDK”的结论错误，不能继续作为未执行理由。
- 先前完整构建混用了 Xcode Swift 6.2.4 与 CLT Swift 6.4 SDK。现已统一通过 xcrun 的 macosx SDK 选择，并在同一个 DEVELOPER_DIR 下验证通过。
- Lua 5.1.5/5.3.6 已从 lua.org 下载、核对官方 SHA-256，并构建在忽略目录中；Lua 本地测试不再受阻。
- 已安装 Homebrew Qt 6.11.1，Windows 目录在 macOS ARM64 下完整编译、配置与 Qt 控制器回放通过；远端 Windows Server 2022 已执行原生构建和 DPAPI 测试。“没有 Qt / 无法执行 Windows 原生测试”不再能作为未执行理由。真实 Windows 桌面、自启动、OpenWrt 真机与校园网现场仍缺少证据。

## 测试隔离问题记录

之前的 smoke test 使用 AppConfig.shared 和正式 Keychain 服务名，会写入/删除正式条目；先前运行可能影响已保存密码，已告知用户。现已改为注入配置和存储后端，原生测试使用每次随机的 tests 服务名，UI smoke 也使用独立配置域，测试关闭正式文件日志。没有读取或回显用户密码；无法由当前证据追溯先前是否存在被覆盖的条目。

Windows 旧 smoke test 同样存在正式 QSettings 域清空和自启动修改风险；本轮运行前已改成临时 INI、注入 Config、关闭系统自启动集成。正式 MainWindow 回放注入相同的独立存储和模拟网络，禁用桌面通知；没有运行 Windows 生产配置单例。
