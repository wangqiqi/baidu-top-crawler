#!/usr/bin/env bash
# 母版仓 · 本机 IDE 准备：实体化 .cursor 门面 + git skip-worktree（勿提交实体化结果）。
# 消费方项目请用 install-super-cursor.sh --replace，不要在本仓提交实体副本。
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

echo "=== prepare-mother-ide-local ==="
bash "$CURSOR_DIR/harness/link-cursor-ide.sh"
bash "$CUR/bin/bootstrap-growth.sh"

# harness/core/rules/local 在无 symlink 时实为指针文件，与索引 mode 120000 不一致时标记为脏
if [[ -f "$ROOT/.cursor/harness/core/rules/local" ]] && grep -q '^\.\./' "$ROOT/.cursor/harness/core/rules/local" 2>/dev/null; then
  :
elif [[ ! -e "$ROOT/.cursor/harness/core/rules/local" ]]; then
  printf '%s\n' '../../../../.growing/rules/local' >"$ROOT/.cursor/harness/core/rules/local"
fi

for rel in "${FACADE_PATHS[@]}"; do
  if git -C "$ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
    git -C "$ROOT" update-index --skip-worktree "$rel"
    echo "OK  skip-worktree $rel"
  else
    echo "SKIP $rel (not tracked)"
  fi
done

echo "---"
echo "OK  Cursor / Trae 可读 rules · skills · hooks；CLI git status 应对门面干净。"
echo "Trae 图形 SCM 可能仍显示上万「新文件」——见 .cursor/docs/platforms.md §本机 IDE 与 Trae SCM"
echo "撤销：bash .cursor/harness/core/bin/unprepare-mother-ide-local.sh"
