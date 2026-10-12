#!/usr/bin/env bash
# dsh-guard.sh — workflow guard MVP for PlanRun (gate-check · plan-check · task-verify · next-task)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Nested bash calls must not depend on `bash` being on PATH: on Windows the
# launcher may have resolved a Git bash that is not exported to this shell.
BASH_BIN="${BASH:-$(command -v bash 2>/dev/null || command -v sh)}"
SC_SKIP_PREFIXES="${SC_SKIP_PREFIXES:-REV- SPIKE- DOC-}"
HEURISTICS_ENABLED="${DSH_GUARD_HEURISTICS:-true}"
FALLBACK_VERIFY="${DSH_GUARD_FALLBACK_VERIFY:-}"
# `eval` runs text taken from the plan file, so it is a local code-execution
# surface. Keep it on by default (existing plans rely on it) but make it a
# documented switch, and always echo what is about to run.
EXEC_ENABLED="${DSH_GUARD_EXEC:-true}"

resolve_plan_file() {
  local candidate dir plan_env
  if [[ -n "${DSH_GROWTH_PLAN:-}" ]]; then
    plan_env="${DSH_GROWTH_PLAN}"
    # GNU dirname/basename split on "/" only: a Windows-style value such as
    # E:\repo\.dsh\growth\plan.md produced "<cwd>/E:\repo\...plan.md" and the
    # guard then reported "plan 不存在" for a file that exists.
    if command -v cygpath >/dev/null 2>&1; then
      plan_env="$(cygpath -u "$plan_env" 2>/dev/null || printf '%s' "$plan_env")"
    fi
    if [[ -f "$plan_env" ]]; then
      echo "$(cd "$(dirname "$plan_env")" && pwd)/$(basename "$plan_env")"
      return 0
    fi
    echo "FAIL: DSH_GROWTH_PLAN 不存在: ${DSH_GROWTH_PLAN}" >&2
    return 1
  fi
  dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    for candidate in "$dir/.dsh/growth/plan.md" "$dir/.cursorGrowth/plan.md"; do
      if [[ -f "$candidate" ]]; then
        echo "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  for candidate in "$ROOT/.dsh/growth/plan.md" "$ROOT/.cursorGrowth/plan.md"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo ""
  return 0
}

resolve_fallback_verify() {
  if [[ -n "$FALLBACK_VERIFY" ]]; then
    echo "$FALLBACK_VERIFY"
    return 0
  fi
  if [[ -f "$ROOT/scripts/verify.sh" ]]; then
    echo "./scripts/verify.sh"
    return 0
  fi
  if [[ -f "$ROOT/scripts/verify-planrun.sh" ]]; then
    echo "./scripts/verify-planrun.sh"
    return 0
  fi
  echo "./scripts/verify.sh"
}

FALLBACK_VERIFY="$(resolve_fallback_verify)"

PLAN="$(resolve_plan_file)" || exit 1
export SC_SKIP_PREFIXES
# shellcheck source=plan-parse.sh
source "$ROOT/scripts/plan-parse.sh" "$PLAN"

cmd="${1:-status}"

# Commands that only read the plan used to fall through to plan-parse.sh with an
# empty path, where `PLAN_FILE="${1:-plan.md}"` silently parsed a stray
# ./plan.md from the cwd. Refuse instead.
require_plan() {
  if [[ -z "$PLAN" || ! -f "$PLAN" ]]; then
    echo "FAIL: plan 不存在（.dsh/growth/plan.md 或 .cursorGrowth/plan.md 或 DSH_GROWTH_PLAN）" >&2
    return 1
  fi
}

gate_check() {
  local reason
  if [[ -z "$PLAN" || ! -f "$PLAN" ]]; then
    echo "=== dsh-guard gate-check ==="
    echo "BLOCK: plan 不存在（.dsh/growth/plan.md 或 .cursorGrowth/plan.md 或 DSH_GROWTH_PLAN）"
    return 1
  fi
  reason="$(plan_gate_ok || true)"
  echo "=== dsh-guard gate-check ==="
  echo "plan: $PLAN"
  case "$reason" in
    OK)
      echo "OK: PLAN_APPROVED=$(plan_plan_approved) · SPRINT=$(plan_sprint) · ACTIVE=$(plan_active)"
      return 0
      ;;
    PLANNING)
      echo "BLOCK: PLANNING=true — 请先 sprint-plan 完成规划并设 PLANNING:false"
      return 1
      ;;
    NO_APPROVAL)
      echo "BLOCK: 无 PLAN_APPROVED — 请先 sprint-plan 确认规划并写入日期"
      return 1
      ;;
    *)
      echo "BLOCK: 未知闸门状态"
      return 1
      ;;
  esac
}

plan_check() {
  local issues=0 fails=0
  echo "=== dsh-guard plan-check ==="
  echo "plan: ${PLAN:-（未找到）}"
  if [[ -z "$PLAN" || ! -f "$PLAN" ]]; then
    echo "FAIL: plan 不存在"
    return 1
  fi
  if ! grep -q '| ⬜ |' "$PLAN" 2>/dev/null && ! grep -q '| 🔧 |' "$PLAN" 2>/dev/null \
    && ! grep -qE '\| ACTIVE \|' "$PLAN" 2>/dev/null; then
    if ! plan_sprint_appears_closed; then
      echo "WARN: 无活跃 ⬜/🔧/ACTIVE 任务"
      issues=$((issues + 1))
    fi
  fi
  if [[ -z "$(plan_active)" ]]; then
    if ! plan_sprint_appears_closed; then
      echo "WARN: <!-- ACTIVE --> 未设置且无 ACTIVE 表行"
      issues=$((issues + 1))
    fi
  fi
  if [[ -z "$(plan_sprint)" ]]; then
    echo "WARN: <!-- SPRINT --> 未设置"
    issues=$((issues + 1))
  fi
  if [[ "$(plan_sprint_status)" == "active" ]] && plan_sprint_goal_ritual_only; then
    echo "WARN: Sprint Goal 似仪式/出口动作（非能力交付）"
    echo "      Goal: $(plan_sprint_goal_text)"
    issues=$((issues + 1))
  fi
  if plan_planning; then
    echo "INFO: PLANNING=true — 仅 sprint-plan"
  elif [[ -z "$(plan_plan_approved)" ]]; then
    echo "FAIL: <!-- PLAN_APPROVED --> 未设置（run 硬闸门）"
    fails=$((fails + 1))
  fi
  if ! grep -qE '^\*\*(执行顺序|Order)\*\*' "$PLAN" 2>/dev/null; then
    echo "WARN: 缺 **执行顺序** 行（NEXT 回退靠表序）"
    issues=$((issues + 1))
  fi
  # A row whose field count differs from the header shifts every positional
  # column ($5 status · $6 acceptance · $7 target). The old check only looked for
  # *missing* columns (`NF < 8`), so one column *extra* — a bare `|` inside a
  # cell, e.g. `docs/en|zh` — passed as healthy while task-verify silently ran
  # the heuristic fallback instead of the acceptance. Hard FAIL: the acceptance
  # cell cannot be trusted once the columns moved.
  local shape_issues lineno task_id fields expected_cols
  expected_cols="$(plan_table_columns)"
  shape_issues="$(plan_table_shape_issues)"
  if [[ -n "$shape_issues" ]]; then
    while IFS=: read -r lineno task_id fields; do
      [[ -z "$lineno" ]] && continue
      echo "FAIL: TASK 表第 ${lineno} 行（${task_id}）字段数 ${fields} ≠ 表头 ${expected_cols}"
      echo "      单元格里可能混进了裸 | —— 改用 {en,zh} 这类写法；列错位会让验收格不可信"
      fails=$((fails + 1))
    done <<<"$shape_issues"
  fi
  if plan_sprint_appears_closed; then
    local unchecked pending_tasks
    unchecked="$(plan_done_when_unchecked)"
    if [[ "${unchecked:-0}" -gt 0 ]]; then
      echo "WARN: Sprint 已闭合但 Done when 仍有 ${unchecked} 项未 [x]"
      issues=$((issues + 1))
    fi
    if [[ "$(plan_sprint_status)" != "closed" ]]; then
      echo "WARN: <!-- SPRINT_STATUS --> 未设 closed"
      issues=$((issues + 1))
    fi
    pending_tasks="$(grep -cE '\| ⬜ \|' "$PLAN" 2>/dev/null || true)"
    pending_tasks="${pending_tasks:-0}"
    if [[ "$pending_tasks" -gt 0 ]]; then
      echo "WARN: Sprint 已闭合但 TASK 表仍有 ${pending_tasks} 行 ⬜"
      issues=$((issues + 1))
    fi
  fi
  local vmeta vpath
  vmeta="$(plan_verify)"
  if [[ "$vmeta" == *"dsh-guard"* && "$vmeta" == *"verify"* ]]; then
    echo "FAIL: <!-- VERIFY --> 不得为 dsh-guard verify（无限递归）；应写 pnpm run verify 或 ./scripts/verify-planrun.sh"
    fails=$((fails + 1))
  elif [[ "$vmeta" != *" "* && "$vmeta" == ./* ]]; then
    vpath="${vmeta#./}"
    if [[ ! -f "$ROOT/$vpath" ]]; then
      echo "WARN: VERIFY 脚本不存在: $vmeta"
      issues=$((issues + 1))
    fi
  fi
  # `plan-check` is the documented handoff gate (run skill, install docs), so a
  # hard FAIL must be non-zero. WARN stays advisory so a healthy-but-untidy plan
  # can still hand off.
  if [[ "$fails" -eq 0 && "$issues" -eq 0 ]]; then
    echo "OK: handoff 就绪"
    return 0
  fi
  echo "CHECK: ${fails} 项阻断 · ${issues} 项待补齐"
  [[ "$fails" -eq 0 ]]
}

run_fallback_verify() {
  local script="${FALLBACK_VERIFY#./}"
  if [[ -f "$ROOT/$script" ]]; then
    echo "==> heuristics fallback: $FALLBACK_VERIFY"
    cd "$ROOT"
    "$BASH_BIN" "$script"
    return $?
  fi
  local verify_cmd
  verify_cmd="$(plan_verify)"
  if [[ -n "$verify_cmd" && "$verify_cmd" != "$FALLBACK_VERIFY" ]]; then
    echo "==> heuristics fallback: $verify_cmd"
    cd "$ROOT"
    # shellcheck disable=SC2086
    eval "$verify_cmd"
    return $?
  fi
  # 2 = nothing to run, distinct from 1 = a fallback ran and failed.
  return 2
}

# The template writes acceptance commands wrapped in backticks (`` `pnpm run
# verify` ``), which never matched the raw-command prefix below and silently
# fell through to the heuristic fallback.
strip_backticks() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ ${#value} -ge 2 && "$value" == '`'*'`' ]]; then
    value="${value#\`}"
    value="${value%\`}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
  fi
  printf '%s' "$value"
}

run_acceptance() {
  local command="$1"
  if [[ "$EXEC_ENABLED" != "true" ]]; then
    echo "SKIP: DSH_GUARD_EXEC=$EXEC_ENABLED — 不执行验收命令: $command"
    return 0
  fi
  echo "==> Running acceptance command: $command"
  cd "$ROOT"
  # shellcheck disable=SC2086
  eval "$command"
}

task_verify() {
  local id="${1:-$(plan_active)}"
  local acc loc acc_cmd rc
  if [[ -z "$PLAN" || ! -f "$PLAN" ]]; then
    echo "FAIL: plan 不存在" >&2
    return 1
  fi
  if [[ -z "$id" || "$id" == "(none)" ]]; then
    echo "FAIL: 无 ACTIVE 任务 ID" >&2
    return 1
  fi
  echo "=== dsh-guard task-verify: ${id} ==="
  echo "plan: $PLAN"
  # A missing row used to abort the whole guard with exit 1 and zero output,
  # because the lookup pipeline ran under `set -euo pipefail`.
  if ! plan_task_has_row "$id"; then
    echo "FAIL: plan 里没有 ${id} 这一行（检查 <!-- ACTIVE --> / NEXT 是否与表格一致）" >&2
    return 1
  fi
  # Fail closed on a shifted row. Reading $6 positionally would hand back the
  # status cell as the acceptance, fail the executable-command test, and drop
  # through to the heuristic fallback — reporting "verified" for an acceptance
  # that never ran (exactly what a bare `|` inside a cell did in SPRINT-01).
  local shape_issue
  shape_issue="$(plan_table_shape_issues | awk -F: -v id="$id" '$2 == id { print; exit }')"
  if [[ -n "$shape_issue" ]]; then
    echo "FAIL: ${id} 所在行字段数与表头不符（${shape_issue}）—— TASK 表列已错位，验收格不可信" >&2
    echo "      单元格里可能混进了裸 |（改用 {en,zh} 这类写法）；修好再跑 —— 不回退到启发式验证" >&2
    return 1
  fi
  acc="$(plan_task_acceptance "$id")"
  loc="$(plan_task_landing "$id")"
  echo "验收: ${acc}"
  echo "落点: ${loc}"

  acc_cmd="$(strip_backticks "$acc")"
  if [[ "$acc_cmd" =~ ^(\./|cd |npm |pnpm |npx |pytest |grep |cargo |go test|make |bash ) ]]; then
    run_acceptance "$acc_cmd"
    return $?
  fi

  if [[ "$HEURISTICS_ENABLED" != "true" ]]; then
    echo "SKIP: heuristics disabled — run acceptance command in plan or verify manually"
    return 0
  fi

  # A failing fallback verify used to be swallowed and reported as SKIP/exit 0,
  # which turned "verify never ran" into "verify passed".
  if run_fallback_verify; then
    return 0
  else
    rc=$?
  fi
  if [[ "$rc" -eq 2 ]]; then
    echo "SKIP: 验收列为描述性文字，且没有可跑的回退脚本；请 Agent 按列手动执行"
    echo "TIP: plan 验收列优先写 pnpm run verify / bash scripts/... 等可执行命令"
    return 0
  fi
  echo "FAIL: 回退校验失败（exit ${rc}）—— 验收未通过" >&2
  return "$rc"
}

print_status() {
  echo "=== dsh-guard status ==="
  echo "plan: ${PLAN:-（未找到）}"
  if [[ -z "$PLAN" || ! -f "$PLAN" ]]; then
    return 1
  fi
  echo "PLANNING:   $(plan_meta PLANNING || echo false)"
  echo "SPRINT:     $(plan_sprint || echo '(none)')"
  echo "APPROVED:   $(plan_plan_approved || echo '(none)')"
  echo "AUTONOMOUS: $(plan_meta AUTONOMOUS || echo false)"
  echo "ACTIVE:     $(plan_active || echo '(none)')"
  local active
  active="$(plan_active)"
  if [[ -n "$active" && "$active" != "(none)" ]]; then
    echo "STATUS:     $(plan_task_status "$active")"
    echo "ACCEPTANCE: $(plan_task_acceptance "$active")"
    echo "NEXT_TASK:  $(plan_next_task)"
  fi
  echo "VERIFY:     $(plan_verify)"
  echo "PENDING:    $(plan_pending_count) tasks"
  local gate
  gate="$(plan_gate_ok || true)"
  echo "GATE:       ${gate}"
}

run_verify() {
  local verify_cmd
  verify_cmd="$(plan_verify)"
  if [[ "$verify_cmd" == *"dsh-guard"* && "$verify_cmd" == *"verify"* ]]; then
    verify_cmd="$FALLBACK_VERIFY"
  fi
  if [[ "$EXEC_ENABLED" != "true" ]]; then
    echo "SKIP: DSH_GUARD_EXEC=$EXEC_ENABLED — 不执行 VERIFY: $verify_cmd"
    return 0
  fi
  echo "==> Full VERIFY: $verify_cmd"
  cd "$ROOT"
  # shellcheck disable=SC2086
  eval "$verify_cmd"
}

guard_doctor() {
  # `doctor` lives in Node, not bash: it hashes files, parses JSON and scans
  # node_modules — all portable there, all painful in POSIX shell.
  local module="$ROOT/scripts/planrun-doctor.mjs"
  if [[ ! -f "$module" ]]; then
    echo "FAIL: 缺少 $module —— 重跑 install-planrun.sh --here 补齐 planrun-doctor.mjs / planrun-manifest.mjs" >&2
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "FAIL: doctor 需要 node" >&2
    return 2
  fi
  # --project first so an explicit user flag (parsed later) still wins.
  node "$module" --project "$ROOT" "$@"
}

case "$cmd" in
  status)
    print_status
    ;;
  verify)
    run_verify
    ;;
  task-verify)
    task_verify "${2:-}"
    ;;
  gate-check)
    gate_check
    ;;
  next-task)
    require_plan || exit 1
    plan_next_task
    ;;
  active)
    require_plan || exit 1
    plan_active
    ;;
  pending)
    require_plan || exit 1
    plan_pending_count
    ;;
  doctor)
    shift
    guard_doctor "$@"
    ;;
  plan-check)
    plan_check
    ;;
  help|-h|--help)
    cat <<EOF
用法: $0 [status|gate-check|task-verify|verify|plan-check|next-task|doctor|...]

  status        Sprint 状态（默认）
  gate-check    run 硬闸门（PLANNING / PLAN_APPROVED）
  task-verify   任务级验收（优先验收列；可传 TASK_ID）
  verify        全量 VERIFY（打版前 / P0 闭合）
  plan-check    plan handoff 结构检查
  next-task     按执行顺序解析下一 ⬜ ID
  doctor        版本漂移体检（guard 脚本 · 模板 schema · 包版本 · 清单）
  active        当前 ACTIVE 任务 ID
  pending       待办 ⬜ 数量

Plan 路径（优先级）:
  1. 环境变量 DSH_GROWTH_PLAN
  2. .dsh/growth/plan.md（目标项目）
  3. .cursorGrowth/plan.md（母版仓开发）

环境变量:
  DSH_GROWTH_PLAN          显式 plan 路径
  DSH_GUARD_HEURISTICS     true（默认）| false
  DSH_GUARD_FALLBACK_VERIFY  描述性验收回退脚本（默认 ./scripts/verify-planrun.sh）
  DSH_GUARD_EXEC           true（默认）| false；false 时只打印验收/VERIFY 命令而不执行
EOF
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
