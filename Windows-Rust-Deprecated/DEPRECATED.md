# ⚠️ 已弃用 - Windows Rust 版本

> **重要通知**: 此目录包含旧版 Rust + egui 实现，已被 Qt 版本取代。
>
> **请使用新的 Qt 版本**: 位于 `Windows/` 目录

---

## 弃用原因

1. **系统托盘复杂**: Rust 的 tray-icon 库需要复杂的跨线程通信
2. **原生集成困难**: Windows API 集成需要大量 FFI 代码
3. **构建依赖**: 需要 mingw-w64 交叉编译工具链

## 新版本优势 (Qt)

- 原生 `QSystemTrayIcon` 系统托盘
- `QSettings` 标准化配置管理
- GitHub Actions 自动构建，无需本地 Windows 环境
- 更好的中文字体支持

---

## 如果需要恢复此版本

```bash
# 仅供参考，不推荐使用
cd Windows-Rust-Deprecated
cargo build --release --target x86_64-pc-windows-gnu
```

---

*此目录保留仅供历史参考。新开发请使用 Qt 版本。*
