#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
sc_cd_root

VERIFY_LOCK="${SC_ROOT}/.verify.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$VERIFY_LOCK"
  if ! flock -n 9; then
    echo "[错误] 另一个 verify 正在运行（锁: ${VERIFY_LOCK}）" >&2
    echo "       若确认无 verify 进程，可删除该锁文件后重试。" >&2
    exit 1
  fi
fi

# shellcheck source=lib/run-suite.sh
source "$(dirname "$0")/lib/run-suite.sh"
# shellcheck source=lib/verify-layers.sh
source "$(dirname "$0")/lib/verify-layers.sh"

layer="$(sc_verify_resolve_layer "${1:-}")" || exit 1

case "$layer" in
  help)
    sc_verify_usage
    exit 0
    ;;
  l1)
    sc_verify_l1
    ;;
  l2-core)
    sc_verify_l2_core
    ;;
  l2)
    sc_verify_l2
    ;;
  l3)
    sc_verify_l3
    ;;
esac
