#!/usr/bin/env python3
"""验证三端真实设备验收矩阵的结构，避免现场记录缺列或状态值漂移。"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "docs" / "REAL_DEVICE_ACCEPTANCE_MATRIX.md"
VALID_STATUSES = {"", "通过", "失败", "阻塞（说明原因）"}


def main():
    content = MATRIX.read_text(encoding="utf-8")
    assert "## 记录头" in content, "验收矩阵缺少记录头"
    assert "commit：" in content and "VERSION：" in content, "验收矩阵缺少提交/版本字段"
    assert "## 7 天稳定性记录" in content, "验收矩阵缺少七天稳定性记录"
    assert "## 完成门禁" in content, "验收矩阵缺少完成门禁"

    rows = {}
    for line in content.splitlines():
        match = re.match(r"^\|\s*(A(?:[1-9]|1[0-3]))\s*\|", line)
        if not match:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        assert len(cells) == 6, f"{match.group(1)} 列数错误: {cells}"
        scenario_id = match.group(1)
        assert scenario_id not in rows, f"验收场景重复: {scenario_id}"
        for platform, value in zip(("Windows", "macOS", "OpenWrt"), cells[2:5]):
            assert value in VALID_STATUSES, f"{scenario_id} 的 {platform} 状态非法: {value!r}"
        assert cells[5], f"{scenario_id} 缺少必须记录的证据说明"
        rows[scenario_id] = cells

    expected = {f"A{i}" for i in range(1, 14)}
    assert set(rows) == expected, f"验收场景必须完整包含 A1-A13，实际为: {sorted(rows)}"
    print("acceptance matrix contract ok: A1-A13")


if __name__ == "__main__":
    main()
