#!/usr/bin/env python3
"""v0 JSON → v1 紧凑 Markdown 的迁移与校验 CLI。

用法：
    python scripts/migrate_to_md.py --dry-run          # 只报告体积，不落盘
    python scripts/migrate_to_md.py                    # 写出 .md（保留 .json）
    python scripts/migrate_to_md.py --check            # 校验已落盘的 .md 与源 JSON 一致
    python scripts/migrate_to_md.py --delete-json      # 校验通过后删除源 JSON

记录级契约见 docs/data-format.md §8；本脚本保证 (title, time, hot) 有序序列不变。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from baidutop import format as fmt  # noqa: E402

DEFAULT_ROOT = Path(__file__).resolve().parent.parent


def md_path_for(json_path: Path) -> Path:
    """v0 文件名（含无「百度」前缀的旧命名）→ v1 统一命名。"""
    date = fmt.file_date_from_name(json_path).replace("-", "")
    return json_path.with_name(f"{date} 百度实时热点.md")


def convert_one(
    json_path: Path,
    *,
    write: bool = True,
    check_only: bool = False,
    generated: str | None = None,
) -> dict[str, object]:
    """迁移单个文件并做记录级校验，返回报告字典。"""
    report: dict[str, object] = {"json": str(json_path), "ok": False}
    try:
        date, records = fmt.read_legacy_json(json_path)
        md_path = md_path_for(json_path)
        report.update({"md": str(md_path), "date": date, "records": len(records)})

        if check_only:
            if not md_path.exists():
                report["error"] = "目标 .md 不存在"
                return report
            doc = fmt.parse(md_path.read_text(encoding="utf-8"), fallback_date=date)
            text = md_path.read_text(encoding="utf-8")
        else:
            text = fmt.render(records, date=date, generated=generated)
            doc = fmt.parse(text, fallback_date=date)

        source_keys = [r.key() for r in records if r.title.strip()]
        migrated_keys = [r.key() for r in doc.records]
        if source_keys != migrated_keys:
            report["error"] = (
                f"记录不一致: 源 {len(source_keys)} 条 / 迁移 {len(migrated_keys)} 条"
            )
            return report
        if doc.unparsed:
            report["error"] = f"有 {len(doc.unparsed)} 行无法解析: {doc.unparsed[:3]}"
            return report

        if write and not check_only:
            fmt.atomic_write_text(md_path, text)

        report["md_bytes"] = len(text.encode("utf-8"))
        report["json_bytes"] = json_path.stat().st_size
        report["ok"] = True
        return report
    except Exception as exc:  # noqa: BLE001 — CLI 需要逐文件容错
        report["error"] = f"{type(exc).__name__}: {exc}"
        return report


def iter_json_files(root: Path) -> list[Path]:
    return sorted(p for p in root.glob("20*/*.json") if p.is_file())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="v0 JSON → v1 Markdown 迁移")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="仓库根目录")
    parser.add_argument("--dry-run", action="store_true", help="只统计，不写文件")
    parser.add_argument("--check", action="store_true", help="只校验已迁移的 .md")
    parser.add_argument("--delete-json", action="store_true", help="校验通过后删除源 JSON")
    parser.add_argument("--limit", type=int, default=0, help="只处理前 N 个文件（调试用）")
    parser.add_argument("--report", type=Path, help="把 JSON 报告写到指定路径")
    args = parser.parse_args(argv)

    files = iter_json_files(args.root)
    if args.limit:
        files = files[: args.limit]
    if not files:
        print("没有找到 20NN/*.json，迁移可能已完成")
        return 0

    generated = fmt.now_utc8().isoformat()
    reports: list[dict[str, object]] = []
    json_total = md_total = records_total = 0
    failures = 0
    deleted = 0

    for json_path in files:
        rep = convert_one(
            json_path,
            write=not args.dry_run,
            check_only=args.check,
            generated=generated,
        )
        reports.append(rep)
        if rep.get("ok"):
            json_total += int(rep.get("json_bytes") or 0)
            md_total += int(rep.get("md_bytes") or 0)
            records_total += int(rep.get("records") or 0)
            if args.delete_json and not args.check and not args.dry_run:
                json_path.unlink()
                deleted += 1
        else:
            failures += 1
            print(f"FAIL {json_path}: {rep.get('error')}", file=sys.stderr)

    print(f"文件: {len(files)} · 记录: {records_total} · 失败: {failures}")
    if json_total and md_total:
        ratio = md_total / json_total * 100
        print(
            f"体积: JSON {json_total / 1e6:.1f}MB → MD {md_total / 1e6:.1f}MB"
            f"（占 {ratio:.1f}%，省 {100 - ratio:.1f}%）"
        )
    if deleted:
        print(f"已删除源 JSON: {deleted} 个")

    if args.report:
        args.report.write_text(
            json.dumps({"reports": reports, "failures": failures}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"报告: {args.report}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
