#!/usr/bin/env bash
# Smoke-test runner.sh against template plan (no side effects on repo plan.md)
set -euo pipefail

CURSOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$CURSOR_DIR/.." && pwd)"
# Git Bash / Windows 可能只有 python；勿硬编码 python3
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[[ -n "$PYTHON_BIN" ]] || { echo "FAIL: python required for runner smoke"; exit 1; }
TMP_PLAN="$(mktemp)"
trap 'rm -f "$TMP_PLAN"' EXIT

cp "$CURSOR_DIR/templates/plan.md" "$TMP_PLAN"

# Template default is closed/empty; smoke needs an active sprint fixture.
# 不用 `sed -i`（BSD/macOS 需要 -i ''），改走临时文件。
sed \
  -e 's/<!-- ACTIVE: (none) -->/<!-- ACTIVE: TASK-001 -->/' \
  -e 's/<!-- PLAN_APPROVED: (none) -->/<!-- PLAN_APPROVED: 2099-01-01 -->/' \
  -e 's/<!-- SPRINT_STATUS: closed -->/<!-- SPRINT_STATUS: active -->/' \
  -e 's/<!-- SPRINT: (none) -->/<!-- SPRINT: SPRINT-01 -->/' \
  "$TMP_PLAN" > "$TMP_PLAN.new"
mv "$TMP_PLAN.new" "$TMP_PLAN"

# shellcheck source=../hooks/lib/plan-parse.sh
source "$CURSOR_DIR/hooks/lib/plan-parse.sh" "$TMP_PLAN"

echo "=== runner smoke ==="

active="$(plan_active)"
[[ "$active" == "TASK-001" ]] || { echo "FAIL: expected TASK-001, got $active"; exit 1; }
echo "OK  plan_active=$active"

approved="$(plan_plan_approved)"
[[ -n "$approved" ]] || { echo "FAIL: PLAN_APPROVED empty"; exit 1; }
echo "OK  PLAN_APPROVED set"

gate="$(plan_gate_ok)"
[[ "$gate" == "OK" ]] || { echo "FAIL: gate=$gate"; exit 1; }
echo "OK  gate-check would pass"

next="$(plan_next_task)"
echo "OK  next-task=$next"

bash "$CURSOR_DIR/bin/runner.sh" help 2>/dev/null | grep -q 'release-tag' \
  && echo "OK  runner help lists release-tag" \
  || { echo "FAIL: runner help missing release-tag"; exit 1; }

# help 不得有命令替换噪音（回归：未转义反引号）
help_err="$(bash "$CURSOR_DIR/bin/runner.sh" help 2>&1 >/dev/null)"
[[ -z "$help_err" ]] || { echo "FAIL: runner help wrote to stderr: $help_err"; exit 1; }
echo "OK  runner help is clean"

# 闸门 fail-closed：未批准的模板 plan 必须 BLOCK（P0-3 回归）
(
  # shellcheck source=../hooks/lib/plan-parse.sh
  source "$CURSOR_DIR/hooks/lib/plan-parse.sh" "$CURSOR_DIR/templates/plan.md"
  g="$(plan_gate_ok)" || true
  [[ "$g" == "NO_APPROVAL" ]] || { echo "FAIL: template gate=$g (expect NO_APPROVAL)"; exit 1; }
  echo "OK  unapproved template blocks"
) || exit 1

# 造一个含 TASK-001 的临时项目；stdout 只回目录路径
mk_plan_project() {
  local acc="$1" d
  d="$(mktemp -d)"
  mkdir -p "$d/.cursor" "$d/.cursorGrowth"
  cp -a "$CURSOR_DIR/." "$d/.cursor/"
  echo "# t" > "$d/README.md"
  {
    echo '<!-- PLANNING: false -->'
    echo '<!-- PLAN_APPROVED: 2026-09-23 -->'
    echo '<!-- SPRINT: SPRINT-TV -->'
    echo '<!-- ACTIVE: TASK-001 -->'
    echo '<!-- SPRINT_STATUS: active -->'
    echo '<!-- VERIFY: ./README.md -->'
    echo '**执行顺序**: `TASK-001`'
    echo ''
    echo '| ID | Task | Priority | Status | Acceptance | Target |'
    echo '|----|------|----------|--------|------------|--------|'
    echo "| TASK-001 | t | P0 | ⬜ | ${acc} | src/ |"
  } > "$d/.cursorGrowth/plan.md"
  printf '%s' "$d"
}

# 断言某命令在某临时项目里的退出码类别
smoke_assert() {
  local d="$1" expect="$2" label="$3"
  shift 3
  local rc=0
  ( cd "$d" && "$@" ) >/dev/null 2>&1 || rc=$?
  if { [[ "$expect" == "fail" && "$rc" -ne 0 ]] || [[ "$expect" == "pass" && "$rc" -eq 0 ]]; }; then
    echo "OK  $label"
  else
    echo "FAIL: $label (rc=$rc, expect=$expect)"; rm -rf "$d"; exit 1
  fi
}

# task-verify fail-closed 回归（B1）
D="$(mk_plan_project '功能正常，界面没问题')"
smoke_assert "$D" fail "task-verify 描述性验收 FAIL（防假完成）" bash .cursor/bin/runner.sh task-verify TASK-001
smoke_assert "$D" fail "plan-check prose 验收 FAIL（B2）" bash .cursor/bin/runner.sh plan-check
rm -rf "$D"

D="$(mk_plan_project 'manual: 人工走查首页并截图留证')"
smoke_assert "$D" pass "task-verify manual 豁免 PASS" bash .cursor/bin/runner.sh task-verify TASK-001
smoke_assert "$D" pass "plan-check manual 验收 PASS（B2）" bash .cursor/bin/runner.sh plan-check
rm -rf "$D"

D="$(mk_plan_project "bash -c 'exit 0'")"
smoke_assert "$D" pass "task-verify 可执行命令 PASS" bash .cursor/bin/runner.sh task-verify TASK-001
smoke_assert "$D" pass "plan-check 可执行验收 PASS（B2）" bash .cursor/bin/runner.sh plan-check
rm -rf "$D"

D="$(mk_plan_project "bash -c 'exit 3'")"
smoke_assert "$D" fail "task-verify 可执行命令失败时 FAIL" bash .cursor/bin/runner.sh task-verify TASK-001
rm -rf "$D"

# 摩擦日志（B5）：必须是合法 JSONL，report 可聚合
D="$(mk_plan_project "bash -c 'exit 0'")"
( cd "$D" && bash .cursor/bin/runner.sh friction-log --task TASK-001 --rounds 2 --rework 0 --verify pass --note 'x"y' ) >/dev/null 2>&1
( cd "$D" && bash .cursor/bin/runner.sh friction-log --task TASK-002 --rounds 4 --rework 1 --verify fail ) >/dev/null 2>&1
if [[ -f "$D/.cursorGrowth/logs/friction.jsonl" ]] && "$PYTHON_BIN" -c "
import json,sys
[json.loads(l) for l in open(sys.argv[1])]" "$D/.cursorGrowth/logs/friction.jsonl" 2>/dev/null; then
  echo "OK  friction.jsonl is valid JSONL"
else
  echo "FAIL: friction.jsonl invalid"; rm -rf "$D"; exit 1
fi
rep="$( cd "$D" && bash .cursor/bin/runner.sh friction-report )"
case "$rep" in
  *"tasks=2"*"verify_pass=1"*"verify_fail=1"*) echo "OK  friction-report aggregates ($rep)" ;;
  *) echo "FAIL: friction-report unexpected: $rep"; rm -rf "$D"; exit 1 ;;
esac
rm -rf "$D"

echo "runner smoke passed."
