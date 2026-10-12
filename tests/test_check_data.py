"""数据完整性检查的回归测试（TASK-010）。

重点：历史记录总数是**下限**而不是等号——线上每天都在抓新数据，
把 1,850,921 当精确值会让 CI 每次抓取后必挂、提交步骤永不执行（v1.0.0 真实故障）。
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import check_data  # noqa: E402

from baidutop import format as fmt  # noqa: E402


def write_day(root: Path, date: str, titles: int = 2, rows_each: int = 1) -> Path:
    """在临时仓库里写一个合法 MD 文件，返回路径。"""
    compact = date.replace("-", "")
    path = root / compact[:4] / f"{compact} 百度实时热点.md"
    records = []
    for i in range(titles):
        for j in range(rows_each):
            records.append(fmt.Record(f"标题{i}", f"{j:02d}:00:00", str(i * 10 + j)))
    fmt.atomic_write_text(path, fmt.render(records, date=date))
    return path


def test_growth_above_baseline_is_ok(tmp_path):
    """收紧前会误报：抓了新数据后总数 > 基线必须仍然通过。"""
    write_day(tmp_path, "2026-10-12", titles=3, rows_each=2)
    result = check_data.check(tmp_path, min_records=5)
    assert result["errors"] == []
    assert result["total_records"] == 6


def test_exact_match_passes_when_requested(tmp_path):
    write_day(tmp_path, "2026-10-12", titles=2, rows_each=1)
    result = check_data.check(tmp_path, expect_records=2, min_records=2)
    assert result["errors"] == []


def test_exact_mismatch_fails_when_requested(tmp_path):
    """迁移验收仍可要求精确总数。"""
    write_day(tmp_path, "2026-10-12", titles=2, rows_each=1)
    result = check_data.check(tmp_path, expect_records=999, min_records=1)
    assert any("精确校验" in e for e in result["errors"])


def test_record_loss_below_baseline_fails(tmp_path):
    write_day(tmp_path, "2026-10-12", titles=1, rows_each=1)
    result = check_data.check(tmp_path, min_records=2)
    assert any("低于历史基线" in e for e in result["errors"])


def test_unparsed_line_fails(tmp_path):
    path = write_day(tmp_path, "2026-10-12")
    path.write_text(path.read_text(encoding="utf-8") + "\n- 乱码行\n", encoding="utf-8")
    result = check_data.check(tmp_path, min_records=1)
    assert any("无法解析的行" in e for e in result["errors"])


def test_date_mismatch_fails(tmp_path):
    path = tmp_path / "2026" / "20261012 百度实时热点.md"
    fmt.atomic_write_text(path, fmt.render([fmt.Record("甲", "01:00:00", "1")], date="2026-10-11"))
    result = check_data.check(tmp_path, min_records=1)
    assert any("front matter 日期不符" in e for e in result["errors"])


def test_declared_records_mismatch_fails(tmp_path):
    path = tmp_path / "2026" / "20261012 百度实时热点.md"
    text = fmt.render([fmt.Record("甲", "01:00:00", "1")], date="2026-10-12")
    fmt.atomic_write_text(path, text.replace("records: 1", "records: 99"))
    result = check_data.check(tmp_path, min_records=1)
    assert any("records 计数不符" in e for e in result["errors"])


def test_legacy_json_counts_toward_baseline(tmp_path):
    path = tmp_path / "2021" / "20210727 百度实时热点.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '{"甲": [{"time": "2021-07-27 08:00:00+08:00", "hot_index": "3"}]}',
        encoding="utf-8",
    )
    result = check_data.check(tmp_path, min_records=1)
    assert result["errors"] == []
    assert result["json_records"] == 1


def test_real_repo_state_is_green():
    """对真实仓库当前状态跑一次（结构 + 下限）。"""
    root = Path(__file__).resolve().parent.parent
    result = check_data.check(root)
    assert result["errors"] == []
    assert result["total_records"] >= check_data.MIN_RECORDS


def test_cli_returns_nonzero_on_failure(tmp_path, capsys):
    write_day(tmp_path, "2026-10-12", titles=1, rows_each=1)
    code = check_data.main(["--root", str(tmp_path), "--min-records", "5"])
    assert code == 1
    assert "FAIL" in capsys.readouterr().out


def test_cli_returns_zero_on_success(tmp_path):
    write_day(tmp_path, "2026-10-12", titles=1, rows_each=1)
    assert check_data.main(["--root", str(tmp_path), "--min-records", "1"]) == 0


def test_cli_accepts_exact_flag(tmp_path):
    """精确校验开关生效：临时仓库只有 1 条，要求 1,850,921 条必须失败。"""
    write_day(tmp_path, "2026-10-12", titles=1, rows_each=1)
    code = check_data.main(
        ["--root", str(tmp_path), "--expect-records", "1850921", "--min-records", "1"]
    )
    assert code == 1


def test_cli_exact_flag_passes_when_equal(tmp_path):
    write_day(tmp_path, "2026-10-12", titles=2, rows_each=1)
    code = check_data.main(["--root", str(tmp_path), "--expect-records", "2", "--min-records", "1"])
    assert code == 0
