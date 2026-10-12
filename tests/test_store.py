"""存储层测试：原子写、文件锁、幂等追加、坏文件自愈、v0 兼容（规范 §9 §10）。"""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from baidutop import format as fmt
from baidutop import store

TZ = timezone(timedelta(hours=8))
DATE = "2025-03-08"


def rec(title: str, hms: str, hot: str) -> fmt.Record:
    return fmt.Record(title, hms, hot)


def test_md_path_for_layout(tmp_path):
    path = store.md_path_for(tmp_path, "2025-03-08")
    assert path == tmp_path / "2025" / "20250308 百度实时热点.md"


def test_md_path_for_rejects_bad_date(tmp_path):
    with pytest.raises(store.StoreError):
        store.md_path_for(tmp_path, "2025-3-8")


def test_append_creates_file_with_front_matter(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    stats = store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE)
    assert stats == {"added": 1, "skipped": 0, "total": 1, "unparsed": 0}
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    assert 'date: "2025-03-08"' in text
    assert "## 甲" in text
    assert "- 01:00:00 1" in text


def test_append_is_idempotent(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    batch = [rec("甲", "01:00:00", "1"), rec("乙", "02:00:00", "2")]
    first = store.append_records(path, batch, date=DATE)
    second = store.append_records(path, batch, date=DATE)
    assert first["added"] == 2
    assert second == {"added": 0, "skipped": 2, "total": 2, "unparsed": 0}
    assert len(fmt.load_md(path).records) == 2


def test_same_second_different_hot_both_kept(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(
        path,
        [rec("同秒", "14:01:44", "2474046"), rec("同秒", "14:01:44", "2969728")],
        date=DATE,
    )
    doc = fmt.load_md(path)
    assert [r.hot for r in doc.records] == ["2474046", "2969728"]


def test_append_accumulates_across_batches(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE)
    store.append_records(path, [rec("甲", "02:00:00", "2"), rec("乙", "02:00:00", "3")], date=DATE)
    doc = fmt.load_md(path)
    assert [r.key() for r in doc.records] == [
        ("甲", "01:00:00", "1"),
        ("甲", "02:00:00", "2"),
        ("乙", "02:00:00", "3"),
    ]
    assert doc.meta["titles"] == "2"
    assert doc.meta["records"] == "3"


def test_concurrent_appends_lose_nothing(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(path, [rec("种子", "00:00:00", "0")], date=DATE)

    def worker(worker_id: int) -> None:
        batch = [rec(f"标题{worker_id}-{i}", f"{i:02d}:00:00", str(i)) for i in range(1, 11)]
        store.append_records(path, batch, date=DATE)

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(worker, range(8)))

    doc = fmt.load_md(path)
    keys = [r.key() for r in doc.records]
    assert len(keys) == len(set(keys)) == 81
    assert "种子" in {r.title for r in doc.records}


def test_lock_timeout_raises(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE)
    with store.file_lock(path):
        with pytest.raises(store.StoreError):
            store.append_records(path, [rec("乙", "02:00:00", "2")], date=DATE, lock_timeout=0.2)


def test_corrupt_file_is_backed_up_not_wiped(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("这不是合法内容\n而且没有结构\n", encoding="utf-8")

    stats = store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE)
    backup = path.with_name(path.name + store.CORRUPT_SUFFIX)
    assert backup.exists()
    assert "这不是合法内容" in backup.read_text(encoding="utf-8")
    assert [r.key() for r in fmt.load_md(path).records] == [("甲", "01:00:00", "1")]
    assert stats["added"] == 1


def test_unparsed_rows_do_not_block_and_are_preserved(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE)
    text = path.read_text(encoding="utf-8") + "\n## 乙\n\n- 乱码行\n"
    path.write_text(text, encoding="utf-8")

    stats = store.append_records(path, [rec("丙", "03:00:00", "3")], date=DATE)
    assert stats["unparsed"] == 1
    assert stats["added"] == 1
    assert path.with_name(path.name + store.CORRUPT_SUFFIX).exists()
    assert "乱码行" in path.with_name(path.name + store.CORRUPT_SUFFIX).read_text(encoding="utf-8")


def test_legacy_json_is_migrated_on_append(tmp_path):
    md = store.md_path_for(tmp_path, "2020-11-04")
    md.parent.mkdir(parents=True, exist_ok=True)
    legacy = md.with_name("20201104 实时热点.json")
    legacy.write_text(
        json.dumps(
            {"蚂蚁集团A股H股双双暂缓上市": [{"time": "2020-11-04 09:00:00.1+08:00", "count": "8800000"}]},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    stats = store.append_records(md, [fmt.Record("新标题", "10:00:00", "999")], date="2020-11-04")
    doc = fmt.load_md(md)
    assert doc.date == "2020-11-04"
    assert [(r.title, r.time, r.hot) for r in doc.records] == [
        ("蚂蚁集团A股H股双双暂缓上市", "09:00:00", "8800000"),
        ("新标题", "10:00:00", "999"),
    ]
    assert stats["total"] == 2
    assert legacy.exists()  # v0 源文件由 TASK-005 统一清理


def test_load_records_prefers_md(tmp_path):
    date = "2025-03-08"
    md = store.md_path_for(tmp_path, date)
    store.append_records(md, [rec("MD标题", "01:00:00", "1")], date=date)
    legacy = md.with_name("20250308 百度实时热点.json")
    legacy.write_text(
        json.dumps({"JSON标题": [{"time": "2025-03-08 01:00:00+08:00", "hot_index": "2"}]}, ensure_ascii=False),
        encoding="utf-8",
    )
    loaded_date, records = store.load_records(md)
    assert loaded_date == date
    assert [r.title for r in records] == ["MD标题"]


def test_load_records_falls_back_to_legacy(tmp_path):
    md = store.md_path_for(tmp_path, "2021-07-27")
    md.parent.mkdir(parents=True, exist_ok=True)
    legacy = md.with_name("20210727 百度实时热点.json")
    legacy.write_text(
        json.dumps({"标题": [{"time": "2021-07-27 08:00:00.5+08:00", "hot_index": "3"}]}, ensure_ascii=False),
        encoding="utf-8",
    )
    date, records = store.load_records(md)
    assert date == "2021-07-27"
    assert [r.hot for r in records] == ["3"]


def test_append_skips_empty_title(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    stats = store.append_records(path, [rec("", "01:00:00", "1")], date=DATE)
    assert stats["added"] == 0
    assert stats["skipped"] == 1


def test_generated_field_optional(tmp_path):
    path = store.md_path_for(tmp_path, DATE)
    store.append_records(path, [rec("甲", "01:00:00", "1")], date=DATE, generated="2026-10-12T18:00:00+08:00")
    assert 'generated: "2026-10-12T18:00:00+08:00"' in path.read_text(encoding="utf-8")


# ------------------------------------------------------------- 主流程集成

class FakeCrawler:
    def __init__(self, pairs):
        self.pairs = pairs

    def crawl_hot_search(self, board: str = "realtime"):
        return self.pairs


def test_run_once_writes_md_and_is_same_day(tmp_path):
    import crawl_baidu_top as crawler

    captured = datetime(2026, 2, 25, 23, 59, 59, tzinfo=TZ)
    result = crawler.run_once(
        root=tmp_path,
        crawler=FakeCrawler([("标题A", "123"), ("标题B", "456")]),
        captured_at=captured,
    )
    assert result["added"] == 2
    path = Path(result["path"])
    assert path.name == "20260225 百度实时热点.md"
    doc = fmt.load_md(path)
    assert doc.date == "2026-02-25"
    # 文件名日期与记录时间来自同一时刻，不再出现跨日错位（v0 缺陷 D3）
    assert {r.time for r in doc.records} == {"23:59:59"}


def test_run_once_rerun_is_idempotent(tmp_path):
    import crawl_baidu_top as crawler

    captured = datetime(2026, 2, 25, 12, 0, 0, tzinfo=TZ)
    fake = FakeCrawler([("标题A", "123")])
    crawler.run_once(root=tmp_path, crawler=fake, captured_at=captured)
    second = crawler.run_once(root=tmp_path, crawler=fake, captured_at=captured)
    assert second["added"] == 0
    assert second["skipped"] == 1


def test_run_once_empty_result_writes_nothing(tmp_path):
    import crawl_baidu_top as crawler

    result = crawler.run_once(
        root=tmp_path,
        crawler=FakeCrawler([]),
        captured_at=datetime(2026, 2, 25, 12, 0, 0, tzinfo=TZ),
    )
    assert result["crawled"] == 0
    assert not list(tmp_path.rglob("*.md"))
