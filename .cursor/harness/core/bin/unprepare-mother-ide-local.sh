#!/usr/bin/env bash
# 撤销 prepare-mother-ide-local：去掉 skip-worktree，恢复 git 跟踪的门面指针。
set -euo pipefail

# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"

FACADE_PATHS=(
  .cursor/harness/core/rules/local
  .cursor/agents
  .cursor/bin
  .cursor/config
  .cursor/docs
  .cursor/hooks
  .cursor/hooks.json
  .cursor/lib
  .cursor/rules
  .cursor/skills
  .cursor/templates
  .cursor/AGENTS.md
  .cursor/README.md
  .cursor/verify-super-cursor.sh
  .cursor/verify-system.sh
)

echo "=== unprepare-mother-ide-local ==="

for rel in "${FACADE_PATHS[@]}"; do
  if git -C "$ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    git -C "$ROOT" update-index --no-skip-worktree "$rel" 2>/dev/null || true
  fi
done

for rel in "${FACADE_PATHS[@]}"; do
  if [[ -d "$ROOT/$rel" ]] || [[ -f "$ROOT/$rel" && "$(wc -c <"$ROOT/$rel" 2>/dev/null || echo 0)" -lt 256 ]]; then
    rm -rf "$ROOT/$rel"
  fi
done

git -C "$ROOT" restore "${FACADE_PATHS[@]}" 2>/dev/null || git -C "$ROOT" checkout -- "${FACADE_PATHS[@]}" 2>/dev/null || true

echo "OK  门面指针已恢复；IDE 需 rules 时请再跑 prepare-mother-ide-local.sh"
