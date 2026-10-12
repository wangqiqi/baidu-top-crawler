#!/usr/bin/env bash
# 验证器公共骨架 —— 消除 8 个 verify-*.sh 各自重复的样板
#
# 用法：
#   source "$CUR/lib/verify-common.sh" "verify-xxx"
#   vc_title
#   vc_ok "msg" / vc_fail "msg" / vc_info "msg" / vc_skip "msg"
#   vc_py "$ARG" <<'PY'   # stdin 的 python 块；失败自动计入，始终返回 0（兼容 set -e）
#   ...
#   PY
#   vc_summary            # 打印汇总并返回 0/1
#
# 输出格式约定（勿改）：`OK  msg` · `FAIL msg` · `SKIP  msg` —— 上游脚本与测试按前缀 grep。
set -euo pipefail

[[ -n "${VC_LOADED:-}" ]] && return 0
VC_LOADED=1

# shellcheck source=platform.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform.sh"

VC_NAME="${1:-verify}"
VC_FAIL=0

vc_title() { echo "=== ${VC_NAME} ==="; }
vc_ok() { echo "OK  $*"; }
vc_fail() {
  echo "FAIL $*"
  VC_FAIL=$((VC_FAIL + 1))
}
vc_info() { echo "  -- $*"; }
vc_skip() { echo "SKIP  $*"; }

# python 解释器（Git Bash 可能只有 python）
vc_python() { sc_python; }

# 运行 stdin 传入的 python 块；失败计入 VC_FAIL，**始终返回 0**（否则在 set -e 下会中断脚本）
vc_py() {
  local py
  if ! py="$(vc_python 2>/dev/null)"; then
    vc_fail "${VC_NAME}: python required"
    return 0
  fi
  if ! "$py" - "$@"; then
    VC_FAIL=$((VC_FAIL + 1))
  fi
  return 0
}

# 汇总并给出退出码；$1 可覆盖成功文案
vc_summary() {
  echo "---"
  if [[ "$VC_FAIL" -eq 0 ]]; then
    echo "${1:-${VC_NAME} passed.}"
    return 0
  fi
  echo "${VC_FAIL} check(s) failed."
  return 1
}
