#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
[[ -f design-tokens.json ]] || { echo "FAIL: design-tokens.json"; exit 1; }
node scripts/color-audit.mjs
echo "[✓] verify_design_tokens"
