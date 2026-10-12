# Super Cursor — `.cursor/`

通用 SOP 目录。**母版仓库**可自由演进；安装到目标项目后默认**只读**（见 **cursor-standalone**）。项目认知 → 运行时 `growth.learn_dir`（git 忽略）。

## 结构

| 始终加载（4） | `rules/core.mdc` · `rules/workflow.mdc` · `rules/communication/cursor-standalone.mdc` · `rules/communication/super-cursor-persona.mdc` |
| 按需 | skills · glob rules · `learn/` |

```
rules/   communication · execution · feedback · tech
skills/  master plan run learn scaffold git release …（SOP 正文；日常只记 plan/run/master）
commands/ 三层 slash（薄入口 → 加载 skill；见下表）
agents/  ship review spike（子进程委派；日常不必记）
hooks/   growth-init run-start run-stop
config/  workflow.json release.json roles.json + schema.json（config 校验）· denylist.txt（母版独立扫描）
bin/     runner.sh scaffold.sh（含 apply-bundle）· 验证器：template-verify · verify-super-cursor · cursor-coherence
         · verify-{doc-super-cursor,growth-layout,rules-globs,portability,config,roo-compat,secrets,scripts-layout,docs-layout,changelog}
         · smoke：install-smoke · consumer-smoke（目标项目端到端）· runner-smoke · scaffold-integrity · platform-check
         · 其它：bootstrap-growth · resolve-role · validate-commit-msg
lib/     platform.sh（跨平台工具 · JSON python 回退 · SC_FORCE_PYTHON）
templates/scaffold/   manifest + stack templates
```

```bash
bash .cursor/bin/template-verify.sh          # 母版全量（推荐 · CI 入口）
bash .cursor/verify-super-cursor.sh          # layout + 11 道门禁（混合仓自动 hybrid；目标项目亦可跑）
bash .cursor/bin/consumer-smoke.sh           # 目标项目端到端：install → 闸门 → hook → 全绿
bash .cursor/bin/cursor-coherence.sh         # 交叉自洽
bash .cursor/verify-system.sh                # 同上 layout（alias）
```

门禁清单与语义 → [`rules/feedback/verify.mdc`](rules/feedback/verify.mdc) §母版门禁清单。

混合仓（根目录有 `scripts/` · `backend/` · `frontend/` 等业务树）：`verify-super-cursor` 自动 **SKIP** 纯母版项（`install-super-cursor.sh` · 禁止 `scripts/` · `.github/workflows/verify.yml`），改验 `scripts/verify.sh`。强制空仓：`SC_VERIFY_LAYOUT=mother`。

命名：[docs/naming.md](docs/naming.md)

## Slash 入口（三层 · 记前两层即可）

slash 菜单按 **【日常】→【生命周期】→【高级】** 标注；Agent 可自动选用的 skill **不必死记 slash**。

### 【日常】80% 时间

| Command | 何时用 | Skill |
|---------|--------|-------|
| **`/run`** | 已有 TASK · 写代码 · 修 bug（**默认入口**） | run |
| **`/plan`** | 新开 Sprint · 拆 Goal/TASK（无 ACTIVE 时） | plan |
| **`/master`** | 真迷路 · 刚安装 · 不知 slash（**勿滥用**） | master |

### 【生命周期】Sprint 前后

| Command | 何时用 | Skill |
|---------|--------|-------|
| `/scaffold` | 空仓库建栈 · 已有项目 audit | scaffold |
| `/learn` | 让 Agent 了解本项目；可据证据**建议约定**（落 Growth / local，不擅自改 `.cursor/`） | learn |
| `/long` | Epic 长程 · 多 Sprint plan/run 链 · checkpoint 续跑 | long |
| `/release` | merge / PR / 打 tag（Sprint 出口） | release |

### 【高级】按需

| Command | 何时用 | Skill |
|---------|--------|-------|
| `/delivery` | UI/功能 Sprint 发版前 7 维走查（**不是**规划导航） | delivery |
| `/manual` | 可发布软件使用说明书 · 配图 regen（**不是** delivery 走查） | user-manual |
| `/report` | 全量/分层测试报告 · verify 后汇总（**不是** 写测试） | test-report |

**无 slash · skill-only**（Agent 按意图自动选用，或 `@` / 关键词）：**ux** · **ia** · **debug** · **review** · **pencil-design**（以及 api/git/test/…）。

**需显式 `/skill` 调用**（`disable-model-invocation: true` — Agent **不会**按关键词自动选用）：**`/week`** · **`/disk`** · **`/maintain`** · **`/ops-deploy`** · **`/code-stats-viz`**。策略表 → [docs/training/skills.md](docs/training/skills.md) §disable-model-invocation。

## 使用场景

**路由分两层**：主路由（7 项）+ `more` 子路由内联在 **`skills/master/SKILL.md`**（默认 payload，避免为了路由再读一个长文件）；关键词索引 · 上下文捷径 · 人格 · DAILY/LIBRARY → **`skills/master/routes.md`**（按需扩展索引）。  
培训速查 → [docs/training/skills.md](docs/training/skills.md) · 端到端示例 → [walkthrough.md](docs/walkthrough.md)。

### 推荐路径

```
空仓库:  /master → /scaffold → /learn → /plan → /run → verify
迭代:    /plan（先总后分、同层 MECE）→ /run **一次**（只沿 ACTIVE 分支连跑 TASK）
长程:    /long <Epic> → 拆 Sprint → 每 Sprint plan+run → checkpoint；易断连可配系统 /loop
卡住:    /master → fix → /run 或 /plan
迷路:    /master（主菜单 7 项 → 子路由）
```

**效果型效率** — 少拉扯才是真省：`/plan` 对齐方向 · `task-verify` 防假完成 · 一事一对话。≠ 压 token 省单次会话。→ [docs/effective-collaboration.md](docs/effective-collaboration.md)

### 技术栈细则（glob 自动加载）

| 类别 | 规则 | 典型 glob |
|------|------|-----------|
| 前端 | `typescript` · `react` · `vue` · `nextjs` · `eslint` · `javascript` | `*.ts(x)` · `*.js(x)` · `*.vue` |
| 后端 / 系统 | `python` · `go` · `rust` · `java` · `cpp` · `c` | `*.py` · `*.go` · `*.rs` · `*.java` · `*.{c,cc,cpp,h,hpp}` |

治理：`constitution.mdc` · `evolution.mdc` · `config/roles.json`（12 人格 · 呼叫可解析 · Growth 会话态 · speech_examples；**skills 全员 full**）。  
扩展 skills（主路径）：**ux** · **ia** · **debug** · **test** · **review** · **study** · **delivery** · **user-manual** · **test-report** · **mcp** · **refactor** · **perf**（入口见 `core.mdc`）。  
**工具技能**：**pencil-design**（关键词可自动选用）· **`/week`**（CHANGELOG 多仓）· **`/disk`** · **`/maintain`** · **`/ops-deploy`** · **`/code-stats-viz`**（后五者 `disable-model-invocation: true`，须显式调用）— full 默认带；lite/rules-only 可不强调（见 `config/README`）。

### 重复劳动 SOP（rules · 通用）

| 模式 | 位置 |
|------|------|
| 开源优先 / vendor 溯源 | `rules/execution/oss-first.mdc` · `submodule.mdc`（**二级**；入口 `/master` → deps） |
| 输入边界 / 安全默认 | `rules/execution/input-bounds.mdc` · **api** / **security** 清单 |
| 扩展宿主（可选） | `rules/execution/extensibility.mdc`（**三级** · glob；无独立 slash） |
| Prompt / Agent 安全 | `rules/execution/prompt-security.mdc` · **security** 清单 |
| 分层验收 verify-layers | `rules/feedback/verify.mdc` · **test** skill |
| 全栈垂直切片 | `rules/execution/vibe.mdc` · **api** skill |
| 文档自洽 doc-coherence | `rules/execution/docs.mdc` · **delivery** skill · **user-manual** `/manual` · **test-report** `/report` |
| 浏览器走查（可选） | **delivery** §10（`skills/delivery/reference/checklist-optional.md`）— UI Sprint 建议；可跳过；无强制 MCP |
| 无障碍（可选） | **delivery** §11（同上 optional 清单）— 键盘·焦点·语义/label·对比度；可跳过；不强制 axe/MCP |
| 系统调试循环 | **debug** skill — 复现→假设→隔离→验证→记录；无复现不盲改；`/run` 自修≤2 后 `⚠️`→`/plan` |
| 数据批处理 IN/分块 | `rules/execution/data-batch.mdc` |
| MCP 建服 | **mcp** skill · `skills/mcp/reference/` |
| delivery / plan 详单 | **delivery** / **plan** · 各自 `skills/*/reference/`（SKILL 为薄索引） |
| 实验闭环 experiment-loop | **spike** agent · **learn** skill |

项目路径与聚合脚本名 → Growth `learn/`（如 `dev-conventions.md`），**勿**写进母版 `.cursor/`。

### 场景速查（摘要）

完整关键词与子路由 → **`skills/master/routes.md`**（canonical）。日常只需：

| 我想… | 入口 |
|-------|------|
| 做事 / 写代码 | **`/run`** |
| 拆 Sprint | **`/plan`** |
| 真迷路 | **`/master`** |
| 空仓 / 发版 / 交付 / 说明书 / 测试报告 | `/scaffold` · `/release` · `/delivery` · `/manual` · `/report` |
| UX·IA / 调试 / 回顾 | skill **ux** · **ia** · **debug** · **review**（无 slash；Agent 自动或 `@`） |

培训表 → [docs/training/skills.md](docs/training/skills.md)。

## 更多文档

- [Naming](docs/naming.md) · [plan/run](docs/plan-run.md) · [效果型效率](docs/effective-collaboration.md) · [Quickstart](docs/quickstart.md)
- [Skills 速查](docs/training/skills.md) · [跨平台](docs/platforms.md)
