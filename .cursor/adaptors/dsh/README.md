<!-- adaptor-contract:v1 -->

# adaptor: dsh

DeepSeek Harness（dsh）· 用户级配置指引。

## Status

**guide-only（无项目内安装）** — 官方 dsh 是**用户级 harness**：配置在 `~/.dsh`（`$DSH_HOME`），全局指令在 `~/.agents/AGENTS.md`、skills 在 `~/.agents/skills/`，**不在项目内**；且为 Developer Preview（允许 breaking changes）。Super Cursor 作为项目级模板无法替用户写用户级目录，故本 adaptor 只提供配置指引，不再提供项目内安装脚本。详见 [docs/layout.md](docs/layout.md)。

## Identity

`adaptor id`: **dsh**

## Install map

与 `install-map.example.json` → `adaptors.dsh`：

| 字段 | 值 |
|------|-----|
| `install_dir` | （无项目内安装） |
| `growth_dir` | `.growing` |
| `hooks_manifest` | **null** |

## Includes

- `core` — 仅供参考；dsh 官方用 `~/.agents/skills/` 加载技能，不读项目内 `.dsh/`。

## Install

无项目内安装。用户级配置指引见 [docs/layout.md](docs/layout.md)：

```bash
# 全局指令与 skills（用户级，非项目内）
#   ~/.agents/AGENTS.md        全局规则
#   ~/.agents/skills/          技能（dsh 扫描此目录）
#   ~/.dsh/profiles/*/         harness 配置（$DSH_HOME）
```

## Next sprint

dsh 官方转为项目内可安装机制后：新增 install 脚本并接入 `install-super-cursor.sh --adaptor dsh`（另开 Sprint）。
