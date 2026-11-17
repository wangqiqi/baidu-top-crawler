<!-- adaptor-contract:v1 -->

# adaptor: kiro

Kiro 项目规则 · `core_rules_export`。

## Status

**implemented（steering export）** — 官方 Kiro 项目规则走 `.kiro/steering/*.md`（`inclusion` frontmatter）；本 adaptor 导出 [docs/layout.md](docs/layout.md) · SSOT [core-rules-export.md](../../harness/core/docs/reference/core-rules-export.md)。

## Identity

`adaptor id`: **kiro**

## Install map

与 `install-map.example.json` → `adaptors.kiro`：

| 字段 | 值 |
|------|-----|
| `install_dir` | `.kiro` |
| `growth_dir` | `.growing` |
| `hooks_manifest` | **null** |

## Includes

- `core_rules_export` — `harness/core/rules` 子集 + `RULES.md` 索引；见 [adaptor-contract.md](../../harness/core/docs/reference/adaptor-contract.md)。

## Install

```bash
bash .cursor/harness/core/bin/install-adaptor-rules-export.sh --adaptor kiro /path/to/project
install-super-cursor /path/to/project --adaptor kiro
```

验收：`bash .cursor/bin/verify-install-rules-export.sh`。

## Next sprint

导出 `.kiro/agents/`（按 Kiro agent schema：`prompt`/`tools`/`permissions`/`resources`）与 `.kiro/skills/`；当前仅 steering 规则（另开 Sprint）。
