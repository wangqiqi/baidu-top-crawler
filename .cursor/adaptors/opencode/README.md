<!-- adaptor-contract:v1 -->

# adaptor: opencode

OpenCode · 生成 `AGENTS.md` + `opencode.json`（官方机制）。

## Status

**implemented（AGENTS.md + opencode.json）** — 官方 OpenCode 项目规则走根目录 `AGENTS.md`、配置走 `opencode.json`（`instructions` 引用 `.cursor/rules/*.mdc`），**无 `.opencode/` 目录**。本 adaptor 生成这两个文件，符合官方机制。详见 [docs/layout.md](docs/layout.md)。

## Identity

`adaptor id`: **opencode**

## Install map

与 `install-map.example.json` → `adaptors.opencode`：

| 字段 | 值 |
|------|-----|
| `install_dir` | **null**（无目录安装，生成根文件） |
| `growth_dir` | `.growing` |
| `hooks_manifest` | **null** |

## Includes

- `core_rules_export` — 生成 `opencode.json` 的 `instructions` 引用 `.cursor/rules/*.mdc`；见 [adaptor-contract.md](../../harness/core/docs/reference/adaptor-contract.md)。

## Install

```bash
bash .cursor/harness/core/bin/install-adaptor-opencode.sh /path/to/project
install-super-cursor /path/to/project --adaptor opencode
```

布局 SSOT → [docs/layout.md](docs/layout.md) · 验收 `bash .cursor/bin/verify-install-opencode.sh`。

## Next sprint

按需扩展 `opencode.json` 的 `instructions`（如引用 remote URL、追加自定义指令文件）；如需 skills，OpenCode 走 `~/.config/opencode/` 用户级（另开 Sprint）。

