#!/usr/bin/env bash
# Parse plan.md — hooks + runner.sh
set -euo pipefail

PLAN_FILE="${1:-plan.md}"
SC_SKIP_PREFIXES="${SC_SKIP_PREFIXES:-REV- SPIKE- DOC-}"

plan_id_should_skip() {
  local id="$1" prefix
  for prefix in $SC_SKIP_PREFIXES; do
    [[ "$id" == "$prefix"* ]] && return 0
  done
  return 1
}

plan_meta() {
  local key="$1"
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo ""
    return 0
  fi
  grep -E "<!-- ${key}:" "$PLAN_FILE" 2>/dev/null | head -1 | sed -E "s/.*<!-- ${key}:[[:space:]]*([^>]+)[[:space:]]*-->.*/\1/" | sed 's/[[:space:]]*$//' || true
}

# 元数据取值：模板占位 (none)/null 视为「未设置」，返回空串
plan_meta_value() {
  local v
  v="$(plan_meta "${1:-}")"
  case "$v" in
    ""|"(none)"|"null"|"None"|"NULL"|"-") return 0 ;;
  esac
  echo "$v"
}

plan_pending_count() {
  grep -c '| ⬜ |' "$PLAN_FILE" 2>/dev/null || echo "0"
}

plan_active() {
  plan_meta_value "ACTIVE"
}

plan_verify() {
  local v
  v="$(plan_meta "VERIFY")"
  if [[ -n "$v" ]]; then
    echo "$v"
  else
    echo "./scripts/verify.sh"
  fi
}

plan_autonomous() {
  local a
  a="$(plan_meta "AUTONOMOUS")"
  [[ "$a" == "true" ]]
}

plan_planning() {
  local p
  p="$(plan_meta "PLANNING")"
  [[ "$p" == "true" ]]
}

plan_sprint() {
  plan_meta_value "SPRINT"
}

# Active Sprint **Goal** 行正文（启发式 · 首条 **Goal**）
plan_sprint_goal_text() {
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo ""
    return 0
  fi
  grep -E '^\*\*Goal\*\*' "$PLAN_FILE" 2>/dev/null | head -1 | sed -E 's/^\*\*Goal\*\*[:：][[:space:]]*//' | sed 's/[[:space:]]*$//' || true
}

# Goal 是否似「仪式/出口」而非能力交付（供 plan-check WARN）
plan_sprint_goal_ritual_only() {
  local goal lower
  goal="$(plan_sprint_goal_text)"
  [[ -z "$goal" ]] && return 1
  lower="$(printf '%s' "$goal" | tr '[:upper:]' '[:lower:]')"
  if ! printf '%s' "$lower" | grep -qiE '(打版|发版|release|打[[:space:]]*tag|打tag|merge|合并|开[[:space:]]*pr|changelog|归档|verify|验收|commit|提交|push|发版)'; then
    return 1
  fi
  if printf '%s' "$lower" | grep -qiE '(实现|模块|功能|接入|引擎|插件|重构|迁移|交付|mvp|api|服务|client|skill|tts|long|架构|接口)'; then
    return 1
  fi
  return 0
}

plan_plan_approved() {
  plan_meta_value "PLAN_APPROVED"
}

plan_max_loops() {
  local m
  m="$(plan_meta "MAX_LOOPS")"
  if [[ -n "$m" ]]; then
    echo "$m"
  else
    echo "15"
  fi
}

# 任务表字段：验收=第6列 · 落点=第7列
# 未命中时返回空串且不因 pipefail 向上传播失败（调用方多为 set -e 的 hooks）
plan_task_row_field() {
  local id="$1"
  local col="$2"
  { grep -E "\| \*\*${id}\*\* \||\| ${id} \|" "$PLAN_FILE" 2>/dev/null | head -1 | awk -F'|' -v c="$col" '{
    gsub(/^[ \t]+|[ \t]+$/, "", $c);
    print $c;
  }'; } || true
}

plan_task_status() {
  plan_task_row_field "$1" 5
}

plan_task_acceptance() {
  plan_task_row_field "$1" 6
}

plan_task_landing() {
  plan_task_row_field "$1" 7
}

plan_last_done() {
  plan_meta_value "LAST_DONE"
}

plan_sprint_status() {
  plan_meta "SPRINT_STATUS"
}

# Sprint 是否已闭合（元数据或 ACTIVE 空且 LAST_DONE 有值）
plan_sprint_appears_closed() {
  local active last status
  status="$(plan_sprint_status)"
  [[ "$status" == "closed" ]] && return 0
  active="$(plan_active)"
  last="$(plan_last_done)"
  if [[ "$active" == "(none)" || -z "$active" ]]; then
    [[ -n "$last" && "$last" != "(none)" ]] && return 0
  fi
  return 1
}

# Done when 小节内未勾选项数
plan_done_when_unchecked() {
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "0"
    return 0
  fi
  awk '
    /^### Done when/ { in_done=1; next }
    /^### / && in_done { exit }
    in_done && /^- \[ \]/ { count++ }
    END { print count+0 }
  ' "$PLAN_FILE" 2>/dev/null || echo "0"
}

plan_next_meta() {
  plan_meta_value "NEXT"
}

# 短 ID / 片段 → 完整任务 ID
plan_resolve_task_id() {
  local token="$1"
  local sprint="$2"
  token="$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$token" ]] && return 0
  if [[ "$token" =~ ^P[0-9]+$ ]]; then
    echo ""
    return 0
  fi
  if [[ "$token" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
    echo "$token"
    return 0
  fi
  if [[ -n "$sprint" && "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
    echo "${sprint}-${token}"
    return 0
  fi
  echo "$token"
}

# 「执行顺序」行（兼容旧模板 **Order**）
plan_order_line() {
  grep -E '^\*\*(执行顺序|Order)\*\*' "$PLAN_FILE" 2>/dev/null | head -1 || true
}

plan_order_tokens() {
  local line="$1"
  echo "$line" | sed -E 's/^\*\*(执行顺序|Order)\*\*[：:][[:space:]]*//' \
    | tr '→' '\n' \
    | sed -E 's/`([^`]+)`/\1/g;s/^[[:space:]]+//;s/[[:space:]]+$//'
}

# 解析「执行顺序」行，返回下一待办 ID（锚点为刚完成的 ID）
plan_next_in_order() {
  local after_id="${1:-}"
  local sprint line token resolved status
  sprint="$(plan_sprint)"
  line="$(plan_order_line)"
  if [[ -z "$line" ]]; then
    plan_next_pending_id
    return 0
  fi
  local found=0
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    resolved="$(plan_resolve_task_id "$token" "$sprint")"
    [[ -z "$resolved" ]] && continue
    if [[ "$found" -eq 1 ]]; then
      status="$(plan_task_status "$resolved")"
      if [[ "$status" == "⬜" || "$status" == "🔧" ]]; then
        echo "$resolved"
        return 0
      fi
    fi
    if [[ "$resolved" == "$after_id" ]]; then
      found=1
    fi
  done < <(plan_order_tokens "$line")

  plan_next_pending_id
}

plan_next_pending_id() {
  local line id
  while IFS= read -r line; do
    id="$(echo "$line" | awk -F'|' '{gsub(/^[ \t*]+|[ \t*]+$/, "", $2); print $2}')"
    [[ -z "$id" ]] && continue
    plan_id_should_skip "$id" && continue
    echo "$id"
    return 0
  done < <(grep '| ⬜ |' "$PLAN_FILE" 2>/dev/null || true)
  echo ""
}

# NEXT 元数据 → 执行顺序 → 首个 ⬜
plan_next_task() {
  local next meta anchor status
  meta="$(plan_next_meta)"
  if [[ -n "$meta" ]]; then
    status="$(plan_task_status "$meta")"
    if [[ "$status" == "⬜" || "$status" == "🔧" ]]; then
      echo "$meta"
      return 0
    fi
  fi
  anchor="$(plan_active)"
  if [[ -z "$anchor" ]]; then
    anchor="$(plan_last_done)"
  fi
  if [[ -n "$anchor" ]]; then
    status="$(plan_task_status "$anchor")"
    if [[ "$status" == "✅" ]]; then
      plan_next_in_order "$anchor"
      return 0
    fi
  fi
  line="$(grep -E '建议下一项 \*\*[A-Z0-9-]+\*\*' "$PLAN_FILE" 2>/dev/null | head -1 || true)"
  if [[ -n "$line" ]]; then
    next="$(echo "$line" | sed -nE 's/.*\*\*([A-Z][A-Z0-9-]+)\*\*.*/\1/p' | head -1)"
    if [[ -n "$next" ]]; then
      echo "$next"
      return 0
    fi
  fi
  plan_next_pending_id
}

# run 启动硬闸门
plan_gate_ok() {
  if plan_planning; then
    echo "PLANNING"
    return 1
  fi
  if [[ -z "$(plan_plan_approved)" ]]; then
    echo "NO_APPROVAL"
    return 1
  fi
  echo "OK"
  return 0
}

# ROADMAP 是否仍有未立项大项（表内非「已闭合」「延后」行）
plan_roadmap_open() {
  local n
  n="$(
    sed -n '/^## ROADMAP/,/^## 变更记录/p' "$PLAN_FILE" 2>/dev/null \
      | grep -E '^\|' \
      | grep -vE '^\|[- ]*主题|^\|[-]+' \
      | grep -cvE '已闭合|延后' || true
  )"
  echo "${n:-0}"
}
