#!/usr/bin/env bash
# SPIKE-008 SPRINT-MARKETPLACE-PREP: marketplace prep checklist archived (Defer listing).
set -euo pipefail
# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"
ARCHIVE_DIR="$ROOT/.growing/archive/meta"

# 归档为本地私有（.growing/ 不入 git）→ 未引导时 SKIP；本地有 meta/ 仍严格校验
# shellcheck source=../lib/growth-archive.sh
source "$CUR/lib/growth-archive.sh"
sc_growth_archive_available "$ARCHIVE_DIR" "verify-spike-marketplace-prep-scope" || exit 0

shopt -s nullglob
files=("$ARCHIVE_DIR"/*_SPIKE_marketplace_prep_scope.md)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "FAIL: no archive meta/*_SPIKE_marketplace_prep_scope.md" >&2
  exit 1
fi
latest="$(printf '%s\n' "${files[@]}" | sort | tail -1)"
for needle in "Defer" "Marketplace" "manifest" "sync-plugin-subset" "pack-plugin-marketplace" "verify-plugin-marketplace-pack" "verify-cursor-plugin-mvp" "migration-catalog" "cursor-platform" "install" "cursor-plugin"; do
  grep -qF "$needle" "$latest" || { echo "FAIL: missing '$needle' in $latest" >&2; exit 1; }
done
echo "OK: marketplace prep scope spike archive $latest"
