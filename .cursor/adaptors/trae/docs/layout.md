# Trae `.trae/` 布局（`core_rules_export` · `core_skills_export`）

> ✅ **已按官方机制对齐**：Trae 项目规则走 `.trae/rules/*.md`，项目技能走 `.trae/skills/<id>/SKILL.md`。

## 官方机制（2026-11 核实）

| 项 | 官方 Trae |
|----|-----------|
| 项目规则 | `.trae/rules/`（Markdown，frontmatter 用 `description` / `alwaysApply` / `globs`） |
| 项目技能 | `.trae/skills/<skill-id>/SKILL.md`（YAML frontmatter：`name` / `description`） |
| 全局规则 | `~/.trae-cn/user_rules`（Windows `%userprofile%/.trae-cn/user_rules`） |
| AGENTS.md | 项目根 `AGENTS.md`（兼容，跨 IDE 复用） |

## 导出产物（本 adaptor）

```text
.trae/
├── README.md          # adaptors/trae/README.md
├── RULES.md           # 生成：rules/**/*.md 索引
├── rules/             # harness/core/rules → .md（无 local；原 .mdc 重命名 .md）
└── skills/            # harness/core/skills/<id>/ → 含 SKILL.md · reference/ · scripts/
```

## Skills

| 项 | 值 |
|----|-----|
| 源 | `harness/core/skills/<id>/`（母版全量 28） |
| 目标 | `.trae/skills/<id>/` |
| 子集 | `--skills-bundle core` → 23（去掉 `week` · `disk` · `maintain` · `ops-deploy` · `code-stats-viz`） |
| 覆盖策略 | 增量复制；**不删除**消费方自有 skill（项目私有 skill 与母版同名时以母版为准） |
| 与 Cursor 一致性 | **逐字节复制**：不改写 frontmatter（保留 `disable-model-invocation`）、不改写正文 `.cursor/…` 路径、不增删 `reference/` · `scripts/`。语义、触发条件、引用锚点与 Cursor 内完全一致 |
| frontmatter | 原样保留 `name` / `description` / `disable-model-invocation`；Trae 按 `disable-model-invocation` 隐藏手动 skill（`/plan` 等仅显式调用，与 Cursor 同语义） |
| 正文路径 | skill 内 `.cursor/...` 引用按消费方 `.cursor/` 解析（`install-super-cursor` 同时安装 `.cursor/`，无需改写） |

## Growth

**`.growing/`** 共享；`rules/local` → `.growing/rules/local`。

## 安装

```bash
bash .cursor/harness/core/bin/install-adaptor-rules-export.sh --adaptor trae /path/to/project
bash .cursor/harness/core/bin/install-adaptor-skills-export.sh --adaptor trae /path/to/project
install-super-cursor /path/to/project --adaptor trae
```

## 验收

`bash .cursor/bin/verify-install-rules-export.sh` · `bash .cursor/bin/verify-install-skills-export.sh`。
