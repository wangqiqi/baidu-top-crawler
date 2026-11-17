# Harness × IDE 对照（SPIKE-003 摘要）

完整表与风险见 `.growing/archive/meta/SPIKE-003-ide-adaptor-matrix.md`。

| 环境 | 安装根 | Adaptor 厚度 | 文档入口 |
|------|--------|--------------|----------|
| Cursor | `.cursor/` | 厚（hooks · Cloud · Bugbot） | https://cursor.com/docs |
| DeepSeek `.dsh` | （用户级，无项目内安装） | guide-only（用户级 `~/.dsh` + `~/.agents`） | [adaptors/dsh/docs/layout.md](../../adaptors/dsh/docs/layout.md) |
| Kiro | `.kiro/` | rules export（`core_rules_export`） | [adaptors/kiro/docs/layout.md](../../adaptors/kiro/docs/layout.md) |
| Trae | `.trae/` | rules + skills export（`core_rules_export` · `core_skills_export`） | [adaptors/trae/docs/layout.md](../../adaptors/trae/docs/layout.md) |
| OpenCode | `AGENTS.md` + `opencode.json` | 官方机制（无 `.opencode/` 目录） | [adaptors/opencode/docs/layout.md](../../adaptors/opencode/docs/layout.md) |
| VS Code 系 | `AGENTS.md` 等 | 薄 | https://code.visualstudio.com/docs/copilot |

映射草案：`config/install-map.example.json`。非 Cursor adaptor 机器验收 → [adaptor-contract.md](adaptor-contract.md)（`bash .cursor/bin/verify-adaptor-contract.sh`）。

**布局文档状态**（SPIKE-ADAPTOR-LAYOUT）：各 id 均有 `adaptors/<id>/docs/layout.md`；其中 **opencode 已按官方机制重做**（AGENTS.md + opencode.json）、**dsh 降级为配置指引**（用户级 harness，无项目内安装）；安装行为以各 `install-adaptor-*.sh` + layout 为准。差距表 → `.growing/archive/harness/20261026_SPIKE_adaptor-layout.md`。
