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
    print("startup contract ok")


if __name__ == "__main__":
    main()
