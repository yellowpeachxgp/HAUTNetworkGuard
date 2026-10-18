# v1.3.21 验证记录（2026-10-19）

基线：`goal/student-ready-integration` + 本轮改动，目标版本 `1.3.21`。
本记录只列出实际执行过的命令和结果；没有把真实 Windows 桌面、OpenWrt 真机、
校园网现场或 7 天连续运行写成“通过”。

## 1. 环境

| 项目 | 值 |
|---|---|
| 主机 | macOS ARM64 (Darwin 27.2) |
| Xcode / Swift | Xcode 26.3，xcrun Swift |
| Qt | Homebrew Qt 6.11.1 |
| Python | 3.14.8 |
| Lua | 5.1.5、5.3.6（本地构建） |
| 构建目录 | `/tmp/haut-qt-v1321`（不写入仓库） |

## 2. 自动化测试

### Python 契约

```bash
for f in tests/test_acceptance_matrix.py tests/test_docs_contract.py \
         tests/test_logging_contract.py tests/test_macos_uninstall.py \
         tests/test_protocol_contract.py tests/test_release_contract.py \
         tests/test_session_policy.py tests/test_startup_contract.py \
         tests/test_version_contract.py; do python3 "$f"; done
```

结果：全部通过。其中会话策略测试同时编译并运行 C++ 和 Swift 实现，
9 个场景、各 142 条事件断言；验收矩阵结构契约为 A1-A13（四端）。

### Lua 5.1 / 5.3

```bash
lua5.1 tests/test_openwrt_modules.lua
lua5.3 tests/test_openwrt_modules.lua
lua5.1 tests/test_openwrt_config.lua
lua5.3 tests/test_openwrt_config.lua
lua5.1 tests/test_openwrt_runtime.lua
lua5.3 tests/test_openwrt_runtime.lua
lua5.1 tests/test_openwrt_session.lua
lua5.3 tests/test_openwrt_session.lua
lua5.1 tests/test_openwrt_log.lua
lua5.3 tests/test_openwrt_log.lua
```

结果：全部通过。`test_openwrt_config.lua` 覆盖：

- BOM、CRLF、整行/行内注释、单双引号、重复键、非法键、空值；
- 文件后端与 UCI 后端优先级、UCI 空值回退文件；
- 1000 条随机字节行不抛错、不返回非字符串值；
- 200000 字节超长值不截断。

`test_openwrt_log.lua` 额外验证文件/UCI 两种后端的 debug 级别和
`io.stdout:flush()` 调用。

### OpenWrt 安装/升级/卸载故障注入

```bash
HAUT_TEST_LUA=lua5.1 python3 tests/test_openwrt_installation.py
HAUT_TEST_LUA=lua5.3 python3 tests/test_openwrt_installation.py
```

结果：各 25 项通过，共 50 项。新增 `config.lua` 后，安装、升级、回滚和
清单覆盖仍全部通过；旧安装缺少 `config.lua` 时升级失败会移除新文件。

### 通用 Linux 安装/重装/卸载故障注入

```bash
HAUT_TEST_LUA=lua5.1 python3 tests/test_linux_generic_installation.py
HAUT_TEST_LUA=lua5.3 python3 tests/test_linux_generic_installation.py
```

结果：各 15 项通过，共 30 项。覆盖：

- 全新安装、已有安装重装保留配置；
- `systemctl` 停止/启用/启动/daemon-reload 失败回滚；
- 卸载默认保留配置、`--purge-config` 清除；
- Release 包 SHA-256 校验、tag/版本不一致拒绝；
- main 源码包安装、非法 ref 拒绝；
- 临时文件、备份目录和配置权限 600。

### Windows Qt

```bash
cmake -B /tmp/haut-qt-v1321 -S Windows -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/haut-qt-v1321 --parallel
ctest --test-dir /tmp/haut-qt-v1321 --output-on-failure
```

结果：6/6 通过：`session_policy_tests`、`windows_smoke_tests`、
`controller_session_tests`、`credential_failure_tests`、
`instance_guard_tests`、`layout_tests`。

新增 `layout_tests` 把应用字体放大到至少 15pt，检查：

- 窗口宽度保持 460、高度不低于 640；
- 所有非空 QLabel 高度不小于 `fontMetrics().height()`；
- 自动换行标签高度不小于 `heightForWidth`；
- 切换复选框重新布局后仍不裁切；
- 内容超过视口时存在滚动条。

### macOS

```bash
cd macOS
./tests/run_smoke_tests.sh
./tests/run_ui_smoke_tests.sh
./build.sh
./create-dmg.sh
hdiutil verify build/HAUTNetworkGuard.dmg
```

结果：

- 协议、隔离配置、凭据故障注入和原生 Keychain 测试通过；
- 正式控制器会话回放 32 个断言通过；
- UI smoke 通过；
- 完整 AppKit 构建通过，无 Swift 编译警告；
- DMG 校验、只读挂载、包内可执行文件、`AppIcon.icns` 和
  `codesign --verify --deep --strict` 通过。

### Shell 语法

```bash
for f in OpenWrt/*.sh OpenWrt/files/etc/init.d/haut-network-guard linux-generic/*.sh; do
  sh -n "$f"
done
```

结果：全部通过。

## 3. 稳定性重复

| 项目 | 次数 | 结果 |
|---|---:|---|
| Qt CTest（6 项） | 20 轮 | 全部通过（120 次测试） |
| Lua runtime（5.1/5.3） | 各 50 轮 | 全部通过 |
| Lua config（5.1/5.3） | 各 10 轮 | 全部通过 |
| Linux 安装（15 项 × 2 Lua） | 3 轮 | 全部通过（90 次测试） |
| OpenWrt 安装（25 项 × 2 Lua） | 2 轮 | 全部通过（100 次测试） |
| 会话策略（C++/Swift） | 3 轮 | 全部通过 |
| macOS UI smoke | 2 轮 | 全部通过 |

说明：以上是加速回放和重复执行，不等同于真实 7 天连续运行。7 天现场记录仍需
按 [REAL_DEVICE_ACCEPTANCE_MATRIX.md](REAL_DEVICE_ACCEPTANCE_MATRIX.md) 执行。

## 4. 发布资产 dry-run

本地按 CI 的 Linux 打包结构创建并校验：

```bash
rm -rf .release-linux
mkdir -p .release-linux/HAUTNetworkGuard-Linux/OpenWrt
cp VERSION README.md .release-linux/HAUTNetworkGuard-Linux/
cp -R OpenWrt/files .release-linux/HAUTNetworkGuard-Linux/OpenWrt/files
cp -R linux-generic .release-linux/HAUTNetworkGuard-Linux/
tar -czf HAUTNetworkGuard-Linux.tar.gz -C .release-linux HAUTNetworkGuard-Linux
tar -tzf HAUTNetworkGuard-Linux.tar.gz > linux-tar-list.txt
grep -Fq ".../linux-generic/install.sh" linux-tar-list.txt
grep -Fq ".../OpenWrt/files/usr/lib/haut-network-guard/config.lua" linux-tar-list.txt
sha256sum HAUTNetworkGuard-Linux.tar.gz > SHA256SUMS
sha256sum -c SHA256SUMS
```

结果：包内包含 `VERSION`、`OpenWrt/files`、`linux-generic/` 和
`README.md`；SHA-256 回读通过。macOS DMG 已单独完成校验、挂载和签名复核。

### 正式 Release 回读（v1.3.21）

- GitHub Actions tag run `39166133262`：validate-openwrt、build-windows-qt、
  build-macos、release-dry-run、release 全部通过。
- Release：<https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases/tag/v1.3.21>，
  资产为 Windows ZIP、macOS DMG、Linux tar.gz、`SHA256SUMS`、`OpenWrt-SHA256SUMS`。
- 下载后执行 `sha256sum -c SHA256SUMS`：三个资产全部 OK。
- Windows ZIP 包含 `HAUTNetworkGuard.exe`、`platforms/qwindows.dll` 和
  `networkinformation/qnetworklistmanager.dll`。
- Linux tar.gz 包含 `VERSION`、`linux-generic/install.sh`、
  `OpenWrt/files/usr/lib/haut-network-guard/config.lua` 和 `main.lua`。
- `OpenWrt-SHA256SUMS` 包含 `config.lua`；DMG 校验、只读挂载、
  `AppIcon.icns` 和 `codesign --verify --deep --strict` 通过。
- 使用 Release 实际资产执行 `linux-generic/install-online.sh v1.3.21`：
  SHA-256 校验、安装、配置权限 600、systemd 服务生成和卸载保留配置通过。

## 5. 尚未替代的现场验证

- 真实 Windows 10/11 桌面上的通知区域显示、Explorer 重启、125%/150% 缩放；
- 真实 OpenWrt 路由器的 procd 启动、升级健康检查和断电恢复；
- 真实 Debian/Ubuntu 主机的 systemd 启动、journal 日志和重启；
- 真实校园网首次登录、错误凭据、断线恢复、注销和 7 天连续运行；
- macOS Developer ID 签名和公证（当前为 ad-hoc）。

这些项目保持“待验证”，不作为本轮自动化通过的替代。
