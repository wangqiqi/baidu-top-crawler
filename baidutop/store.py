"""MD v1 存储层：文件锁 + 原子替换 + 幂等追加 + v0 兼容读取。

规范见 docs/data-format.md §9 §10：
- 追加幂等：``(title, time)`` 已存在则跳过；
- 原子写：临时文件 + ``os.replace``，禁止原地截断；
- 排他锁：``<file>.lock`` + ``fcntl.flock``，防并发抓取互相覆盖；
- 坏文件自愈：解析失败或存在无法解析的行 → 备份 ``<file>.corrupt`` 后重建，不静默清空。
"""

from __future__ import annotations

import errno
import fcntl
import os
import time
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path

from . import format as fmt

CORRUPT_SUFFIX = ".corrupt"
LOCK_SUFFIX = ".lock"
DEFAULT_LOCK_TIMEOUT = 30.0


class StoreError(RuntimeError):
    """存储层错误（锁超时、日期缺失等）。"""


@contextmanager
def file_lock(
    path: os.PathLike[str] | str,
    *,
    timeout: float = DEFAULT_LOCK_TIMEOUT,
    poll: float = 0.05,
) -> Iterator[None]:
    """对 ``path`` 加排他锁（跨进程）。超时抛 :class:`StoreError`。"""
    lock_path = Path(str(path) + LOCK_SUFFIX)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(lock_path, "a+", encoding="utf-8")
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as exc:
                if exc.errno not in (errno.EACCES, errno.EAGAIN):
                    raise
                if time.monotonic() >= deadline:
                    raise StoreError(f"获取文件锁超时: {lock_path}") from exc
                time.sleep(poll)
        yield
    finally:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()


def md_path_for(root: os.PathLike[str] | str, date: str) -> Path:
    """按 v1 命名规则生成路径：``<root>/YYYY/YYYYMMDD 百度实时热点.md``。"""
    compact = date.replace("-", "")
    if len(compact) != 8:
        raise StoreError(f"非法日期: {date!r}")
    return Path(root) / compact[:4] / f"{compact} 百度实时热点.md"


def legacy_json_paths(md_path: os.PathLike[str] | str) -> list[Path]:
    """同日的 v0 JSON 候选路径（含无「百度」前缀的旧命名）。"""
    target = Path(md_path)
    compact = target.name.split(" ")[0]
    return [
        target.with_name(f"{compact} 百度实时热点.json"),
        target.with_name(f"{compact} 实时热点.json"),
    ]


def _read_any(md_path: Path) -> tuple[str, list[fmt.Record], Path | None, list[str]]:
    """读取 MD；不存在时回退到 v0 JSON。返回 (日期, 记录, 来源, 告警)。"""
    warnings: list[str] = []
    if md_path.exists():
        doc = fmt.load_md(md_path)
        date = doc.date or fmt.file_date_from_name(md_path)
        return date, list(doc.records), md_path, warnings

    for candidate in legacy_json_paths(md_path):
        if candidate.exists():
            date, records = fmt.read_legacy_json(candidate)
            warnings.append(f"从 v0 JSON 读取: {candidate.name}")
            return date, records, candidate, warnings

    return fmt.file_date_from_name(md_path), [], None, warnings


def load_records(
    path: os.PathLike[str] | str,
) -> tuple[str, list[fmt.Record]]:
    """读取当日记录（MD 优先，其次 v0 JSON）。"""
    target = Path(path)
    date, records, _source, _warnings = _read_any(target)
    return date, records


def write_document(
    path: os.PathLike[str] | str,
    records: Sequence[fmt.Record],
    *,
    date: str | None = None,
    generated: str | None = None,
) -> str:
    """整文件原子写出（调用方负责加锁）。返回写出的文本。"""
    target = Path(path)
    doc_date = date or fmt.file_date_from_name(target)
    text = fmt.render(records, date=doc_date, generated=generated)
    fmt.atomic_write_text(target, text)
    return text


def _backup_corrupt(target: Path) -> Path:
    backup = target.with_name(target.name + CORRUPT_SUFFIX)
    counter = 1
    while backup.exists():
        backup = target.with_name(f"{target.name}{CORRUPT_SUFFIX}.{counter}")
        counter += 1
    os.replace(target, backup)
    return backup


def append_records(
    path: os.PathLike[str] | str,
    records: Sequence[fmt.Record],
    *,
    date: str | None = None,
    generated: str | None = None,
    lock_timeout: float = DEFAULT_LOCK_TIMEOUT,
) -> dict[str, int]:
    """幂等追加记录并原子落盘。

    返回统计：``{"added": n, "skipped": n, "upgraded": n, "total": n, "unparsed": n}``。

    ``upgraded`` = 同一幂等键的旧记录原本缺 ``rank``、本次补上的条数（原地升级，不新增行）。
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)

    with file_lock(target, timeout=lock_timeout):
        existing: list[fmt.Record] = []
        unparsed = 0
        doc_date = date or fmt.file_date_from_name(target)

        if target.exists():
            try:
                doc = fmt.load_md(target)
                existing = list(doc.records)
                unparsed = len(doc.unparsed)
                doc_date = date or doc.date or doc_date
                if unparsed:
                    # 保留原始内容副本，但不阻塞写入
                    _backup_corrupt(target)
            except Exception:  # noqa: BLE001 — 任何解析失败都走自愈路径
                _backup_corrupt(target)
                existing = []
        else:
            legacy_date, legacy_records, source, _warn = _read_any(target)
            if source is not None and source.suffix == ".json":
                existing = legacy_records
                doc_date = date or legacy_date

        # 幂等键 (title, time, hot)；rank 是键上的属性，可原地升级（规范 §9）
        index: dict[tuple, int] = {}
        for pos, rec in enumerate(existing):
            index.setdefault((rec.title, rec.time, rec.hot), pos)

        merged = list(existing)
        added = 0
        skipped = 0
        upgraded = 0
        for rec in records:
            if not rec.title.strip():
                skipped += 1
                continue
            key = (rec.title, rec.time, rec.hot)
            pos = index.get(key)
            if pos is None:
                index[key] = len(merged)
                merged.append(rec)
                added += 1
                continue
            old = merged[pos]
            if old.rank is None and rec.rank is not None:
                # 同一观测补上 rank：原地升级，不新增行
                merged[pos] = replace(old, rank=rec.rank)
                upgraded += 1
                continue
            # 已有 rank 不被覆盖（避免抓取抖动改写历史位次）；其余视为重复
            skipped += 1

        text = fmt.render(merged, date=doc_date, generated=generated)
        fmt.atomic_write_text(target, text)

    return {
        "added": added,
        "skipped": skipped,
        "upgraded": upgraded,
        "total": len(merged),
        "unparsed": unparsed,
    }
