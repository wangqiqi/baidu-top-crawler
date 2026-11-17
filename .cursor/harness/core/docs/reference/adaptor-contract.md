# Adaptor 最小契约（v1）

非 Cursor IDE 的 adaptor 在实现安装/导出前，须满足本契约，使 `install-map.example.json` 与仓库目录可机器验收。

**对照**：Harness × IDE 摘要 → [harness-ide-matrix.md](harness-ide-matrix.md)（完整 SPIKE 表在本地 `.growing/archive/meta/`）。

**v1 载体**：各 adaptor 的 `README.md` 章节 + `config/install-map.example.json` 字段；**不**要求 `adaptor.json`。

## 适用范围

| 类型 | adaptor id | 本契约 |
|------|------------|--------|
| 已实现（项目内可安装） | `kiro` · `trae` · `opencode` · `zcode` · `workbuddy` | **必须**（字段 + 章节机器校验） |
| 指引型（无项目内安装） | `dsh` | 不适用（用户级 harness，见 `adaptors/dsh/README.md`） |
| 已实现 | `cursor` | 另有 hooks · plugin verify；本契约仅作字段对照 |

> 注意：`verify-adaptor-contract.sh` 目前仅校验 README 章节结构与 install-map 字段一致，**不校验**与各家官方规范的实际符合度。官方规范符合度见 [harness-ide-matrix.md](harness-ide-matrix.md) 及各 `adaptors/*/docs/layout.md` §官方对照。

## 目录布局

母版 SSOT：

```text
.cursor/adaptors/<adaptor id>/README.md
```

`verify-harness-layout.sh` 已要求上述 adaptor id 均存在 `README.md`；内容须符合下文。

## README 必备章节（机器检查）

每个 adaptor 的 `README.md` 须包含以下 **二级标题**（顺序不限），且文首 HTML 注释含 `adaptor-contract:v1`：

| 章节 | 内容要求 |
|------|----------|
| `## Status` | 写明当前对齐状态：**implemented** / **misaligned**；官方 layout 待确认或已错位时直说 |
| `## Identity` | 一行 `adaptor id`: **&lt;id&gt;**（与目录名一致） |
| `## Install map` | 与 `install-map.example.json` 一致：`install_dir` · `growth_dir` · `hooks_manifest`（可为 `null`） |
| `## Includes` | 列出 `includes` 数组；说明各 token 语义（见下） |
| `## Next sprint` | 指向后续实现 Sprint ID（可多个候选，须可 grep） |

## `install-map.example.json` 字段映射

路径：`.cursor/harness/core/config/install-map.example.json` → `adaptors.<id>`。

| 字段 | 含义 |
|------|------|
| `install_dir` | 安装到目标项目时的根目录（如 `.kiro`）；生成根目录文件的 adaptor（opencode）为 `null` |
| `growth_dir` | Growth 坐标（通常 `.growing`） |
| `includes` | 从 Harness Core 打入的包片段（**v1 仅文档化**，install 脚本未实现多 adaptor） |
| `hooks_manifest` | 生命周期 hooks 清单路径；无则 JSON `null`，README 写 `hooks_manifest`: **null** |

### `includes` token（v1 枚举）

以 `install-map.example.json` 为准，不得擅自新增键而不改 map：

| Token | 意图 |
|-------|------|
| `core` | Harness Core 主体（skills · rules · bin · config 等） |
| `core_rules_export` | 面向 Kiro/Trae 的 rules 导出 → [core-rules-export.md](core-rules-export.md) |
| `core_skills_export` | 面向 Trae 的 skills 导出（`.trae/skills/<id>/SKILL.md`）→ [adaptors/trae/docs/layout.md](../../adaptors/trae/docs/layout.md) |
| `cursor_hooks` | Cursor 专用（仅 `cursor` adaptor） |
| `cursor_plugin_verify` | Cursor Plugin 冒烟（仅 `cursor` adaptor） |

## adaptor 对照表（与 install-map 同步）

| id | install_dir | includes | hooks_manifest |
|----|-------------|----------|----------------|
| `kiro` | `.kiro`（rules → `.kiro/steering/*.md`） | `core_rules_export` | （map 未列则 README 写 **未定义**） |
| `trae` | `.trae`（rules → `.trae/rules/*.md` · skills → `.trae/skills/`） | `core_rules_export` · `core_skills_export` | （同上） |
| `opencode` | `null`（项目根 `AGENTS.md` + `opencode.json`） | `core_rules_export` | （同上） |

## 验收

```bash
bash .cursor/bin/verify-adaptor-contract.sh
```

母版聚合：`verify-super-cursor.sh` · `template-verify.sh`。

## 变更纪律

- 改 `install_dir` / `includes` → 同步 **install-map** · 各份 README · 本表
- 新增 adaptor id → 新建 `adaptors/<id>/` · map 条目 · 扩展 `verify-adaptor-contract.sh` 的 adaptor 列表
