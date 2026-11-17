<!-- adaptor-contract:v1 -->

# adaptor: trae

Trae 项目规则与技能 · `core_rules_export` + `core_skills_export`。

## Status

**implemented（rules + skills export）** — 官方 Trae 项目规则走 `.trae/rules/*.md`，项目技能走 `.trae/skills/<id>/SKILL.md`；本 adaptor 导出 [docs/layout.md](docs/layout.md) · rules SSOT [core-rules-export.md](../../harness/core/docs/reference/core-rules-export.md)。

## Identity

`adaptor id`: **trae**

## Install map

与 `install-map.example.json` → `adaptors.trae`：

| 字段 | 值 |
|------|-----|
| `install_dir` | `.trae` |
| `growth_dir` | `.growing` |
| `hooks_manifest` | **null** |

## Includes

- `core_rules_export` — `harness/core/rules` → `.trae/rules/` + `RULES.md` 索引；见 [adaptor-contract.md](../../harness/core/docs/reference/adaptor-contract.md)。
- `core_skills_export` — `harness/core/skills` → `.trae/skills/`（full=28 · core=23；逐字节复制，不改写 frontmatter/路径；不删除消费方自有 skill）；见 [docs/layout.md §Skills](docs/layout.md)。

## Install

```bash
bash .cursor/harness/core/bin/install-adaptor-rules-export.sh --adaptor trae /path/to/project
bash .cursor/harness/core/bin/install-adaptor-skills-export.sh --adaptor trae /path/to/project
install-super-cursor /path/to/project --adaptor trae
```

验收：`bash .cursor/bin/verify-install-rules-export.sh` · `bash .cursor/bin/verify-install-skills-export.sh`。

## Next sprint

规则 frontmatter（`description` / `alwaysApply` / `globs`）已与 Trae 官方键对齐；后续按官方机制变更复核 `.trae/rules/` 与 `.trae/skills/` 的加载行为（另开 Sprint）。
