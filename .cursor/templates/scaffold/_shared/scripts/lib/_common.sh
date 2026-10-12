#!/usr/bin/env bash
# 项目脚本公共骨架 —— `scripts/lib/_*.sh` 约定：**只 source，不直接 exec**
#
# 分层 SSOT：`.cursor/skills/plan/reference/growth-layout.md` §Scripts 布局
#   scripts/{test.sh,verify.sh}   根只留入口（开发循环 / 聚合）
#   scripts/verify/tier/          L0/L2/L3 orchestrator
#   scripts/verify/domain/        L1 域脚本 verify_*.sh
#   scripts/lib/_*.sh             公因子（本文件）
#   scripts/ops/ · scripts/dev/   工具与一次性脚本
[[ -n "${SC_SCRIPT_COMMON_LOADED:-}" ]] && return 0
SC_SCRIPT_COMMON_LOADED=1

# 切到项目根（scripts/lib/_common.sh → 项目根 = ../..）
sc_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cd "$here"
}

sc_step() { echo "==> $*"; }
sc_ok() { echo "OK  $*"; }
sc_fail() { echo "FAIL $*"; SC_STEP_FAILS=$((SC_STEP_FAILS + 1)); }
SC_STEP_FAILS=0

# 需要外部命令时显式报错（避免"命令不存在"被当成测试失败）
sc_require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { sc_fail "missing command: $c"; return 1; }
  done
}

sc_summary() {
  echo "---"
  if [[ "${SC_STEP_FAILS:-0}" -eq 0 ]]; then
    echo "${1:-all steps passed.}"
    return 0
  fi
  echo "${SC_STEP_FAILS} step(s) failed."
  return 1
}
