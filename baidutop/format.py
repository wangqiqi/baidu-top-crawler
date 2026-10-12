"""百度热搜数据格式 v1（紧凑 Markdown 分节）读写实现。

权威规范：docs/data-format.md。本模块是纯文本 ↔ 记录 的转换层，
不含抓取逻辑；文件系统写入用 :func:`atomic_write_text`（原子替换）。

记录级契约（§8）：
    (title, time_sec, hot) 有序多重集在 v0 → v1 前后完全一致；
    唯一允许的有损是微秒 6 位被丢弃。
"""

from __future__ import annotations

import json
import os
import re
import tempfile
from collections import OrderedDict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

SCHEMA_VERSION = 1
TZ = timezone(timedelta(hours=8))
TZ_LABEL = "+08:00"
BOARD = "realtime"
SOURCE_URL = "https://top.baidu.com/board?tab=realtime"

FM_FENCE = "---"
TITLE_PREFIX = "## "
ROW_PREFIX = "- "

# v0 时间戳容错：`T` 或空格分隔、可带 6 位微秒、可带时区；两种写法都出现过。
_ISO_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$"
)
# v1 数据行：时间可为 `HH:MM:SS`（本日）或 `YYYY-MM-DD HH:MM:SS`（跨日）。
_ROW_RE = re.compile(
    r"^(?:(\d{4}-\d{2}-\d{2})\s+)?(\d{2}:\d{2}:\d{2})\s+(.*)$"
)
_FILE_DATE_RE = re.compile(r"(\d{8})")


class FormatError(ValueError):
    """内容不符合 v1 规范。"""


@dataclass(frozen=True)
class Record:
    """一条热搜记录（标题 · 秒级时间 · 热度原文）。"""

    title: str
    time: str
    hot: str

    def key(self) -> Tuple[str, str, str]:
        return (self.title, self.time, self.hot)


@dataclass
class Document:
    """解析结果：front matter + 记录 + 无法解析的原始行。"""

    meta: Dict[str, str] = field(default_factory=dict)
    records: List[Record] = field(default_factory=list)
    unparsed: List[Tuple[int, str]] = field(default_factory=list)

    @property
    def date(self) -> str:
        return self.meta.get("date", "")


# --------------------------------------------------------------------------
# 转义（规范 §7）
# --------------------------------------------------------------------------

def escape_title(title: str) -> str:
    """转义标题：``\\`` → ``\\\\``，换行 → 字面 ``\\n``；其余原样保留。"""
    out = title.replace("\\", "\\\\")
    for ch in ("\r\n", "\n", "\r"):
        out = out.replace(ch, "\\n")
    return out


def unescape_title(text: str) -> str:
    """还原 :func:`escape_title` 的转义（反序解码）。"""
    out: List[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
            if nxt == "n":
                out.append("\n")
                i += 2
                continue
        out.append(ch)
        i += 1
    return "".join(out)


# --------------------------------------------------------------------------
# 时间（规范 §5.3）
# --------------------------------------------------------------------------

def normalize_time(value: str, file_date: str) -> str:
    """把 v0 ISO 时间戳归一为 v1 行内时间：本日 ``HH:MM:SS``，跨日带日期。"""
    m = _ISO_RE.match(value.strip())
    if not m:
        raise FormatError(f"无法解析时间戳: {value!r}")
    date, hms = m.group(1), m.group(2)
    return hms if date == file_date else f"{date} {hms}"


def format_datetime(dt: datetime, file_date: str) -> str:
    """把 datetime 渲染为 v1 行内时间（统一 UTC+8）。"""
    local = dt.astimezone(TZ)
    stamp = local.strftime("%Y-%m-%d %H:%M:%S")
    return normalize_time(stamp, file_date)


def now_utc8() -> datetime:
    """当前 UTC+8 时间（全项目统一时区来源）。"""
    return datetime.now(timezone.utc).astimezone(TZ)


def file_date_from_name(path: "os.PathLike[str] | str") -> str:
    """从文件名提取 ``YYYYMMDD`` 并转成 ``YYYY-MM-DD``。"""
    m = _FILE_DATE_RE.search(Path(path).name)
    if not m:
        raise FormatError(f"文件名中没有日期: {path}")
    raw = m.group(1)
    return f"{raw[:4]}-{raw[4:6]}-{raw[6:]}"


# --------------------------------------------------------------------------
# 渲染 / 解析
# --------------------------------------------------------------------------

def _quote(value: str) -> str:
    escaped = value.replace('"', '\\"')
    return f'"{escaped}"'


def render(
    records: Iterable[Record],
    *,
    date: str,
    generated: Optional[str] = None,
    source: str = SOURCE_URL,
    board: str = BOARD,
) -> str:
    """渲染整个 v1 文档。空标题被跳过；标题顺序 = 首次出现顺序。"""
    sections: "OrderedDict[str, List[Record]]" = OrderedDict()
    snapshots: set = set()
    for rec in records:
        if not rec.title.strip():
            continue
        sections.setdefault(rec.title, []).append(rec)
        snapshots.add(rec.time)

    total = sum(len(v) for v in sections.values())
    lines: List[str] = [
        FM_FENCE,
        f"schema: {SCHEMA_VERSION}",
        f"date: {_quote(date)}",
        f"timezone: {_quote(TZ_LABEL)}",
        f"board: {board}",
        f"source: {_quote(source)}",
        f"snapshots: {len(snapshots)}",
        f"titles: {len(sections)}",
        f"records: {total}",
    ]
    if generated:
        lines.append(f"generated: {_quote(generated)}")
    lines.append(FM_FENCE)
    lines.append("")

    for title, recs in sections.items():
        lines.append(TITLE_PREFIX + escape_title(title))
        lines.append("")
        for rec in recs:
            lines.append(f"{ROW_PREFIX}{rec.time} {rec.hot}")
        lines.append("")

    return "\n".join(lines).rstrip("\n") + "\n"


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1].replace('\\"', '"')
    return value


def parse(text: str, *, fallback_date: Optional[str] = None) -> Document:
    """解析 v1 文档；不合规的行保留进 ``unparsed``，不静默丢弃。"""
    lines = text.splitlines()
    doc = Document()
    idx = 0

    if lines and lines[0].strip() == FM_FENCE:
        idx = 1
        while idx < len(lines) and lines[idx].strip() != FM_FENCE:
            raw = lines[idx].strip()
            if raw and ":" in raw:
                key, _, value = raw.partition(":")
                doc.meta[key.strip()] = _unquote(value)
            idx += 1
        idx += 1  # 跳过收尾围栏
    if fallback_date and "date" not in doc.meta:
        doc.meta["date"] = fallback_date

    current: Optional[str] = None
    for lineno, raw in enumerate(lines[idx:], start=idx + 1):
        stripped = raw.rstrip()
        if not stripped:
            continue
        if stripped.startswith(TITLE_PREFIX):
            title = unescape_title(stripped[len(TITLE_PREFIX):])
            current = title if title.strip() else None
            continue
        if stripped.startswith(ROW_PREFIX):
            if current is None:
                doc.unparsed.append((lineno, raw))
                continue
            m = _ROW_RE.match(stripped[len(ROW_PREFIX):])
            if not m:
                doc.unparsed.append((lineno, raw))
                continue
            date_part, hms, hot = m.group(1), m.group(2), m.group(3)
            token = f"{date_part} {hms}" if date_part else hms
            doc.records.append(Record(title=current, time=token, hot=hot))
            continue
        doc.unparsed.append((lineno, raw))

    return doc


# --------------------------------------------------------------------------
# 文件 IO
# --------------------------------------------------------------------------

def atomic_write_text(path: "os.PathLike[str] | str", text: str) -> None:
    """同目录临时文件 + ``os.replace`` 原子替换，避免半截文件。"""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(target.parent), prefix=f".{target.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_md(path: "os.PathLike[str] | str") -> Document:
    """读取 v1 文件；缺 front matter 时用文件名兜底日期。"""
    text = Path(path).read_text(encoding="utf-8")
    fallback = None
    try:
        fallback = file_date_from_name(path)
    except FormatError:
        pass
    return parse(text, fallback_date=fallback)


# --------------------------------------------------------------------------
# v0 JSON 兼容读取（规范 §12）
# --------------------------------------------------------------------------

def read_legacy_json(
    path: "os.PathLike[str] | str", *, file_date: Optional[str] = None
) -> Tuple[str, List[Record]]:
    """读取 v0 JSON 分组格式，返回 ``(日期, 记录列表)``。

    兼容 ``count`` / ``hot_index`` 两种热度键与 ``T`` / 空格两种时间分隔符。
    """
    target = Path(path)
    date = file_date or file_date_from_name(target)
    data = json.loads(target.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    if not isinstance(data, dict):
        raise FormatError(f"{target}: 顶层不是对象")

    records: List[Record] = []
    for title, entries in data.items():
        if not isinstance(title, str) or not title.strip():
            continue
        for entry in entries or []:
            if not isinstance(entry, dict):
                raise FormatError(f"{target}: 条目不是对象: {entry!r}")
            hot = entry.get("hot_index", entry.get("count"))
            records.append(
                Record(
                    title=title,
                    time=normalize_time(str(entry.get("time", "")), date),
                    hot=str(hot),
                )
            )
    return date, records


def index_by_title(records: Sequence[Record]) -> "OrderedDict[str, List[Record]]":
    """按标题分组，保持首次出现顺序（校验与增量合并用）。"""
    grouped: "OrderedDict[str, List[Record]]" = OrderedDict()
    for rec in records:
        grouped.setdefault(rec.title, []).append(rec)
    return grouped
