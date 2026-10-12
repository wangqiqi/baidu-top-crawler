# 百度热搜爬虫

> 当前版本 **v1.0.0**（数据格式 v1 冻结）· 变更记录见 [CHANGELOG.md](CHANGELOG.md)

定时抓取百度热搜榜单，按 **v1 紧凑 Markdown 分节格式**持久化，带重试、并发安全与完整验收链路。

| 指标 | 数值 |
|---|---|
| 数据文件 | 2163 个（2020-11-04 ~ 2026-10-12） |
| 记录总数 | 1,850,921 条 |
| 数据体积 | **53.4 MB**（同一批数据 v0 JSON 为 228.3 MB，**省 76.6%**） |
| 抓取频率 | GitHub Actions 每天 4 次 |

## 功能特性

- **紧凑 Markdown 存储**：按标题分节，人可读、GitHub 可直接预览、diff 友好；比 v0 JSON 省约 77%
- **并发安全**：`fcntl` 排他锁 + 临时文件原子替换，重叠运行不再互相覆盖
- **健壮重试**：超时 / 连接错误 / 5xx（408·425·429·500·502·503·504）指数退避，尊重 `Retry-After`；4xx 立即失败
- **幂等追加**：`(title, time, hot)` 三元组去重，重复执行不产生重复行
- **坏文件自愈**：解析失败或存在非法行时先备份 `.corrupt` 再重建，不静默清空
- **v0 兼容**：能读旧 JSON 分组格式（含 `count` 字段、`T`/空格两种时间分隔符）
- **可验收**：pytest + ruff + 数据完整性 + 体积预算，一条命令跑全

## 安装

```bash
pip install -r requirements.txt
```

开发环境（含 pytest / ruff / pyyaml）：

```bash
pip install -e ".[dev]"
```

## 使用方法

```bash
python crawl_baidu_top.py                 # 抓取并追加写入当日文件
python crawl_baidu_top.py --verbose       # 输出 DEBUG 日志
python crawl_baidu_top.py --root /path    # 指定数据仓库根目录
python crawl_baidu_top.py --board realtime
```

程序会写入 `YYYY/YYYYMMDD 百度实时热点.md`；同日多次抓取自动追加，重复观测自动跳过。

输出示例：

```
2026-10-12 17:51:48 - INFO - 开始爬取百度realtime榜单...
2026-10-12 17:51:49 - INFO - 成功爬取 51 条热搜数据
2026-10-12 17:51:49 - INFO - 成功写入 51 条记录到: 2026/20261012 百度实时热点.md（跳过重复 0 条，累计 204 条）
```

## 数据格式

```markdown
---
schema: 1
date: "2025-03-08"
timezone: "+08:00"
board: realtime
source: "https://top.baidu.com/board?tab=realtime"
snapshots: 24
titles: 430
records: 1224
generated: "2026-10-12T17:51:48+08:00"
---

## 始终保持弄潮儿的角色

- 00:19:29 7974352
- 01:13:56 7956248
```

- 行内时间精度为秒（`HH:MM:SS`，UTC+8）；跨日记录写完整 `YYYY-MM-DD HH:MM:SS`
- 标题按首次出现顺序分节；`#`、`|`、`*` 等字符原样保留，无需转义
- 权威定义、转义规则与 round-trip 契约见 **[docs/data-format.md](docs/data-format.md)**

### 为什么不是每行带标题的表格

全量真数据实测（2163 个文件 / 1,850,921 条）：

| 方案 | 体积 | 占 v0 |
|---|---|---|
| v0 JSON（`indent=4`） | 228.3 MB | 100% |
| 紧凑 JSON | ≈63 MB | 38% |
| **MD 分节（本仓采用）** | **53.4 MB** | **23.4%** |
| MD 单表（每行带标题） | 115 MB | 50% |
| TSV（每行带标题） | 101 MB | 44% |

每行重复标题的表格格式只能省一半，所以本仓坚持「按标题分节」。

## 配置

| 参数 | 默认值 | 说明 |
|---|---|---|
| `timeout` | 10 | 请求超时（秒） |
| `max_retries` | 3 | 最大重试次数 |
| `retry_delay` | 2 | 退避基础间隔（秒），指数增长，上限 30 秒 |

```python
crawler = BaiduHotSearchCrawler(timeout=15, max_retries=5, retry_delay=1)
```

## 验收与开发

```bash
./scripts/verify.sh              # lint + 单测 + 数据完整性 + 体积报告
./scripts/verify.sh --lint       # ruff
./scripts/verify.sh --tests      # pytest
./scripts/verify.sh --data       # 数据完整性（记录数、front matter、非法行）
./scripts/verify.sh --size       # 体积预算硬校验
```

## 数据迁移（v0 JSON → v1 Markdown）

```bash
python scripts/migrate_to_md.py --dry-run        # 只报告体积与一致性，不落盘
python scripts/migrate_to_md.py                  # 写出 .md（保留 .json 作为对照）
python scripts/migrate_to_md.py --check          # 校验已落盘 .md 与源 JSON 一致
python scripts/migrate_to_md.py --delete-json    # 逐条校验通过后删除源 JSON
```

迁移保证 `(title, time, hot)` 有序多重集完全一致，唯一有损是微秒位（爬取调度抖动）。

## 项目结构

```
├── crawl_baidu_top.py         # 爬虫入口（抓取 + 落盘）
├── baidutop/
│   ├── format.py              # v1 格式：渲染 / 解析 / 转义 / v0 兼容读取
│   ├── store.py               # 存储：文件锁 + 原子写 + 幂等追加 + 坏文件自愈
│   └── http.py                # HTTP：退避重试策略
├── scripts/
│   ├── verify.sh              # 验收入口
│   ├── check_data.py          # 数据完整性检查
│   ├── check_size.py          # 体积预算
│   └── migrate_to_md.py       # v0 → v1 迁移 CLI
├── tests/                     # 95 个单测
├── docs/data-format.md        # 格式规范 v1（SSOT）
└── 2026/20261012 百度实时热点.md
```

## 定时任务

`.github/workflows/schedule.yml`：

- cron `17 1,7,13,19 * * *`（UTC）＝ 北京时间 09:17 / 15:17 / 21:17 / 03:17，错开整点以缓解 GitHub 免费 runner 的定时限流
- `concurrency` 串行化，杜绝并发覆盖
- 抓取 → 数据校验 → 提交推送；无变更跳过提交，push 前 `pull --rebase`
- 失败时输出 `::error::` 注解与 job summary

## 参考项目

- <https://github.com/quarrying/baidu-top-crawler>
- <https://github.com/bonfy/github-trending>
- <https://github.com/JPAdCoder/BaiduTopic-python>
