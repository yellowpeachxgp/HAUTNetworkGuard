# HAUT Network Guard - AI 技术文档

> **重要**: 此文件包含完整的技术实现细节，供 AI 助手在后续开发中快速理解项目。请勿将此文件公开或上传到公开仓库。

## 项目概述

HAUT Network Guard 是一个为河南工业大学 (HAUT) 校园网设计的 macOS 原生菜单栏应用，用于自动登录和保持网络连接。

### 核心需求
- Mac mini 24/7 运行，需要持续稳定的网络连接
- 校园网会定期断开，需要自动重连
- 不依赖浏览器，原生 macOS 应用

---

## 技术架构

### 1. 协议分析

校园网使用 **SRUN3K** 认证协议，服务器信息：
- **认证服务器 IP**: `172.16.154.130`
- **登录端口**: `69`
- **状态检查端口**: `80`

#### API 端点
```
状态检查: http://172.16.154.130/cgi-bin/rad_user_info
登录/注销: http://172.16.154.130:69/cgi-bin/srun_portal
```

#### 状态检查响应格式
- **在线**: `username,seconds,ip,bytes,...` (逗号分隔的多个字段)
- **离线**: 空响应或包含 `not_online`

#### 登录请求参数
```
action=login
username=<加密后的用户名>
password=<加密后的密码>
ac_id=1
drop=0
pop=1
type=10
n=117
mbytes=0
minutes=0
mac=02:00:00:00:00:00
```

#### 登录响应
- 成功: 包含 `login_ok`
- 已在线: 包含 `already_online`
- 失败: 其他错误信息

---

### 2. 加密算法 (核心机密)

#### 用户名加密
```swift
// 算法: 每个字符的 ASCII 码 +4，然后添加前缀 "{SRUN3}\r\n"
static func encryptUsername(_ username: String) -> String {
    var encrypted = ""
    for char in username {
        if let scalar = char.unicodeScalars.first {
            let newValue = scalar.value + 4
            if let newScalar = UnicodeScalar(newValue) {
                encrypted += String(newScalar)
            }
        }
    }
    return "{SRUN3}\r\n" + encrypted
}

// 示例:
// 输入: "231040600203"
// 步骤: 每个字符 ASCII +4
//   '2' (50) -> '6' (54)
//   '3' (51) -> '7' (55)
//   ...
// 输出: "{SRUN3}\r\n675484:44647"
```

#### 密码加密
```swift
// 算法: XOR 加密 + 位拆分重组
// 密钥: "1234567890" (从末尾开始循环使用)

static func encryptPassword(_ password: String) -> String {
    let key = "1234567890"
    let keyChars = Array(key)
    var encrypted = ""

    for (i, char) in password.enumerated() {
        guard let charValue = char.asciiValue else { continue }

        // 密钥索引: 从末尾开始，循环
        let keyIndex = key.count - 1 - (i % key.count)
        guard let keyCharValue = keyChars[keyIndex].asciiValue else { continue }

        // XOR 运算
        let ki = Int(charValue) ^ Int(keyCharValue)

        // 位拆分: 低4位 + 0x36, 高4位 + 0x63
        let lowBits = (ki & 0x0f) + 0x36
        let highBits = ((ki >> 4) & 0x0f) + 0x63

        let lowChar = Character(UnicodeScalar(lowBits)!)
        let highChar = Character(UnicodeScalar(highBits)!)

        // 交替组合: 偶数索引 low+high, 奇数索引 high+low
        if i % 2 == 0 {
            encrypted += String(lowChar) + String(highChar)
        } else {
            encrypted += String(highChar) + String(lowChar)
        }
    }

    return encrypted
}

// 示例:
// 输入: "fang20051012"
// 密钥: "1234567890" (循环使用，从 '0' 开始)
// 步骤:
//   'f' (102) XOR '0' (48) = 86 -> low=6+0x36=60(':'), high=5+0x63=104('h') -> ":h"
//   'a' (97) XOR '9' (57) = 88 -> low=8+0x36=62('>'), high=5+0x63=104('h') -> "h>"
//   ...
```

#### URL 编码注意事项
加密后的用户名包含特殊字符 `{SRUN3}\r\n`，必须使用严格的 URL 编码：
```swift
var urlEncoded: String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
}
```

---

### 3. 应用架构

```
┌─────────────────────────────────────────────────────┐
│                    AppDelegate                       │
│  - 应用生命周期管理                                    │
│  - 首次运行检测                                       │
└─────────────────────┬───────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
┌───────────────────┐    ┌────────────────────┐
│ SettingsWindow    │    │ StatusBarController │
│ - 用户名/密码输入   │    │ - 菜单栏图标管理     │
│ - 首次配置引导     │    │ - 状态监控 (3秒间隔) │
└───────────────────┘    │ - 自动登录逻辑       │
                         │ - 系统通知           │
                         └─────────┬───────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │      SrunAPI        │
                         │ - 状态检查          │
                         │ - 登录/注销请求     │
                         │ - 响应解析          │
                         └─────────┬───────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │   SrunEncryption    │
                         │ - 用户名加密        │
                         │ - 密码加密          │
                         └─────────────────────┘
```

### 4. 文件结构说明

| 文件 | 功能 |
|------|------|
| `main.swift` | 应用入口，创建 NSApplication |
| `AppDelegate.swift` | 应用代理，管理生命周期和首次运行 |
| `Config.swift` | 配置管理，UserDefaults 存储凭据 |
| `Encryption.swift` | SRUN3K 加密算法实现 |
| `SrunAPI.swift` | 网络请求封装，状态检查和登录 |
| `StatusBarController.swift` | 菜单栏 UI 和监控逻辑 |
| `SettingsWindow.swift` | 设置窗口 UI |
| `AboutWindow.swift` | 关于窗口 UI |

---

## 开发历程与问题解决

### 问题 1: 登录后无法重新登录
**症状**: 注销后再登录失败
**原因**: URL 编码不完整，`{SRUN3}\r\n` 中的特殊字符未正确编码
**解决**: 使用更严格的 CharacterSet，只允许 `alphanumerics` + `-._~`

### 问题 2: 自动重连只触发一次
**症状**: 断线后只尝试登录一次，失败后不再重试
**原因**: 逻辑只在状态从"在线"变为"离线"时触发
**解决**: 改为每次检测到离线状态都尝试登录

### 问题 3: 首次运行无配置
**需求**: 分发给其他同学使用，需要配置界面
**解决**: 添加 SettingsWindow，首次运行时弹出配置窗口

---

## 关键实现细节

### 状态监控循环
```swift
// 每 3 秒检测一次网络状态
checkTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    self.checkStatus()
}

// 检测到离线时自动登录
func handleStatusChange(_ newStatus: NetworkStatus) {
    if !newStatus.isOnline {
        performAutoLogin()  // 每次离线都尝试登录
    }
}
```

### 凭据存储
```swift
// 使用 UserDefaults 存储 (注意: 不够安全，后续可改用 Keychain)
private let usernameKey = "haut_username"
private let passwordKey = "haut_password"
```

### 菜单栏图标
```swift
// 使用 SF Symbols
let onlineIcon = "wifi"           // 在线
let offlineIcon = "wifi.slash"    // 离线
let checkingIcon = "arrow.triangle.2.circlepath"  // 检测中
```

---

## 后续开发计划

### 优先级高
1. **Keychain 存储**: 将密码存储改为 Keychain，提高安全性
2. **多账号支持**: 支持切换多个账号
3. **日志查看**: 在应用内查看登录日志

### 优先级中
4. **流量统计**: 显示历史流量使用情况
5. **自定义检测间隔**: 允许用户设置检测频率
6. **网络变化监听**: 使用 Network.framework 监听网络变化，而非轮询

### 优先级低
7. **iOS 版本**: 开发 iOS/iPadOS 版本
8. **多平台**: 考虑 Windows/Linux 版本

---

## 构建与发布

### 构建命令
```bash
./build.sh
```

### DMG 打包
```bash
./create-dmg.sh
```

### 发布流程
1. 更新 `Config.swift` 中的版本号
2. 运行 `./build.sh` 构建
3. 运行 `./create-dmg.sh` 打包
4. 在 GitHub 创建 Release，上传 DMG

---

## 原始参考

项目基于以下资源逆向分析：
- JavaScript 油猴脚本 (Violentmonkey userscript)
- ehaut/ehaut GitHub 仓库的 HTML 客户端

加密算法从 JavaScript 移植到 Swift，核心逻辑保持一致。

---

## AI 助手使用指南

如果你是一个新的 AI 对话，请注意：

1. **不要修改加密算法**: `Encryption.swift` 中的算法经过验证，请勿修改
2. **URL 编码很关键**: 特殊字符必须正确编码
3. **测试登录功能**: 任何 API 相关的修改都需要实际测试
4. **保密技术细节**: README.md 中不要包含加密算法细节

### 快速开始开发
```bash
cd /Volumes/SN\ 770/Developer/ehaut/HAUTNetworkGuard
./build.sh  # 编译
open build/HAUTNetworkGuard.app  # 运行测试
```

### 常见开发任务
- **添加新功能**: 主要修改 `StatusBarController.swift`
- **修改 UI**: 修改对应的 Window 文件
- **调整 API**: 修改 `SrunAPI.swift`
- **配置项**: 修改 `Config.swift`

---

*此文档由 Claude (Opus 4.5) 生成，用于项目知识传递。*
