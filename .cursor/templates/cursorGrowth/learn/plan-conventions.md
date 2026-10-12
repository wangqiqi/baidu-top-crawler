# Plan & archive conventions（项目特化）

> 由 **`/learn`** 维护 · 供 **plan** · **run** · `runner.sh plan-check` 参考。  
> **勿**写入 `.cursor/rules` 或 skills 正文 — 团队差异只放本文件。

## 域表（archive · scripts · docs 共用）

**一处登记、三处消费**：归档域 · 脚本域（`scripts/verify/domain/`）· 文档主题都以此表为准，避免各写一份。

| 域 | archive/ | scripts/ | docs/ |
|----|----------|----------|-------|
| `sprint` | Sprint 闭合摘要 | — | 验收与发布 |
| `spike` | SPIKE 结论 · ADR | `dev/` | 架构决策 |
| `release` | 发版笔记 | `ops/` | 部署运维 |
| `doc` | 文档/SOP 收敛 | `docs/` | 开发规范 |
| `ops` | 运维 · 数据 · 迁移 | `ops/` | 部署运维 |
| （扩展） | 团队在此追加 | — | — |

母版推荐域全表 → **plan** `reference/growth-layout.md`。

## Archive 命名

| 项 | 本项目 |
|----|--------|
| 目录 | `.cursorGrowth/archive/{domain}/` — **至少一级域目录** |
| 格式 | `YYYYMMDD_HHMMSS_<topic>_<module>.md` |
| 门禁 | `runner.sh archive-check`（根目录 flat 文件 > `growth.archive_flat_max` 即 FAIL） |
| 说明 | `<topic>` / `<module>` 用英文或拼音缩写，避免空格 |

## docs/ 编号与上限

规则正文 → `.cursor/rules/execution/project-docs.mdc` · 配置 → `config/docs-layout.json`（本项目的 `profile` 与启用号位在此登记）。

**规则**：对外持久文档一律 `NN_中文功能.md`；**带序号文档硬上限 10 个**（超限必须合并同类或下沉 Growth）。

| 号 | 用途 | 生成方式 |
|----|------|----------|
| `01`–`06` | 自主分配（产品概述 · 快速开始 · 架构 · 接口契约 · 开发规范 · 部署运维） | 人 / Agent 撰写 |
| **`07_用户手册.md`** | 可发布使用说明书 | **自动生成** — `/manual`（Manual Contract） |
| **`08_测试报告.md`** | 发布测试报告 | **自动生成** — `/report`（Report Contract） |
| `09`–`10` | 预留（验收与发布 · 待定） | 人 / Agent 撰写 |
| `ROADMAP.md` | 长期计划（**例外：不加序号**） | 人 / Agent 维护 |

**序号纪律**：号**不重用**（删除后留空号）· 新增**追加**· 两自动生成文档的号由 `config/manual.yaml` / `config/test-report.yaml` 的 `doc_path` 固定，**不得手写**。

**自动生成标记**（写文件头，供校验与 regenerate）：

```markdown
<!-- generated: manual · regenerate: /manual -->
```

**docs vs Growth 边界**：

| 进 `docs/`（入 git · 对外 · 持久） | 进 `.cursorGrowth/learn/`（gitignore · 本地认知） |
|-------------------------------------|--------------------------------------------------|
| 使用者需要的说明、契约、报告 | 本仓约定、模块地图、发版节奏、踩坑记录 |
| 与版本一起演进 | 换人/换机可重建，不进发布物 |

## Plan 可选段落（若有）

团队在 plan 中使用的**额外**基线段落（差距表、审查笔记等）在此登记；Sprint 收尾须与 `.cursorGrowth/archive/` 对齐：

| 段落类型（团队自定） | 收尾动作 |
|----------------------|----------|
| （待填） | 改 **交付态**，或链 `.cursorGrowth/archive/...` 作历史快照 |

## Sprint 区块标题

`runner.sh plan-check` 在 Sprint 闭合时会 WARN 仍为「进行中」标题的区块：

| 状态 | 标题示例（任选一种语言，团队统一即可） |
|------|----------------------------------------|
| 进行中 | `Active sprint` · `活跃 Sprint` |
| 已闭合 | `Completed sprint` · `已完成 Sprint` |

## 与母版分工

| 层 | 内容 |
|----|------|
| `.cursor/` | 通用机制：`SPRINT_STATUS` · Done when · TASK ✅ · reconciliation 清单 |
| 本文件 | 域表 · 归档命名 · docs 编号与上限 · 可选段落类型 · 标题用语 |

