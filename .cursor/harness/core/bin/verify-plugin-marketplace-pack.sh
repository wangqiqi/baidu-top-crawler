#!/usr/bin/env bash
# Validate dist/cursor-plugin-marketplace layout for Cursor official discovery.
set -euo pipefail
# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"
# shellcheck source=../lib/verify-common.sh
source "$CUR/lib/verify-common.sh" "verify-plugin-marketplace-pack"

vc_title
OUT="${SC_PLUGIN_MARKETPLACE_OUT:-$ROOT/dist/cursor-plugin-marketplace}"
PACK="$OUT/super-cursor-mvp"
MANIFEST="$PACK/.cursor-plugin/plugin.json"

if [[ ! -f "$MANIFEST" ]]; then
  vc_fail "missing pack output — run: bash .cursor/harness/core/bin/pack-plugin-marketplace.sh"
fi

for rel in rules/core.mdc skills/master/SKILL.md agents/ship.md hooks/hooks.json assets/logo.svg README.md; do
  [[ -e "$PACK/$rel" ]] || vc_fail "pack missing $rel"
done

[[ -f "$OUT/.cursor-plugin/marketplace.json" ]] || vc_fail "missing marketplace.json at pack root .cursor-plugin/"

vc_py "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
root = p.parent.parent
for key in ("rules", "skills", "agents"):
    val = data.get(key)
    if not val:
        print(f"FAIL: manifest missing {key}", file=sys.stderr)
        sys.exit(1)
    rel = val if isinstance(val, str) else val[0]
    if not (root / rel).is_dir():
        print(f"FAIL: manifest {key}={rel} not found under pack root", file=sys.stderr)
        sys.exit(1)
hooks = data.get("hooks")
if not hooks:
    print("FAIL: manifest missing hooks", file=sys.stderr)
    sys.exit(1)
hook_path = hooks if isinstance(hooks, str) else hooks
if not (root / hook_path).is_file():
    print(f"FAIL: hooks path {hook_path} missing", file=sys.stderr)
    sys.exit(1)
logo = data.get("logo")
if logo and not (root / logo).is_file():
    print(f"FAIL: logo path {logo} missing", file=sys.stderr)
    sys.exit(1)
print("OK  marketplace pack manifest paths resolve")
PY

vc_ok "marketplace pack layout $PACK"
vc_summary
