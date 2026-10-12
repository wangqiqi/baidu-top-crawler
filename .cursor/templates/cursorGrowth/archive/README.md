# archive/ — 产出归档（域分层）

**规则**：新产出一律落 **一级域目录**，不得长期堆在 `archive/` 根。
根目录 flat 文件数由 `runner.sh archive-check` 把关（阈值 `workflow.json` → `growth.archive_flat_max`，默认 5）。

| 域 | 放什么 |
|----|--------|
| `sprint/` | Sprint 闭合摘要 · TASK 汇总 |
| `spike/` | SPIKE 结论 · 调研 ADR |
| `release/` | 发版笔记 · tag 说明 |
| `doc/` | 文档 / SOP / skill-rule 收敛 |
| `ops/` | 运维 · 数据 · 迁移 · 工具脚本记录 |

命名：`<YYYYMMDD>_<HHMMSS>_<topic>_<module>.md`
域表可按项目扩展 → 登记在 `learn/plan-conventions.md`（团队增量），完整规则见
`.cursor/skills/plan/reference/growth-layout.md`。
