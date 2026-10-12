#!/usr/bin/env python3
"""数据完整性检查：解析全部 v1 MD 与遗留 v0 JSON，核对记录数与规范一致性。

迁移前（存在 JSON）与迁移后（只剩 MD）都能跑：
- 任一文件解析失败 / MD 存在无法解析的行 / front matter 日期与文件名不符 → 失败
- 迁移完成后（无遗留 JSON）强制校验记录总数 == --expect-records
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
EXPECTED_RECORDS = 1850921


def check(root: Path, expect_records: int) -> dict[str, object]:
    errors: list[str] = []
    warnings: list[str] = []
    md_files = sorted(root.glob("20*/*.md"))
    json_files = sorted(root.glob("20*/*.json"))

    md_records = 0
    json_records = 0
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
            errors.append(f"titles 计数不符 {path}: 声明 {titles}")
        md_records += len(doc.records)
        md_dates[expect_date] += 1

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

    if not json_files and md_files:
        if md_records != expect_records:
            errors.append(f"记录总数不符: 期望 {expect_records} / 实际 {md_records}")
    elif json_files and not md_files:
        if json_records != expect_records:
            errors.append(f"遗留 JSON 记录总数不符: 期望 {expect_records} / 实际 {json_records}")
    else:
        total = md_records + json_records
        if total != expect_records:
            warnings.append(f"MD+JSON 合计 {total} 条，期望 {expect_records}（迁移混合态下仅提示）")

    return {
        "md_files": len(md_files),
        "json_files": len(json_files),
        "md_records": md_records,
        "json_records": json_records,
        "errors": errors,
        "warnings": warnings,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="数据完整性检查")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--expect-records", type=int, default=EXPECTED_RECORDS)
    parser.add_argument("--json-report", type=Path, help="把结果写成 JSON")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    result = check(args.root, args.expect_records)

    if not args.quiet:
        print(
            f"数据检查: MD {result['md_files']} 个 / {result['md_records']} 条 · "
            f"JSON {result['json_files']} 个 / {result['json_records']} 条"
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
