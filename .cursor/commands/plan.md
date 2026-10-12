---
description: 【生命周期】先总后分：Goal · Done when → 拆 Sprint → plan.md
---

加载 skill **plan**：

1. **阶段 1** — `PLANNING:true`，写 **Goal** · **Done when**；用 AskQuestion 收集 Sprint 范围
2. **阶段 2** — 拆 TASK + 验收列；写 `.cursorGrowth/plan.md`
3. **阶段 3** — 设 `PLANNING:false` · `PLAN_APPROVED` · `ACTIVE`/`NEXT`，跑 `gate-check`

`plan.md` 模板在 `.cursor/templates/plan.md`；`gate-check` ≠ OK 不写业务代码。
