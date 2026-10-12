#!/usr/bin/env bash
# Universal Super Cursor layout check
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CUR="$ROOT/.cursor"

# shellcheck source=bin/../lib/verify-common.sh
source "$CUR/lib/verify-common.sh" "verify-super-cursor"

# Mother-only layout: pure Super Cursor template repo (no co-located business tree).
# Hybrid: .cursor/ + co-located business tree. Auto-detect; override SC_VERIFY_LAYOUT=mother|hybrid.
is_hybrid_repo() {
  case "${SC_VERIFY_LAYOUT:-auto}" in
    hybrid) return 0 ;;
    mother) return 1 ;;
  esac
  [[ -d "$ROOT/scripts" || -d "$ROOT/backend" || -d "$ROOT/frontend" ]]
}

# 是否母版仓（含 install-super-cursor.sh）。安装到目标项目后为 false →
# 跳过母版专属项，使本脚本在目标项目也能得到有意义的结果。
is_mother_repo() {
  [[ -f "$ROOT/install-super-cursor.sh" ]]
}

# 母版专属项：hybrid 仓或目标项目均跳过
skip_mother_only() {
  is_hybrid_repo || ! is_mother_repo
}

check() { [[ -e "$1" ]] && echo "OK  $1" || { echo "FAIL $1"; VC_FAIL=$((VC_FAIL + 1)); }; }
check_mother_only() {
  local path="$1" label="${2:-$1}"
  if skip_mother_only; then
    echo "SKIP  non-mother (mother-only): $label"
    return 0
  fi
  check "$path"
}
check_absent() { [[ -e "$1" ]] && { echo "FAIL must not exist: $1"; VC_FAIL=$((VC_FAIL + 1)); } || echo "OK  absent $1"; }
check_absent_mother_only() {
  local path="$1" label="${2:-must not exist: $1}"
  if skip_mother_only; then
    echo "OK  non-mother (skip mother-only): $label"
    return 0
  fi
  check_absent "$path"
}
check_verify_workflow() {
  if is_hybrid_repo; then
    if [[ -f "$ROOT/scripts/verify.sh" ]]; then
      echo "OK  hybrid: scripts/verify.sh (skip .github/workflows/verify.yml)"
    else
      echo "FAIL hybrid: scripts/verify.sh missing"
      VC_FAIL=$((VC_FAIL + 1))
    fi
    return 0
  fi
  if ! is_mother_repo; then
    echo "SKIP  non-mother: .github/workflows/verify.yml"
    return 0
  fi
  check "$ROOT/.github/workflows/verify.yml"
}
check_grep_absent() {
  local dir="$1" pattern="$2"
  if grep -rq --exclude="verify-super-cursor.sh" "$pattern" "$dir" 2>/dev/null; then
    echo "FAIL $dir contains $pattern"
    VC_FAIL=$((VC_FAIL + 1))
  else
    echo "OK  no '$pattern' in $(basename "$dir") tree"
  fi
}

echo "=== Super Cursor verify (universal) ==="
if is_hybrid_repo; then
  echo "layout mode: hybrid (.cursor + business tree)"
else
  echo "layout mode: mother (pure template repo)"
fi
check "$CUR/rules/core.mdc"
check "$CUR/rules/workflow.mdc"
check "$CUR/rules/feedback/changelog.mdc"
check "$CUR/rules/feedback/verify.mdc"
check "$CUR/rules/execution/submodule.mdc"
check "$CUR/config/workflow.json"
check "$CUR/config/release.json"
check "$CUR/config/README.md"
check "$CUR/templates/plan.md"
if [[ -f "$CUR/templates/plan.md" ]] && ! grep -qE '^\*\*(执行顺序|Order)\*\*' "$CUR/templates/plan.md" 2>/dev/null; then
  echo "FAIL templates/plan.md missing **执行顺序** line"
  VC_FAIL=$((VC_FAIL + 1))
else
  echo "OK  templates/plan.md has execution order line"
fi
check "$CUR/rules/communication/collaboration.mdc"
check "$CUR/rules/execution/docs.mdc"
check "$CUR/rules/execution/commit.mdc"
check "$CUR/rules/execution/bugfix.mdc"
check "$CUR/templates/cursorGrowth/README.md"
check "$CUR/templates/cursorGrowth/learn/plan-conventions.md"
check "$CUR/hooks/growth-init.sh"
check "$CUR/hooks/run-start.sh"
check "$CUR/hooks/run-stop.sh"
check "$CUR/hooks/lib/config-load.sh"
check "$CUR/hooks/lib/plan-parse.sh"
check "$CUR/hooks/lib/json-utils.sh"
check "$CUR/README.md"   # .cursor/README.md
check "$CUR/verify-system.sh"
check "$CUR/lib/platform.sh"
check "$CUR/skills/master/SKILL.md"
check "$CUR/skills/master/routes.md"
check "$CUR/bin/runner-smoke.sh"
check "$CUR/bin/bootstrap-growth.sh"
check "$CUR/bin/install-smoke.sh"
check_mother_only "$ROOT/install-super-cursor.sh"
check_mother_only "$ROOT/AGENTS.md"
if [[ -f "$ROOT/AGENTS.md" ]] && ! is_hybrid_repo && is_mother_repo; then
  grep -q '\.cursor/AGENTS\.md' "$ROOT/AGENTS.md" \
    && echo "OK  root AGENTS.md points at .cursor/AGENTS.md" \
    || { echo "FAIL root AGENTS.md must point at .cursor/AGENTS.md"; VC_FAIL=$((VC_FAIL + 1)); }
fi
check "$CUR/config/profiles/full.json"
check "$CUR/config/profiles/lite.json"
check "$CUR/config/profiles/rules-only.json"
check "$CUR/docs/walkthrough.md"
check "$CUR/rules/tech/rust.mdc"
check "$CUR/rules/tech/nextjs.mdc"
check "$CUR/skills/plan/SKILL.md"
check "$CUR/skills/run/SKILL.md"
check "$CUR/skills/learn/SKILL.md"
check "$CUR/skills/scaffold/SKILL.md"
check "$CUR/skills/git/SKILL.md"
check "$CUR/skills/release/SKILL.md"
check "$CUR/skills/long/SKILL.md"
check "$CUR/commands/plan.md"
check "$CUR/commands/run.md"
check "$CUR/commands/master.md"
check "$CUR/commands/learn.md"
check "$CUR/commands/scaffold.md"
check "$CUR/commands/release.md"
check "$CUR/commands/long.md"
check "$CUR/commands/delivery.md"
check "$CUR/skills/delivery/SKILL.md"
check "$CUR/skills/ux/SKILL.md"
check "$CUR/skills/ia/SKILL.md"
check "$CUR/commands/manual.md"
check "$CUR/commands/report.md"
check "$CUR/skills/debug/SKILL.md"
check "$CUR/skills/review/SKILL.md"
check "$CUR/skills/week/SKILL.md"
check "$CUR/skills/disk/SKILL.md"
check "$CUR/skills/maintain/SKILL.md"
check "$CUR/skills/code-stats-viz/SKILL.md"
check "$CUR/skills/pencil-design/SKILL.md"
check "$CUR/skills/security/SKILL.md"
check "$CUR/skills/api/SKILL.md"
check "$CUR/rules/tech/c.mdc"
check "$CUR/rules/communication/constitution.mdc"
check "$CUR/rules/feedback/evolution.mdc"
check "$CUR/rules/execution/cli-python.mdc"
check "$CUR/rules/execution/vibe.mdc"
check "$CUR/rules/execution/scope.mdc"
check "$CUR/rules/execution/testing.mdc"
check "$CUR/rules/communication/agent-discipline.mdc"
check "$CUR/rules/communication/super-cursor-persona.mdc"
check "$CUR/rules/communication/cursor-standalone.mdc"
check "$CUR/docs/library-index.md"
check "$CUR/config/roles.json"
check "$CUR/skills/debug/SKILL.md"
check "$CUR/skills/test/SKILL.md"
check "$CUR/skills/mcp/SKILL.md"
check "$CUR/skills/refactor/SKILL.md"
check "$CUR/skills/perf/SKILL.md"
check "$CUR/rules/tech/eslint.mdc"
check "$CUR/rules/tech/javascript.mdc"
check "$CUR/rules/execution/security-sdlc.mdc"
check "$CUR/skills/review/SKILL.md"
check "$CUR/skills/study/SKILL.md"
check "$CUR/skills/user-manual/SKILL.md"
check "$CUR/skills/test-report/SKILL.md"
check "$CUR/agents/review.md"
check "$CUR/agents/spike.md"
check "$CUR/docs/migration-catalog.md"
check "$CUR/bin/scaffold.sh"
check "$CUR/bin/scaffold-integrity.sh"
check "$CUR/templates/scaffold/manifest.json"
check "$CUR/docs/training/skills.md"
check "$CUR/docs/quickstart.md"
check "$CUR/docs/effective-collaboration.md"
check "$CUR/docs/platforms.md"
check "$ROOT/.cursorignore"
check "$CUR/templates/scaffold/_shared.cursorignore"
check "$CUR/bin/template-verify.sh"
check_absent_mother_only "$ROOT/scripts"
check_absent "$ROOT/examples"
check_verify_workflow
check "$CUR/skills/release/SKILL.md"
check "$CUR/agents/ship.md"
check "$CUR/AGENTS.md"
check "$CUR/docs/naming.md"
check "$CUR/docs/rules-catalog.md"
check "$CUR/bin/runner.sh"
check "$CUR/bin/platform-check.sh"
check "$CUR/hooks.json"
check "$CUR/bin/cursor-coherence.sh"
check "$CUR/bin/validate-commit-msg.sh"
check "$CUR/rules/tech/cpp.mdc"
check "$CUR/rules/tech/typescript.mdc"
check "$CUR/rules/tech/react.mdc"
check "$CUR/rules/tech/vue.mdc"
check "$CUR/rules/tech/svelte.mdc"
check "$CUR/rules/tech/go.mdc"
check "$CUR/rules/tech/java.mdc"
check "$CUR/rules/tech/python.mdc"
check "$CUR/rules/execution/api.mdc"
check "$CUR/rules/execution/ux.mdc"
check "$CUR/rules/execution/ia.mdc"
check "$CUR/rules/execution/delivery.mdc"
check "$CUR/rules/execution/async-progress.mdc"
check "$CUR/rules/execution/long-running-ui.mdc"
check "$CUR/rules/execution/modal-layering.mdc"
check "$CUR/rules/execution/error-context.mdc"
check "$CUR/rules/execution/single-detector.mdc"
check "$CUR/rules/execution/data-batch.mdc"
check "$CUR/rules/communication/multi-session-edits.mdc"
check "$CUR/rules/execution/data-list.mdc"
check "$CUR/rules/execution/deploy-ops.mdc"
check "$CUR/rules/execution/doc-hygiene.mdc"
check "$CUR/rules/execution/project-docs.mdc"
check "$CUR/rules/execution/i18n-copy.mdc"
check "$CUR/skills/ops-deploy/SKILL.md"
check "$CUR/rules/execution/oss-first.mdc"
check "$CUR/rules/execution/input-bounds.mdc"
check "$CUR/rules/execution/extensibility.mdc"
check "$CUR/rules/execution/prompt-security.mdc"
check "$CUR/rules/feedback/release.mdc"
check "$CUR/rules/feedback/tag.mdc"
check_absent "$ROOT/domain-packages"
check_absent "$ROOT/profiles"
check_absent "$CUR/agents/release.md"
check_absent "$CUR/rules/index.mdc"
check_absent "$CUR/rules/feedback/growth.mdc"
check_grep_absent "$CUR" "date -Iseconds"

check_grep_absent "$CUR" "master 指令"


echo "--- platform helpers ---"
# shellcheck source=lib/platform.sh
source "$CUR/lib/platform.sh"
ts="$(iso8601_now)"
[[ -n "$ts" ]] && echo "OK  iso8601_now=$ts" || { echo "FAIL iso8601_now"; VC_FAIL=$((VC_FAIL + 1)); }
pf="$(json_cfg "$CUR/config/workflow.json" plan_file __missing__)"
[[ "$pf" == ".cursorGrowth/plan.md" ]] && echo "OK  json_cfg plan_file=$pf" || { echo "FAIL json_cfg plan_file=$pf"; VC_FAIL=$((VC_FAIL + 1)); }
we="$(json_cfg "$CUR/config/workflow.json" workflow.enabled __missing__)"
[[ "$we" == "true" ]] && echo "OK  json_cfg workflow.enabled=$we" || { echo "FAIL json_cfg workflow.enabled=$we"; VC_FAIL=$((VC_FAIL + 1)); }

echo "--- changelog order (newest_first) ---"
# release.json order=newest_first：已发布 ## [x.y.z] 节须严格新→旧；## [Unreleased] 可置顶
CL="$ROOT/CHANGELOG.md"
if [[ ! -f "$CL" ]]; then
  echo "OK  no root CHANGELOG.md (skip order check)"
elif ! py="$(sc_python 2>/dev/null)"; then
  echo "FAIL python required for CHANGELOG order check"
  VC_FAIL=$((VC_FAIL + 1))
else
  if "$py" - "$CL" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# capture semver headings only (skip Unreleased)
vers = re.findall(r"^## \[(\d+\.\d+\.\d+)\]", text, flags=re.M)
if len(vers) < 2:
    print("OK  CHANGELOG version headings <%d (skip strict order)" % len(vers))
    sys.exit(0)

def key(v: str):
    return tuple(int(x) for x in v.split("."))

for i in range(len(vers) - 1):
    if key(vers[i]) <= key(vers[i + 1]):
        print(
            "FAIL CHANGELOG not newest_first: %s then %s (index %d)"
            % (vers[i], vers[i + 1], i)
        )
        sys.exit(1)
print("OK  CHANGELOG newest_first (%d version headings)" % len(vers))
sys.exit(0)
PY
  then
    :
  else
    VC_FAIL=$((VC_FAIL + 1))
  fi
fi

echo "--- roles.json persona speech ---"
roles_file="$CUR/config/roles.json"
if [[ -f "$roles_file" ]]; then
  py="$(sc_python 2>/dev/null || true)"
  if [[ -n "$py" ]] && "$py" - "$roles_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
rules = data.get("speech_rules") or {}
assert rules.get("forbid_self_name_opener") is True
for p in data.get("personas", []):
    assert len(p.get("speech_examples") or []) >= 4, p.get("id")
    gn = str(p.get("given_name") or "")
    for line in p.get("speech_examples") or []:
        assert not gn or not str(line).strip().startswith(gn), p.get("id")
    cues = p.get("voice_cues") or {}
    for k in ("address_user", "rhythm", "flavor", "never"):
        assert cues.get(k), f"{p.get('id')} missing voice_cues.{k}"
    emo = p.get("emotion_cues") or {}
    for k in ("on_success", "on_blocker", "on_decision", "on_grind"):
        assert emo.get(k), f"{p.get('id')} missing emotion_cues.{k}"
print("OK  roles.json speech_rules voice_cues emotion_cues examples")
PY
  then
    :
  else
    VC_FAIL=$((VC_FAIL + 1))
  fi
else
  echo "FAIL roles.json missing"
  VC_FAIL=$((VC_FAIL + 1))
fi

echo "--- standalone: no upstream URL in skills ---"
# skill 正文禁止 github.com 作 SSOT（library-index / standalone-map 除外）
violators=""
while IFS= read -r f; do
  [[ "$f" == *"standalone-map.md" ]] && continue
  violators="${violators}${f}"$'\n'
done < <(grep -rl 'https://github.com' "$CUR/skills" 2>/dev/null || true)
if [[ -n "$(echo "$violators" | sed '/^$/d')" ]]; then
  echo "FAIL skills contain github.com URL (use docs/library-index.md):"
  echo "$violators" | sed '/^$/d'
  VC_FAIL=$((VC_FAIL + 1))
else
  echo "OK  skills no upstream github URLs"
fi

echo "--- standalone: denylist（用户 / 项目 / 机器 / 凭据）---"
DENYLIST="$CUR/config/denylist.txt"
if [[ ! -f "$DENYLIST" ]]; then
  echo "FAIL missing $DENYLIST — standalone guard would be silently disabled"
  VC_FAIL=$((VC_FAIL + 1))
else
  deny_rules=0
  deny_hits=""
  while IFS= read -r pat || [[ -n "$pat" ]]; do
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    deny_rules=$((deny_rules + 1))
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      case "$f" in
        */verify-super-cursor.sh|*/config/denylist.txt) continue ;;
      esac
      deny_hits="${deny_hits}${f#*/}  <=  ${pat}"$'\n'
    done < <(grep -rliE -- "$pat" "$CUR" 2>/dev/null || true)
  done < "$DENYLIST"
  if [[ -n "$(printf '%s' "$deny_hits" | sed '/^$/d')" ]]; then
    echo "FAIL .cursor violates standalone denylist ($DENYLIST):"
    printf '%s' "$deny_hits" | sed '/^$/d' | sort -u
    VC_FAIL=$((VC_FAIL + 1))
  else
    echo "OK  standalone denylist clean (${deny_rules} rules)"
  fi
fi

echo "=== doc + growth-layout + rules-globs 子验证（母版专属）==="
if is_mother_repo; then
  bash "$CUR/bin/verify-doc-super-cursor.sh" || VC_FAIL=$((VC_FAIL + 1))
  bash "$CUR/bin/verify-growth-layout.sh" || VC_FAIL=$((VC_FAIL + 1))
else
  echo "SKIP  non-mother: verify-doc / verify-growth-layout（母版门面计数检查）"
fi
bash "$CUR/bin/verify-rules-globs.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-portability.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-config.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-roo-compat.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-secrets.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-scripts-layout.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-docs-layout.sh" || VC_FAIL=$((VC_FAIL + 1))
bash "$CUR/bin/verify-changelog.sh" || VC_FAIL=$((VC_FAIL + 1))

echo "=== verify wiring 自检 ==="
# 防止「脚本存在但没接线」：bin/verify-*.sh 必须被本脚本或 template-verify.sh 调用
orphans=""
for _v in "$CUR"/bin/verify-*.sh; do
  [[ -e "$_v" ]] || continue
  _n="$(basename "$_v")"
  if ! grep -qF "bin/$_n" "$CUR/verify-super-cursor.sh" "$CUR/bin/template-verify.sh" 2>/dev/null; then
    orphans="${orphans} ${_n}"
  fi
done
if [[ -n "$orphans" ]]; then
  echo "FAIL orphaned verifier(s) not aggregated by verify-super-cursor.sh or template-verify.sh:$orphans"
  VC_FAIL=$((VC_FAIL + 1))
else
  echo "OK  all bin/verify-*.sh are aggregated"
fi

echo "---"
vc_summary "All checks passed."
