#!/usr/bin/env bash
# PlanRun 验收脚本（TASK-006）：lint · 单测 · 数据完整性 · 体积预算
#
# 用法:
#   ./scripts/verify.sh            # 全量（体积只报告，不因迁移未完成而失败）
#   ./scripts/verify.sh --lint     # 只跑 ruff
#   ./scripts/verify.sh --tests    # 只跑 pytest
#   ./scripts/verify.sh --data     # 只跑数据完整性（迁移验收）
#   ./scripts/verify.sh --size     # 体积预算硬校验（TASK-009 验收）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="${PYTHON:-python3}"

run_lint() {
  echo "==> lint (ruff)"
  if "$PY" -m ruff --version >/dev/null 2>&1; then
    "$PY" -m ruff check .
  else
    echo "SKIP: ruff 未安装（pip install -e '.[dev]'）"
  fi
}

run_tests() {
  echo "==> tests (pytest)"
  "$PY" -m pytest
}

run_data() {
  echo "==> data integrity"
  "$PY" scripts/check_data.py
}

run_size() {
  echo "==> size budget"
  "$PY" scripts/check_size.py "$@"
}

mode="${1:-all}"
case "$mode" in
  --lint)  run_lint ;;
  --tests) run_tests ;;
  --data)  run_data ;;
  --size)  run_size --strict ;;
  --report-size) run_size ;;
  all|"")
    run_lint
    run_tests
    run_data
    run_size
    ;;
  -h|--help)
    sed -n '2,12p' "$0"
    ;;
  *)
    echo "未知参数: $mode（见 --help）" >&2
    exit 2
    ;;
esac

echo "OK: verify 通过（mode=$mode）"
