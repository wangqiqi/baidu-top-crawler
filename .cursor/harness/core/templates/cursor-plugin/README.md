# Super Cursor MVP (Cursor Plugin)

> **母版维护**：本目录内容由 `bash .cursor/harness/core/bin/sync-plugin-subset.sh` 从 harness 模板与 `.cursor/` 子集生成；**勿手改**生成树（`rules/` · `skills/` 等）。改 manifest / 门面文案请编辑 `.cursor/harness/core/templates/cursor-plugin/`，再跑 sync。

**不是**完整 Super Cursor 安装。全量 rules · 28 skills · `config/` · Growth · verify → 目标仓库先跑 [`install-super-cursor.sh`](../install-super-cursor.sh)（或母版文档中的 dropin 轨）。

## 这是什么

| 含 | 不含 |
|----|------|
| 5 lifecycle skills：`master` · `plan` · `run` · `learn` · `scaffold` | 其余 23+ skills（`git` · `debug` · `test` …） |
| Agents：`ship` · `review` · `spike` | 完整 `runner.sh` / `gate-check` 工具链 |
| 11 条核心 rules（constitution · workflow · verify …） | 全量 `rules/tech` 等 |
| 会话 hooks（`growth-init` · `run-start` · `run-stop`） | 打包的 `config/workflow.json` |
| bundled `templates/project-onekey/` | `commands/`（slash 直挂 skill） |

## 推荐安装顺序

1. **先**在目标项目安装 Super Cursor（`.cursor/config/` · hooks · 全量或 `core` skills bundle）。
2. **再**启用本 Plugin（Marketplace / 本地加载 / 母版 `.cursor-plugin/` 子集）。

仅加载 Plugin、无 `.cursor/config/workflow.json` 时：hooks 无法读取 workflow 与 Growth 开关，plan 闸门与 persona 合并不完整。

### 三轨对照（勿混用）

| 轨 | Skills（约） | `config/` |
|----|--------------|-----------|
| **install full** | 28 | ✅ |
| **install `--skills-bundle core`** | 23 | ✅ |
| **本 Plugin** | 5 lifecycle + agents | ❌（依赖先 install） |

## 本地测试（上架前）

官方发现路径要求 manifest 在 **`.cursor-plugin/plugin.json`**，且 `rules/` · `skills/` 与其**同级**（非 monorepo 内嵌目录）。母版仓内日常校验用平铺的 `.cursor-plugin/`；提交 Marketplace 前请生成官方布局：

```bash
bash .cursor/harness/core/bin/sync-plugin-subset.sh
bash .cursor/harness/core/bin/pack-plugin-marketplace.sh
bash .cursor/harness/core/bin/verify-plugin-marketplace-pack.sh
```

将 `dist/cursor-plugin-marketplace/super-cursor-mvp/` 拷到 `~/.cursor/plugins/local/super-cursor-mvp/`（保留其内 `.cursor-plugin/plugin.json` 与根级 `rules/`），Reload Window，在 Customize 中确认 rules · skills · agents · hooks。

**Hooks 需要 Bash**（Git Bash · WSL · macOS/Linux 终端）。Windows 纯 PowerShell 未测 PATH 下 bash。

## 安全与隐私

- Hooks 仅在仓库内读写 `.growing/` · 读 `.cursor/config/workflow.json`；**不**收集密钥、不发起外呼网络（无 MCP）。
- 脚本为人可审的 shell；安装前请扫一眼 `hooks/*.sh`。

## Marketplace

**状态：Prep（可打包提交）** — 实际上架仍经 [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish) 人工审核；**不**重复提交同一仓库。

| 项 | 说明 |
|----|------|
| 提交布局 | `dist/cursor-plugin-marketplace/`（见 `pack-plugin-marketplace.sh`） |
| 母版 monorepo | 可选根级 `.cursor-plugin/marketplace.json`（模板在 harness `templates/cursor-plugin/`） |
| 清单归档 | Growth `archive/meta/*_SPIKE_marketplace_prep_scope.md` |
| 门禁 | `verify-spike-marketplace-prep-scope` · `verify-plugin-marketplace-pack` · `verify-cursor-plugin-mvp` |

```bash
bash .cursor/bin/verify-spike-marketplace-prep-scope.sh   # 母版：归档回归
```

## 母版验证

```bash
bash .cursor/bin/sync-plugin-subset.sh
bash .cursor/adaptors/cursor/bin/verify-cursor-plugin-manifest.sh
bash .cursor/adaptors/cursor/bin/verify-cursor-plugin-mvp.sh
```

范围矩阵 → Growth `*_SPIKE_plugin_mvp_scope.md` · `*_SPIKE_plugin_phase2_scope.md`。
