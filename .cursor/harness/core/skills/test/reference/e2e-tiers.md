# E2E 与视觉回归档位（通用）

真源：**verify.mdc** L0–L3。本页只描述 **Playwright/Cypress 类** 套件如何分档，避免全部塞进 merge 前 fast 路径。

## 三档

| 档位 | 依赖 | 默认 CI / merge | 默认 release / nightly |
|------|------|-----------------|------------------------|
| **Mock / stub API** | 前端 + 路由 mock · 无真实后端 | ✅ 可进 L2-core | ✅ |
| **Real-stack** | 真实 API + DB/种子 · 固定测试账号 | ❌ 不进 fast | ✅ 专用 job 或 `verify-e2e-real.sh` |
| **Visual baseline** | 截图 diff · 字体/渲染敏感 | ❌ 不进 fast | ✅ 固定 runner 镜像 · `--update` 文档化 |

## 契约（项目写入 Growth `learn/`）

- **命名前缀** · **janitor**（afterAll 清数据）· **单 worker**（real-stack 避免竞态）
- 真实栈 spec **禁止**与 mock 套件混在同一 project 默认同跑（隔离 `playwright.config` project）

## 与 manifest / plan

| plan 验收列 | 档位 |
|-------------|------|
| 单 spec + `--project=mock` | Mock |
| `manual: 本地起 backend` | Real-stack |
| `verify-visual-baseline.sh` | Visual |

Sprint `<!-- VERIFY: ... -->` 写 **出口**；TASK 列 **不要**写 visual/real-stack 全量 unless 本 TASK Owns 该档。

## 反模式

- 把 visual 基线 PNG 变更绑进每个 PR 的 fast verify（flake + 噪音）
- Real-stack 无清理策略，污染共享环境
- Mock 套件断言「刷新保持状态」仅用 `body` visible — 须断言路由/tab/hash 等 **真实状态**
