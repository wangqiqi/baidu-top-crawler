#!/usr/bin/env python3
"""体积预算检查：数据目录 / 工作区 / git pack。

默认只报告；``--strict`` 时按预算硬失败（供 TASK-009 使用）。
预算见 docs/data-format.md §13：数据 ≤ 55MB · 工作区 ≤ 65MB · 新克隆（pack）≤ 25MB。
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parent.parent
DATA_MAX_MB = 55.0
WORKTREE_MAX_MB = 65.0
PACK_MAX_MB = 25.0


def _dir_bytes(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return total


def measure(root: Path) -> dict[str, float]:
    data_bytes = 0
    json_bytes = 0
    md_bytes = 0
    for year_dir in sorted(root.glob("20*")):
        if not year_dir.is_dir():
            continue
        for item in year_dir.rglob("*"):
            if not item.is_file():
                continue
            try:
                size = item.stat().st_size
            except OSError:
                continue
            data_bytes += size
            if item.suffix == ".json":
                json_bytes += size
            elif item.suffix == ".md":
                md_bytes += size

    worktree_bytes = 0
    for item in root.rglob("*"):
        if ".git" in item.parts:
            continue
        if item.is_file():
            try:
                worktree_bytes += item.stat().st_size
            except OSError:
                pass

    pack_bytes = 0
    try:
        out = subprocess.run(
            ["git", "count-objects", "-v"],
            cwd=str(root),
            capture_output=True,
            text=True,
            check=False,
        ).stdout
        for line in out.splitlines():
            if line.startswith("size-pack:"):
                pack_bytes = int(line.split(":", 1)[1].strip()) * 1024
    except (OSError, ValueError):
        pass

    return {
        "data_mb": data_bytes / 1e6,
        "json_mb": json_bytes / 1e6,
        "md_mb": md_bytes / 1e6,
        "worktree_mb": worktree_bytes / 1e6,
        "pack_mb": pack_bytes / 1e6,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="体积预算检查")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--strict", action="store_true", help="超预算时返回非零")
    parser.add_argument(
        "--no-pack",
        action="store_true",
        help="跳过 git pack 预算（历史重写尚未执行时使用）",
    )
    args = parser.parse_args(argv)

    m = measure(args.root)
    print(f"数据目录: {m['data_mb']:.1f}MB（JSON {m['json_mb']:.1f}MB · MD {m['md_mb']:.1f}MB）")
    print(f"工作区:   {m['worktree_mb']:.1f}MB")
    print(f"git pack: {m['pack_mb']:.1f}MB")

    if m["json_mb"] > 0 and m["md_mb"] > 0:
        ratio = m["md_mb"] / m["json_mb"] * 100
        print(f"MD/JSON 比: {ratio:.1f}%（省 {100 - ratio:.1f}%）")

    failures: list[str] = []
    if m["data_mb"] > DATA_MAX_MB:
        failures.append(f"数据 {m['data_mb']:.1f}MB > 预算 {DATA_MAX_MB}MB")
    if m["worktree_mb"] > WORKTREE_MAX_MB:
        failures.append(f"工作区 {m['worktree_mb']:.1f}MB > 预算 {WORKTREE_MAX_MB}MB")
    if not args.no_pack and m["pack_mb"] > PACK_MAX_MB:
        failures.append(f"git pack {m['pack_mb']:.1f}MB > 预算 {PACK_MAX_MB}MB（需 TASK-009 重写历史）")

    for failure in failures:
        print(f"{'FAIL' if args.strict else 'WARN'}: {failure}")

    if args.strict and failures:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
