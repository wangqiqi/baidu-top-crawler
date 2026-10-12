"""v1 格式的 round-trip 与兼容性测试（规范 §7 §8 §12）。"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest

from baidutop import format as fmt

TZ = timezone(timedelta(hours=8))

SPECIAL_TITLES = [
    "普通标题",
    "#郭婞淳夺中国台北东京奥运首金#",
    "a|b 带竖线",
    "*星号* 强调",
    "-49.7℃!黑龙江迎50年来最冷一天",
    "5.6万人接种疫苗离境后无一感染",
    "反\\斜杠",
    "换\n行",
    "结尾带空格加井号 #",
]


def make_records(file_date: str = "2025-03-08"):
    """构造覆盖特殊标题 + 同秒重复 + 跨日的记录集。"""
    records = []
    for title in SPECIAL_TITLES:
        records.append(fmt.Record(title, "00:19:29", "7974352"))
        records.append(fmt.Record(title, "01:13:56", "7956248"))
    # 同标题同秒不同热度：v0 实测存在 4 例，必须逐行保留
    records.append(fmt.Record("同秒两条", "14:01:44", "2474046"))
    records.append(fmt.Record("同秒两条", "14:01:44", "2969728"))
    # 跨日记录：日期与文件 date 不同，写完整日期
    records.append(fmt.Record("跨日标题", "2026-02-26 00:00:00", "6561543"))
    return records


# ---------------------------------------------------------------- 转义

@pytest.mark.parametrize("title", SPECIAL_TITLES)
def test_escape_roundtrip(title):
    assert fmt.unescape_title(fmt.escape_title(title)) == title


def test_escape_backslash_not_double_decoded():
    assert fmt.escape_title("\\n") == "\\\\n"
    assert fmt.unescape_title("\\\\n") == "\\n"


def test_escape_newline_becomes_literal():
    assert fmt.escape_title("a\nb") == "a\\nb"
    assert "\n" not in fmt.escape_title("a\nb")


# ------------------------------------------------------- 渲染 / 解析

def test_render_parse_roundtrip_preserves_ordered_records():
    records = make_records()
    text = fmt.render(records, date="2025-03-08")
    doc = fmt.parse(text)
    assert not doc.unparsed
    assert [r.key() for r in doc.records] == [r.key() for r in records]


def test_cross_day_record_keeps_full_date():
    text = fmt.render(make_records(), date="2025-03-08")
    assert "- 2026-02-26 00:00:00 6561543" in text
    assert "- 00:19:29 7974352" in text


def test_titles_grouped_and_first_seen_order():
    records = [
        fmt.Record("乙", "01:00:00", "2"),
        fmt.Record("甲", "02:00:00", "1"),
        fmt.Record("乙", "03:00:00", "3"),
    ]
    text = fmt.render(records, date="2025-03-08")
    assert text.index("## 乙") < text.index("## 甲")
    doc = fmt.parse(text)
    assert [r.key() for r in doc.records] == [
        ("乙", "01:00:00", "2"),
        ("乙", "03:00:00", "3"),
        ("甲", "02:00:00", "1"),
    ]


def test_front_matter_values_quoted():
    text = fmt.render([fmt.Record("甲", "01:00:00", "1")], date="2025-03-08")
    assert 'date: "2025-03-08"' in text
    assert 'timezone: "+08:00"' in text
    doc = fmt.parse(text)
    assert doc.meta["date"] == "2025-03-08"
    assert doc.meta["timezone"] == "+08:00"
    assert doc.meta["schema"] == "1"


def test_front_matter_counts():
    doc = fmt.parse(fmt.render(make_records(), date="2025-03-08"))
    assert int(doc.meta["records"]) == len(doc.records)
    assert int(doc.meta["titles"]) == len({r.title for r in doc.records})
    assert int(doc.meta["snapshots"]) == len({r.time for r in doc.records})


def test_empty_title_skipped():
    records = [fmt.Record("", "01:00:00", "1"), fmt.Record("甲", "01:00:00", "2")]
    text = fmt.render(records, date="2025-03-08")
    doc = fmt.parse(text)
    assert [r.key() for r in doc.records] == [("甲", "01:00:00", "2")]
    assert "## \n" not in text


def test_render_is_deterministic():
    records = make_records()
    assert fmt.render(records, date="2025-03-08") == fmt.render(records, date="2025-03-08")


def test_unparsed_lines_are_kept_not_dropped():
    text = fmt.render([fmt.Record("甲", "01:00:00", "1")], date="2025-03-08")
    text += "\n## 乙\n\n- 乱码行\n- 01:00:00 5\n"
    doc = fmt.parse(text)
    assert len(doc.unparsed) == 1
    assert doc.unparsed[0][1] == "- 乱码行"
    assert ("乙", "01:00:00", "5") in [r.key() for r in doc.records]


def test_missing_front_matter_falls_back_to_filename(tmp_path):
    path = tmp_path / "20250308 百度实时热点.md"
    path.write_text("## 甲\n\n- 01:00:00 1\n", encoding="utf-8")
    doc = fmt.load_md(path)
    assert doc.date == "2025-03-08"


# ------------------------------------------------------- v0 兼容

def test_legacy_count_key_and_space_separator(tmp_path):
    path = tmp_path / "20201104 实时热点.json"
    path.write_text(
        json.dumps(
            {
                "蚂蚁集团A股H股双双暂缓上市": [
                    {"time": "2020-11-04 09:00:00.123456+08:00", "count": "8800000"},
                    {"time": "2020-11-04 10:00:00.123456+08:00", "count": "8700000"},
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    date, records = fmt.read_legacy_json(path)
    assert date == "2020-11-04"
    assert [r.hot for r in records] == ["8800000", "8700000"]
    assert [r.time for r in records] == ["09:00:00", "10:00:00"]

    text = fmt.render(records, date=date)
    assert "- 09:00:00 8800000" in text
    doc = fmt.parse(text)
    assert [r.key() for r in doc.records] == [r.key() for r in records]


def test_legacy_hot_index_and_T_separator(tmp_path):
    path = tmp_path / "20260705 百度实时热点.json"
    path.write_text(
        json.dumps(
            {"不到50元的“次抛衣”热销": [{"time": "2026-07-05T00:00:01.324232+08:00", "hot_index": "6193134"}]},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    _, records = fmt.read_legacy_json(path)
    assert records[0].time == "00:00:01"
    assert records[0].hot == "6193134"


def test_legacy_hot_index_preferred_over_count(tmp_path):
    path = tmp_path / "20250308 百度实时热点.json"
    path.write_text(
        json.dumps({"甲": [{"time": "2025-03-08 01:00:00+08:00", "count": "1", "hot_index": "2"}]}),
        encoding="utf-8",
    )
    _, records = fmt.read_legacy_json(path)
    assert records[0].hot == "2"


# ------------------------------------------------------- 时间

@pytest.mark.parametrize(
    "value,expected",
    [
        ("2025-03-08 00:19:29.152649+08:00", "00:19:29"),
        ("2025-03-08T00:19:29.152649+08:00", "00:19:29"),
        ("2025-03-08 00:19:29+08:00", "00:19:29"),
        ("2026-02-26 00:00:00.383986+08:00", "2026-02-26 00:00:00"),
    ],
)
def test_normalize_time(value, expected):
    assert fmt.normalize_time(value, "2025-03-08") == expected


def test_normalize_time_rejects_garbage():
    with pytest.raises(fmt.FormatError):
        fmt.normalize_time("", "2025-03-08")


def test_format_datetime_converts_to_utc8():
    utc = datetime(2025, 3, 7, 16, 19, 29, tzinfo=timezone.utc)
    assert fmt.format_datetime(utc, "2025-03-08") == "00:19:29"


def test_file_date_from_name():
    assert fmt.file_date_from_name("2020/20201104 实时热点.json") == "2020-11-04"
    with pytest.raises(fmt.FormatError):
        fmt.file_date_from_name("no-date.json")


# ------------------------------------------------------- 原子写

def test_atomic_write_replaces_and_leaves_no_temp(tmp_path):
    target = tmp_path / "20250308 百度实时热点.md"
    fmt.atomic_write_text(target, "v1")
    fmt.atomic_write_text(target, "v2")
    assert target.read_text(encoding="utf-8") == "v2"
    assert sorted(p.name for p in tmp_path.iterdir()) == [target.name]
