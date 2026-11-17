# 安装路径：CLI · 拖放复制（双轨 SSOT）

对外消费 Super Cursor 时，**两条路径等价加载 Cursor IDE 的 rules / skills / hooks**（产物均为平铺 `.cursor/`，非母版「门面指针」）。

| 轨 | 你怎么做 | 典型场景 |
|----|----------|----------|
| **A · CLI 安装** | `bash install-super-cursor.sh <项目根> [--replace] [--copy-plan] …` | 团队仓库 · 要 `.growing/` · gitignore 合并 · adaptor |
| **B · 复制 / 拖放** | 解压 dropin 包，或将已平铺的 `.cursor/` **整夹复制**到项目根 | 无 Git · 内网 U 盘 · 只先要规则 · Windows 资源管理器拖拽 |

**不是 B**：把母版仓里的 `.cursor`（含 `harness/` 指针门面）直接拷走 —— Cursor 往往读不到 rules。请用 **A** 或 **B 的官方 dropin**。

---

## A · CLI 安装

```bash
bash install-super-cursor.sh /path/to/your-project --replace --copy-plan
```

| 会做的事 | 说明 |
|----------|------|
| 平铺 `.cursor/` | 与 dropin 同构（`link-cursor-ide`） |
| `.growing/` | plan · learn · archive 种子（git 忽略） |
| `.gitignore` / `.cursorignore` | 合并 Growth 与 `rules/local` |
| `--adaptor *` | Kiro · Trae · OpenCode 等（可选） |

升级：[consumer-refresh.md](../consumer-refresh.md) · `install-super-cursor.sh --replace`。

---

## B · 复制 / 拖放

### B1 — 官方拖放包（推荐）

在 **Super Cursor 母版** 打包含 `.cursor/` 的 tar：

```bash
bash install-super-cursor.sh --pack-dropin
# 产出: .growing/offline-dist/super-cursor-dropin-<version>-<time>.tar.gz
```

**解压到项目根**（Linux / macOS / Git Bash）：

```bash
tar -xzf super-cursor-dropin-*.tar.gz -C /path/to/your-project
```

**Windows 资源管理器**：解压 zip/tar 得到 `.cursor` 文件夹，**拖进项目根**（与 `package.json` / `.git` 同级）即可。

然后 Cursor：**Developer: Reload Window**。

包内附 `DROPIN-README.md`。校验：

```bash
bash .cursor/bin/verify-cursor-dropin.sh /path/to/your-project
```

### B2 — 手工复制目录

从**已 CLI 安装**或**已解压 dropin** 的项目，复制整个 `.cursor/` 到另一项目根。复制后同样运行 `verify-cursor-dropin.sh`。

---

## 两条轨如何衔接

| 现状 | 下一步 |
|------|--------|
| 只有 B（拖放） | 需要 `/plan` · `.growing` 时，再跑 **A**（`--replace` 可保留已平铺 `.cursor`，主要补 Growth） |
| 只有 A | 给同事 **B1** 包即可，无需对方 clone 母版 |
| 升级版本 | CLI：`install-super-cursor --replace`；拖放：重新 `--pack-dropin` 解压覆盖 `.cursor` |

---

## 母版 / 离线大包

| 命令 | 产出 | 用途 |
|------|------|------|
| `--pack-dropin` | 仅 `.cursor/` + README | **任意项目复制即用** |
| `--pack-offline` | 母版根 + `install-super-cursor.sh` | 无网络环境 · 多次 install |

详见 [platforms.md](../platforms.md) · 根仓库 `README.md` §安装（Marketplace / 发布仓替换为实际 URL）。
