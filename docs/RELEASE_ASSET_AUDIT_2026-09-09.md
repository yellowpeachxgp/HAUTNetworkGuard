# v1.3.18 发布资产审计

审计日期：2026-09-09

审计对象：[GitHub Release v1.3.18](https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases/tag/v1.3.18)。本记录只描述远端现状，不修改已发布资产。

## 远端资产

| 资产 | 远端大小 | SHA-256 | 回读结果 |
|---|---:|---|---|
| `HAUTNetworkGuard-Windows.zip` | 13,485,601 bytes | `9e8d1925be8dc35e88e9e1181838dd54a82c6d820593a2b12549e5b07482e7` | 解压后包含 `HAUTNetworkGuard.exe`、Qt 运行库和 `platforms/qwindows.dll`；可执行文件字符串回读为 `1.3.18` |
| `HAUTNetworkGuard.dmg` | 280,048 bytes | `b9151d96e1a7c242f4b697cbc6048f3e09e902ed6159e398d5a0c302871ec5f9` | 只读挂载后 `Info.plist` 的短版本为 `1.3.18`，包内签名验证通过 |

## 缺口与影响

- Release 资产列表只有上述两个桌面文件，没有 `SHA256SUMS` 或 `OpenWrt-SHA256SUMS`。
- 因此 v1.3.18 的固定版本 OpenWrt 在线安装/升级无法完成清单校验，会按设计安全失败；这不是安装脚本故障，也不能把 `v1.3.18` 宣称为当前完整发布资产。
- 下一次正式 Release 必须由工作流生成并上传两个清单，同时回读 Release 页面、资产哈希和 OpenWrt 清单覆盖；在此之前不应要求学生使用固定版本在线安装命令。

## 审计命令

```bash
gh release view v1.3.18 --json tagName,assets
gh release download v1.3.18 --pattern 'HAUTNetworkGuard-Windows.zip' --pattern 'HAUTNetworkGuard.dmg'
sha256sum HAUTNetworkGuard-Windows.zip HAUTNetworkGuard.dmg
unzip -l HAUTNetworkGuard-Windows.zip
hdiutil attach -readonly -nobrowse HAUTNetworkGuard.dmg
plutil -p HAUTNetworkGuard.app/Contents/Info.plist
codesign --verify --verbose HAUTNetworkGuard.app
```

审计没有启动 Windows 程序，也没有执行校园网登录、注销或修改远端 Release。
