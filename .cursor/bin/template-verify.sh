#!/usr/bin/env bash
# Super Cursor 母版仓库完整验收（layout + scaffold + runner）
# verify-super-cursor.sh 自动 mother | hybrid；混合仓不 FAIL 纯母版 layout 项。
set -euo pipefail
CUR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$CUR/.." && pwd)"
cd "$ROOT"

echo "=== Bootstrap .cursorGrowth (mother repo) ==="
bash "$CUR/bin/bootstrap-growth.sh"

echo ""
echo "=== Super Cursor template verify ==="
bash "$CUR/verify-super-cursor.sh"

echo ""
echo "=== Cursor coherence ==="
bash "$CUR/bin/cursor-coherence.sh"

echo ""
echo "=== Scaffold CLI smoke ==="
bash "$CUR/bin/scaffold.sh" list >/dev/null
bash "$CUR/bin/scaffold.sh" detect >/dev/null
bash "$CUR/bin/scaffold.sh" apply-bundle user-manual --dry-run --stack react-vite-ts >/dev/null
bash "$CUR/bin/scaffold.sh" apply-bundle test-report --dry-run --stack go-api >/dev/null

# bundle/scaffold 解析必须同时支持 jq 与 python 回退
# （历史缺陷：bundle 路径直连 jq，无 jq 时 apply-bundle 直接 FAIL，且回退腿表面绿）
echo "  -- python 回退腿（SC_FORCE_PYTHON=1）"
SC_FORCE_PYTHON=1 bash "$CUR/bin/scaffold.sh" list >/dev/null
SC_FORCE_PYTHON=1 bash "$CUR/bin/scaffold.sh" apply-bundle user-manual --dry-run --stack react-vite-ts >/dev/null

echo ""
echo "=== Scaffold integrity ==="
bash "$CUR/bin/scaffold-integrity.sh"

echo ""
echo "=== Runner smoke ==="
bash "$CUR/bin/runner-smoke.sh"

echo ""
echo "=== Install smoke ==="
if [[ -f "$ROOT/install-super-cursor.sh" ]]; then
  bash "$CUR/bin/install-smoke.sh"
else
  echo "OK  skip install-smoke (target project — no install-super-cursor.sh)"
fi

echo ""
echo "=== Consumer smoke（目标项目端到端）==="
bash "$CUR/bin/consumer-smoke.sh"

echo ""
echo "=== Platform check ==="
bash "$CUR/bin/platform-check.sh"

echo ""
echo "All template checks passed."
