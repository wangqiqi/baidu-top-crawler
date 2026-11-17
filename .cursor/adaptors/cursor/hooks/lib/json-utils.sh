#!/usr/bin/env bash
# Minimal JSON helpers — prefer jq, fallback python (hooks stdin JSON)
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_hooks_dir="$(cd "$_LIB_DIR/.." && pwd)"
_w="$_hooks_dir"
while [[ "$_w" != "/" ]]; do
  if [[ -f "$_w/lib/platform.sh" && -d "$_w/hooks" ]]; then
    # shellcheck source=../../lib/platform.sh
    source "$_w/lib/platform.sh"
    break
  fi
  if [[ -f "$_w/harness/core/lib/platform.sh" ]]; then
    # shellcheck source=../../../../harness/core/lib/platform.sh
    source "$_w/harness/core/lib/platform.sh"
    break
  fi
  if [[ -f "$_w/lib/platform.sh" ]]; then
    # shellcheck source=../../lib/platform.sh
    source "$_w/lib/platform.sh"
    break
  fi
  _w="$(dirname "$_w")"
done

_json_py() {
  sc_python 2>/dev/null || true
}

json_get() {
  local json="$1"
  local key="$2"
  local py
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r ".${key} // empty" 2>/dev/null || true
    return 0
  fi
  if py="$(_json_py)" && [[ -n "$py" ]]; then
    "$py" -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2],""))' "$json" "$key" 2>/dev/null || true
    return 0
  fi
  echo ""
}

json_workspace_root() {
  local json="$1"
  local py
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.workspace_roots[0] // empty' 2>/dev/null || true
    return 0
  fi
  if py="$(_json_py)" && [[ -n "$py" ]]; then
    "$py" -c 'import json,sys; d=json.loads(sys.argv[1]); r=d.get("workspace_roots") or []; print(r[0] if r else "")' "$json" 2>/dev/null || true
    return 0
  fi
  echo ""
}

json_string() {
  local text="$1"
  local py
  # 必须 printf（而非 here-string `<<<`）：here-string 会附送尾换行，
  # 让 JSON 字符串值凭空多一个 "\n"（2026-10-14 修）
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$text" | jq -Rs .
    return 0
  fi
  if py="$(_json_py)" && [[ -n "$py" ]]; then
    printf '%s' "$text" | "$py" -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    return 0
  fi
  echo '""'
}

# json_string 返回含外层引号的 JSON 字符串；这里取「可安全插入 JSON 模板」的内层文本，
# 供手写 heredoc 的调用方使用（裸插值遇引号/换行即写坏 JSON）
json_escape_text() {
  local s
  s="$(json_string "$1")"
  printf '%s' "${s:1:${#s}-2}"
}

json_additional_context() {
  local text="$1"
  echo "{\"additional_context\": $(json_string "$text")}"
}

json_followup() {
  local text="$1"
  echo "{\"followup_message\": $(json_string "$text")}"
}
