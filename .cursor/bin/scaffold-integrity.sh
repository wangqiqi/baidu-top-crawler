#!/usr/bin/env bash
# Validate scaffold templates: test.sh · verify.sh · tests layout
set -euo pipefail

CURSOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_ROOT="$CURSOR_DIR/templates/scaffold"
MANIFEST="$TEMPLATE_ROOT/manifest.json"
# shellcheck source=../lib/platform.sh
source "$CURSOR_DIR/lib/platform.sh"
FAIL=0

fail() { echo "FAIL $1"; FAIL=$((FAIL + 1)); }
ok() { echo "OK  $1"; }

if ! sc_has_json_tool; then
  echo "FAIL: jq or python (python3) required" >&2
  exit 1
fi

echo "=== scaffold integrity ==="

# 共享层：scripts 分层骨架 + lib 公因子（E3）
for f in scripts/README.md scripts/lib/_common.sh scripts/verify/domain/.gitkeep scripts/verify/tier/.gitkeep; do
  [[ -f "$TEMPLATE_ROOT/_shared/$f" ]] && ok "_shared/$f" || fail "_shared missing $f"
done

while IFS= read -r id; do
  id="${id%$'\r'}"          # Windows python 文本模式可能残留 CR
  dir="$TEMPLATE_ROOT/$id"
  [[ -d "$dir" ]] || { fail "missing dir $id"; continue; }

  for script in scripts/test.sh scripts/verify.sh .github/workflows/ci.yml; do
    [[ -f "$dir/$script" ]] || fail "$id: missing $script"
  done

  test_field="$(sc_manifest_scaffold_field "$MANIFEST" "$id" test)"; test_field="${test_field%$'\r'}"
  verify_field="$(sc_manifest_scaffold_field "$MANIFEST" "$id" verify)"; verify_field="${verify_field%$'\r'}"
  [[ "$test_field" == "scripts/test.sh" ]] || fail "$id: manifest test field"
  [[ "$verify_field" == "scripts/verify.sh" ]] || fail "$id: manifest verify field"

  case "$id" in
    react-vite-ts|vue-vite-ts|nextjs-ts|cpp-cmake|rust-axum)
      [[ -d "$dir/tests" ]] || fail "$id: missing tests/"
      ;;
    go-api)
      [[ -d "$dir/tests/integration" ]] || fail "$id: missing tests/integration/"
      ;;
    python-fastapi)
      [[ -d "$dir/tests/unit" && -d "$dir/tests/integration" ]] || fail "$id: missing tests/unit|integration"
      ;;
  esac

  ok "$id"
done < <(sc_manifest_ids "$MANIFEST")

# 测试框架必须与声明一致（testing.mdc 选型表 · 优先成熟开源）
while IFS= read -r id; do
  id="${id%$'\r'}"
  declared="$(sc_manifest_scaffold_field_join "$MANIFEST" "$id" test_framework 2>/dev/null || true)"; declared="${declared%$'\r'}"
  [[ -z "$declared" || "$declared" == "null" ]] && continue
  hits=0
  for f in "$TEMPLATE_ROOT/$id/scripts/test.sh" "$TEMPLATE_ROOT/$id/scripts/verify.sh" "$TEMPLATE_ROOT/$id/package.json" "$TEMPLATE_ROOT/$id/pyproject.toml" "$TEMPLATE_ROOT/$id/Cargo.toml" "$TEMPLATE_ROOT/$id/CMakeLists.txt"; do
    [[ -f "$f" ]] || continue
    for kw in $declared; do
      [[ -z "$kw" ]] && continue
      grep -qF -- "$kw" "$f" 2>/dev/null && hits=$((hits + 1))
    done
  done
  if [[ "$hits" -gt 0 ]]; then
    ok "$id test framework declared+used: $declared"
  else
    fail "$id declares test_framework='$declared' but no script/config references it"
  fi
done < <(sc_manifest_ids "$MANIFEST")

while IFS= read -r id; do
  id="${id%$'\r'}"
  src="$TEMPLATE_ROOT/$id/scripts/verify.sh"
  [[ -f "$src" ]] || continue
  # 任一共因子均可（_common.sh 或栈专用 _frontend.sh，后者自身 source _common.sh）
  if grep -q 'lib/_' "$src"; then
    ok "$id verify.sh sources scripts/lib/_* 公因子"
  else
    fail "$id verify.sh does not source scripts/lib/_*.sh (scripts 分层前导)"
  fi
done < <(sc_manifest_ids "$MANIFEST")

bundle_root="$TEMPLATE_ROOT/_bundles/user-manual"
if sc_manifest_bundle_exists "$MANIFEST" "user-manual"; then
  echo ""
  echo "=== bundle integrity ==="
  for f in \
    shared/config/manual.yaml \
    shared/docs/user-guide.md \
    shared/scripts/docs/sync_manual_screenshots.sh \
    shared/scripts/verify/docs/verify_doc_manual.sh \
    web/e2e/manual-walkthrough.spec.ts \
    web/playwright.manual.config.ts
  do
    [[ -f "$bundle_root/$f" ]] && ok "bundle user-manual $f" || fail "bundle missing $f"
  done
fi

bundle_root="$TEMPLATE_ROOT/_bundles/test-report"
if sc_manifest_bundle_exists "$MANIFEST" "test-report"; then
  echo ""
  echo "=== bundle integrity (test-report) ==="
  for f in \
    shared/config/test-report.yaml \
    shared/docs/test-report.md \
    shared/scripts/docs/collect_test_report.sh \
    shared/scripts/verify/docs/verify_test_report.sh \
    shared/design/test-report/README.md
  do
    [[ -f "$bundle_root/$f" ]] && ok "bundle test-report $f" || fail "bundle missing $f"
  done
fi

[[ "$FAIL" -eq 0 ]] && exit 0
echo "$FAIL scaffold check(s) failed." >&2
exit 1
