# OpenCode 布局（Super Cursor · 官方机制）

> ✅ **本 adaptor 已按官方机制实现**：OpenCode 用项目根 `AGENTS.md` + `opencode.json`，**无 `.opencode/` 目录**。

## 官方机制（2026-11 核实）

| 项 | 官方 OpenCode |
|----|------|
| 项目规则 | 项目根 `AGENTS.md`（`/init` 生成或手写；会被注入 LLM 上下文） |
| 全局规则 | `~/.config/opencode/AGENTS.md` |
| 配置 | `opencode.json`（`instructions` 数组可引用本地文件或远程 URL） |
| 兼容回退 | `CLAUDE.md`（Claude Code 约定，无 AGENTS.md 时用） |

## 安装产物

| 文件 | 内容 |
|------|------|
| `<目标>/AGENTS.md` | 项目规则（含 Super Cursor 工作流要点） |
| `<目标>/opencode.json` | `instructions` 引用 `.cursor/rules/*.mdc`（core / workflow / communication / execution / feedback） |

**前置**：目标项目已装 `.cursor/`（`instructions` 引用其 `rules`）；未装时本脚本输出 WARN 但仍生成文件。

## 安装

```bash
bash .cursor/harness/core/bin/install-adaptor-opencode.sh /path/to/project
install-super-cursor /path/to/project --adaptor opencode
```

## 验收

`bash .cursor/bin/verify-install-opencode.sh`（断言生成 AGENTS.md + opencode.json，且**不**生成 `.opencode/` 目录）
