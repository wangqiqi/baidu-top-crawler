# Changelog

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)，变更记录格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [1.0.0] - 2026-10-12

数据格式冻结为 v1，采集链路可靠性重建完成。

### ⚠️ 破坏性变更

- **数据存储格式由 v0 JSON 分组改为 v1 紧凑 Markdown 分节**（规范见 [docs/data-format.md](docs/data-format.md)）：
  - 2163 个数据文件由 `20NN/NNNNNNNN [百度]实时热点.json` 变为 `20NN/NNNNNNNN 百度实时热点.md`
  - 行内时间精度由微秒降为秒（`HH:MM:SS`，UTC+8）；跨日记录写完整 `YYYY-MM-DD HH:MM:SS`
  - 旧字段 `count` 归一为热度位；`T` 与空格两种时间分隔符统一为空格
  - 标题含 `\` 与换行时按规范转义，其余字符（`#` `|` `*` 等）原样保留
- **仓库历史已重写**：提交数 46,626 → 32，所有既有 clone/fork 失效

### Added

- `baidutop/format.py` — 格式层：渲染 / 解析 / 转义 / round-trip 校验 / v0 JSON 兼容读取
- `baidutop/store.py` — 存储层：`fcntl` 排他锁 + 临时文件原子替换 + 幂等追加 + 坏文件 `.corrupt` 自愈
- `baidutop/http.py` — 传输层：指数退避重试（超时 / 连接错误 / 408·425·429·5xx）、`Retry-After`、可注入 session
- `scripts/verify.sh` — 验收入口（`--lint` / `--tests` / `--data` / `--size`）
- `scripts/check_data.py` — 数据完整性检查（迁移前后均可运行，校验 1,850,921 条）
- `scripts/check_size.py` — 体积预算检查（数据 / 工作区 / git pack）
- `scripts/migrate_to_md.py` — 迁移 CLI（`--dry-run` / `--check` / `--delete-json`）
- `docs/data-format.md` — 数据格式规范 v1（SSOT）：转义规则、时间语义、round-trip 契约
- `pyproject.toml` — pytest 与 ruff 配置
- 95 个单测：格式 round-trip、存储并发与自愈、HTTP 重试策略、CI 工作流结构

### Changed

- **数据体积 223.0MB → 53.4MB（-76.6%）**；工作区 229.6MB → 54.7MB；git pack 72.1MB → 23.9MB；
  新克隆 ≈292MB → **82MB**
- 爬虫 CLI 支持 `--root` / `--board` / `--verbose`，退出码反映抓取结果
- 依赖与运行环境：Python ≥3.11，actions/checkout@v4 + actions/setup-python@v5 + pip 缓存
- CI 调度：cron 由每小时改为每天 4 次错峰（`17 1,7,13,19 * * *`），新增 `concurrency` 串行化、
  无变更跳过提交、push 前 `pull --rebase`、job summary 与 `::error::` 失败可见
- README 重写：格式说明、体积对比、验收与迁移用法

### Fixed

| 编号 | 缺陷 |
|---|---|
| D1 | 整文件 read-modify-write 无锁 → 重叠运行丢数据 |
| D2 | `RequestException` 分支直接 `raise` → 5xx 从不重试 |
| D3 | 文件名取开始时刻、记录时间取结束时刻 → 跨日错位（`20260225` / `20260704` 共 102 条） |
| D4 | `RETRY_DELAY` 硬编码、`save_as_json` 混用模块级 `logging` |
| D5 | 无变更时 commit 步骤直接失败；push 前无 rebase |
| D6 | cron `0 * * * *` 被 GitHub 限流饿死（689 次/月 → 4~5 次/天） |
| D7 | `.gitignore` 中 `__pycache__/` 规则被中文顿号破坏 |

### Notes

- **数据无损**：2163 个文件 / 1,850,921 条记录逐条校验一致；唯一有损为微秒位（爬取调度抖动）
- 完整历史归档：`baidu-top-crawler-full-20261012.bundle`（含重写前的 46,626 个提交与已删分支）
- 陈旧远端分支 `trae/solo-agent-GC0Nyf` 已删除（其内容全部包含于 `main`）
- 遗留待办：历史缺失 314 天待补抓；如需真·每小时采集需换自托管调度
