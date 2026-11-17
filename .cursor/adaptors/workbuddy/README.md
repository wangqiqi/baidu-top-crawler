<!-- adaptor-contract:v1 -->

# adaptor: workbuddy

WorkBuddy · Harness Core 安装到 `.workbuddy/`。

## Status

**implemented（core install）** — 按 [docs/layout.md](docs/layout.md) 平铺 core 树；无 hooks（`hooks_manifest`: null）。

## Identity

`adaptor id`: **workbuddy**

## Install map

与 `install-map.example.json` → `adaptors.workbuddy`：

| 字段 | 值 |
|------|-----|
| `install_dir` | `.workbuddy` |
| `growth_dir` | `.growing` |
| `hooks_manifest` | **null** |

## Includes

- `core` — Harness Core 主体（skills · rules · bin · config）；见 [adaptor-contract.md](../../harness/core/docs/reference/adaptor-contract.md) §`includes` token。

## Install

```bash
bash .cursor/harness/core/bin/install-adaptor-workbuddy.sh /path/to/project
# 或与 Cursor 一并：
install-super-cursor /path/to/project --adaptor workbuddy
```

布局 SSOT → [docs/layout.md](docs/layout.md) · 验收 `bash .cursor/bin/verify-install-workbuddy.sh`。

## Next sprint

WorkBuddy 官方 `.workbuddy/` 目录规范（skills / memory / mcp.json 约定）公开并钉死后：对照差距表更新本 `layout.md` 与 `install-adaptor-workbuddy.sh`（另开 Sprint；无 Breaking 假设前保持当前 core 平铺）。
