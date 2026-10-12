# Verify layers（scaffold bundle）

与 Super Cursor `rules/feedback/verify.mdc` 对齐的分层验收骨架。

## 分层

| 层 | 命令 | 用途 |
|----|------|------|
| **L1** | `./scripts/verify.sh` | 开发循环 · 每个 TASK |
| **L2-core** | `./scripts/verify-core.sh` | merge 前 P0 切片 |
| **L2** | `./scripts/verify-release.sh` | Sprint 收尾 / 打版 |
| **L3** | `./scripts/verify.sh --full` | CI / nightly |

## 扩展新 slice

1. 新建 `scripts/verify/slices/verify_<feature>.sh`：

```bash
#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../../lib/load.sh"
sc_cd_root
# … assertions …
sc_pass "verify_<feature>"
```

2. 在 `scripts/lib/verify-layers.sh` 登记到 `VERIFY_SLICES_STANDARD`（或 CORE / HEAVY / TASK）。
3. 跑 `bash scripts/verify/slices/verify_layers_registry.sh`。
4. CI 建议：`VERIFY_REGISTRY_STRICT=1`。

## 并行

互不共享可变状态的 slice 由 `run_suite parallel` 执行；共享安装/seed 的路径用 `flock`（见 `scripts/verify.sh` 入口锁）。
