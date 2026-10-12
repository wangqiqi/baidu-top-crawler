#!/usr/bin/env python3
"""数据完整性检查：解析全部 v1 MD 与遗留 v0 JSON，核对结构一致性与记录数下限。

迁移前（存在 JSON）与迁移后（只剩 MD）都能跑：
- 任一文件解析失败 / MD 存在无法解析的行 / front matter 日期与文件名不符 → 失败
- 声明的 records / titles 计数与实际不符 → 失败
- **记录总数低于历史基线 → 失败（疑似数据丢失）**；总数增长是正常的（每天都在抓新数据）

注意（TASK-010 回归修复）：历史基线是**下限**而不是等号。v1.0.0 曾把它当作精确值，
导致每次线上抓取后校验必然失败、提交步骤永不执行。需要精确比对时用 ``--expect-records``。
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from baidutop import format as fmt  # noqa: E402

DEFAULT_ROOT = Path(__file__).resolve().parent.parent
# 迁移完成时的记录数（2026-10-12）。只作为下限：低于它说明历史数据丢了。
MIN_RECORDS = 1850921


def check(
    root: Path,
    expect_records: int | None = None,
    min_records: int = MIN_RECORDS,
) -> dict[str, object]:
    errors: list[str] = []
    warnings: list[str] = []
    md_files = sorted(root.glob("20*/*.md"))
    json_files = sorted(root.glob("20*/*.json"))

    md_records = 0
    json_records = 0
    ranked_records = 0
    unranked_records = 0
    rank_conflicts: list[str] = []
    ranks_by_key: dict[tuple[str, str], set[int]] = {}
    md_dates: Counter = Counter()
    json_dates: Counter = Counter()

    for path in md_files:
        try:
            doc = fmt.load_md(path)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"MD 解析失败 {path}: {type(exc).__name__}: {exc}")
            continue
        if doc.unparsed:
            errors.append(f"MD 存在无法解析的行 {path}: {doc.unparsed[:3]}")
        expect_date = fmt.file_date_from_name(path)
        if doc.date != expect_date:
            errors.append(f"front matter 日期不符 {path}: {doc.date!r} != {expect_date!r}")
        declared = doc.meta.get("records")
        if declared is not None and int(declared) != len(doc.records):
            errors.append(f"records 计数不符 {path}: 声明 {declared} / 实际 {len(doc.records)}")
        titles = doc.meta.get("titles")
        if titles is not None and int(titles) != len({r.title for r in doc.records}):
            errors.append(
                f"titles 计数不符 {path}: 声明 {titles} / 实际 {len({r.title for r in doc.records})}"
            )
        for rec in doc.records:
            if rec.rank is None:
                unranked_records += 1
                continue
            ranked_records += 1
            if rec.rank < 1:
                errors.append(f"rank 非法（须 ≥1）{path}: {rec.title!r} rank={rec.rank}")
            ranks_by_key.setdefault((rec.title, rec.time), set()).add(rec.rank)
        md_records += len(doc.records)
        md_dates[expect_date] += 1

    for key, ranks in ranks_by_key.items():
        if len(ranks) > 1:
            rank_conflicts.append(f"{key[0]!r} @ {key[1]} 出现多个 rank: {sorted(ranks)}")
    for conflict in rank_conflicts[:5]:
        errors.append(f"同一 (标题, 时间) 存在不同 rank：{conflict}")
    if len(rank_conflicts) > 5:
        errors.append(f"...另有 {len(rank_conflicts) - 5} 处 rank 冲突")

    for path in json_files:
        try:
            date, records = fmt.read_legacy_json(path)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"JSON 解析失败 {path}: {type(exc).__name__}: {exc}")
            continue
        json_records += len(records)
        json_dates[date] += 1

    both = sorted(set(md_dates) & set(json_dates))
    if both:
        warnings.append(f"{len(both)} 天的 MD 与 JSON 并存（迁移进行中）: {both[:3]}")

    total = md_records + json_records
    if total < min_records:
        errors.append(f"记录总数 {total} 低于历史基线 {min_records}（疑似数据丢失）")
    if expect_records is not None and total != expect_records:
        errors.append(f"记录总数不符（精确校验）: 期望 {expect_records} / 实际 {total}")

    return {
        "md_files": len(md_files),
        "json_files": len(json_files),
        "md_records": md_records,
        "ranked_records": ranked_records,
        "unranked_records": unranked_records,
        "json_records": json_records,
        "total_records": total,
        "min_records": min_records,
        "errors": errors,
        "warnings": warnings,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="数据完整性检查")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument(
        "--expect-records",
        type=int,
        default=None,
        help="精确校验记录总数（迁移验收用；默认只校验不低于基线）",
    )
    parser.add_argument("--min-records", type=int, default=MIN_RECORDS, help="记录总数下限")
    parser.add_argument("--json-report", type=Path, help="把结果写成 JSON")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    result = check(args.root, args.expect_records, args.min_records)

    if not args.quiet:
        print(
            f"数据检查: MD {result['md_files']} 个 / {result['md_records']} 条 · "
            f"JSON {result['json_files']} 个 / {result['json_records']} 条 · "
            f"合计 {result['total_records']} 条（基线 {result['min_records']}）· "
            f"带 rank {result['ranked_records']} / 无 rank {result['unranked_records']}"
        )
        for warning in result["warnings"]:
            print(f"WARN: {warning}")
        for error in result["errors"]:
            print(f"FAIL: {error}")

    if args.json_report:
        args.json_report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
