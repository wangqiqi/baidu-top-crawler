# Kiro `.kiro/` 布局（`core_rules_export`）

> ✅ **已按官方机制对齐**：Kiro 项目规则走 `.kiro/steering/*.md`（Markdown，非 `.mdc`），另有 `.kiro/agents/`、`.kiro/skills/`。

## 官方机制（2026-11 核实）

| 项 | 官方 Kiro |
|----|------|
| 项目规则 | `.kiro/steering/*.md`（frontmatter 用 `inclusion: always\|fileMatch\|manual\|auto`） |
| agent 配置 | `.kiro/agents/*.json\|.md`（`prompt` / `tools` / `permissions` / `resources` / `hooks`） |
| skills | `.kiro/skills/*/SKILL.md` |
| AGENTS.md | 工作区任意位置 `AGENTS.md`（始终加载，作 steering 上下文） |

## 导出产物（本 adaptor）

```text
.kiro/
├── README.md          # adaptors/kiro/README.md
├── RULES.md           # 生成：steering/**/*.md 索引
└── steering/          # harness/core/rules → .md（无 local；原 .mdc 重命名 .md）
```

> 说明：本 adaptor 仅导出 **steering 规则**（`.md`），不导出 `.kiro/agents/`（需按 Kiro agent schema 另写，见 `## Next sprint`）。

## Growth

**`.growing/`** 共享；`rules/local` 在 `.growing/rules/local`。

## 安装

```bash
bash .cursor/harness/core/bin/install-adaptor-rules-export.sh --adaptor kiro /path/to/project
install-super-cursor /path/to/project --adaptor kiro
```

## 验收

`bash .cursor/bin/verify-install-rules-export.sh`（kiro · trae 的 rules 共用；trae skills 另见 `verify-install-skills-export.sh`）。
