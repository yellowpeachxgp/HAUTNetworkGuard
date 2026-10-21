#!/usr/bin/env python3

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "Windows" / "src" / "main.cpp").read_text(encoding="utf-8")
    assert 'const bool startupRequested = args.contains("--startup", Qt::CaseInsensitive);' in source
    assert "const bool hasConfigured = Config::instance().hasConfigured();" in source
    assert "const bool startInBackground = startupRequested && hasConfigured;" in source
    assert 'if (startupRequested && !hasConfigured)' in source
    assert "显示配置窗口" in source
    # 后台启动必须先建托盘、延迟完整 UI；修复自启放到事件循环之后。
    assert "MainWindow mainWindow(startInBackground);" in source
    assert "repairAutoLaunchIfNeeded" in source
    assert "启动阶段" in source
    assert "QElapsedTimer" in source

    header = (ROOT / "Windows" / "src" / "mainwindow.h").read_text(encoding="utf-8")
    assert "explicit MainWindow(bool deferUi" in header
    assert "void ensureUiBuilt();" in header
    assert "void refitWindowSize();" in header

    window = (ROOT / "Windows" / "src" / "mainwindow.cpp").read_text(encoding="utf-8")
    assert "QScrollArea#contentScrollArea" in window
    assert "setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded)" in window
    assert "QLayout::SetMinimumSize" in window
    assert "setMinimumHeight(contentHeight)" in window
    assert "ensureUiBuilt" in window

    config = (ROOT / "Windows" / "src" / "config.cpp").read_text(encoding="utf-8")
    assert "ONLOGON" in config
    assert "scheduledTaskCreateArgs" in config
    assert "计划任务" in config
    assert "repairAutoLaunchIfNeeded" in config
    print("startup contract ok")


if __name__ == "__main__":
    main()
