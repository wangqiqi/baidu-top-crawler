#!/usr/bin/env bash
# 断言路径下 .cursor 为「Cursor IDE 可直接加载」的平铺树（非文本指针门面）。
set -euo pipefail

# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"

TARGET="${1:-$ROOT}"
CUR_PACK="$TARGET/.cursor"

echo "=== verify-cursor-dropin ==="

vc_fail() {
  echo "FAIL cursor-dropin: $*" >&2
  exit 1
}

[[ -d "$CUR_PACK" ]] || vc_fail "missing $CUR_PACK"

# 文本指针：小文件且内容为 harness/ 相对路径
if [[ -f "$CUR_PACK/rules" ]]; then
  vc_fail ".cursor/rules is a pointer file — run install or unpack a dropin pack"
fi
[[ -d "$CUR_PACK/rules" || -L "$CUR_PACK/rules" ]] || vc_fail ".cursor/rules must be a directory or symlink"
[[ -f "$CUR_PACK/rules/core.mdc" ]] || vc_fail "missing rules/core.mdc"
[[ -f "$CUR_PACK/hooks.json" ]] || vc_fail "missing hooks.json"

if [[ -d "$CUR_PACK/skills" || -L "$CUR_PACK/skills" ]]; then
  # install + link-cursor-ide 在 Unix 常保留 skills→harness/core/skills 符号链接；BSD find 须 -L 才计入子目录
  n="$(find -L "$CUR_PACK/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n" -ge 23 ]] || vc_fail "skills count $n < 23 (use find -L if skills is a symlink)"
else
  vc_fail "missing .cursor/skills/"
fi

if [[ -f "$CUR_PACK/bin/runner.sh" ]]; then
  echo "OK  runner.sh present (workflow scripts usable)"
fi

echo "OK  cursor dropin contract ($TARGET)"
exit 0
