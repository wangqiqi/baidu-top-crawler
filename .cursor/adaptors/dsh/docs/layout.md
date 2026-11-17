# DeepSeek Harness（dsh）· 用户级配置指引

> ⚠️ **本 adaptor 无项目内安装**。官方 dsh 是用户级 harness，配置不在项目内。

## 官方对照（2026-11 核实）

| 项 | 官方 DeepSeek Harness（dsh） |
|----|------|
| 配置根 | **用户级** `~/.dsh`（`$DSH_HOME`，含 `profiles/` · `cordis.patch.yml` · `.credentials.yaml`） |
| 全局指令 | `~/.agents/AGENTS.md`（`$DSH_AGENTS_HOME`，默认 `~/.agents`） |
| skills | `~/.agents/skills/`（用户级扫描） |
| 架构 | everything-is-a-plugin（Cordis）；Developer Preview，允许 breaking changes |

结论：dsh 是「用户级 harness」，不是「项目内目录」范式。Super Cursor 作为项目级模板**无法替用户写用户级目录**，故只提供以下配置指引。

## 用户级配置指引

```bash
# 1. 全局规则（所有项目生效）
mkdir -p ~/.agents
#   编辑 ~/.agents/AGENTS.md，写入你的全局指令

# 2. 技能（dsh 扫描此目录）
#   将想共享的技能放入 ~/.agents/skills/<name>/SKILL.md
#   可参考 Super Cursor 的 harness/core/skills/ 结构（frontmatter 需按 dsh 约定调整）

# 3. harness 配置（模型 · provider · 权限）
#   dsh 配置在 $DSH_HOME（默认 ~/.dsh），通过 dsh web 的 Settings 或手写 profiles
```

## 与 Super Cursor 的关系

- Super Cursor 的规则 / 技能方法论可**参考**，但需按 dsh 的 plugin / skills schema 重写后放入 `~/.agents/skills/`。
- 项目内 `.growing/` 与 dsh 无直接关联；dsh 的会话/配置状态在用户级 `~/.dsh`。
