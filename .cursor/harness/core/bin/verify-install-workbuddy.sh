#!/usr/bin/env bash
# Smoke: install Harness Core into .workbuddy/ (temp dir).
set -euo pipefail
# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"
# shellcheck source=../lib/temp-cleanup.sh
source "$CUR/lib/temp-cleanup.sh"
sc_temp_trap_cleanup
INSTALL_WB="$CUR/bin/install-adaptor-workbuddy.sh"

sc_mktemp_dir sc-verify-install-workbuddy
TMP="$SC_MKTEMP_LAST"

if ! bash "$INSTALL_WB" "$TMP" --profile lite --skills-bundle core >/dev/null 2>&1; then
  echo "FAIL: install-adaptor-workbuddy exited non-zero" >&2
  exit 1
fi

for f in .workbuddy/skills .workbuddy/rules/core.mdc .workbuddy/bin/runner.sh .workbuddy/config/workflow.json; do
  [[ -e "$TMP/$f" ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done

[[ -f "$TMP/.workbuddy/README.md" ]] || { echo "FAIL: missing .workbuddy/README.md" >&2; exit 1; }
[[ ! -e "$TMP/.workbuddy/hooks.json" ]] && [[ ! -d "$TMP/.workbuddy/hooks" ]] || {
  echo "FAIL: .workbuddy must not include Cursor hooks tree" >&2
  exit 1
}
[[ ! -d "$TMP/.workbuddy/adaptors" ]] || { echo "FAIL: .workbuddy must not include adaptors/" >&2; exit 1; }

core_n="$(find -L "$TMP/.workbuddy/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$core_n" == "23" ]] || { echo "FAIL: .workbuddy skills=$core_n (expected 23 for core bundle)" >&2; exit 1; }

echo "OK: verify-install-workbuddy (.workbuddy core bundle skills=$core_n)"
