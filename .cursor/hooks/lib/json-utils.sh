#!/usr/bin/env bash
# Minimal JSON helpers — prefer jq, fallback python (hooks stdin JSON)
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/platform.sh
source "$_LIB_DIR/../../lib/platform.sh"

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
  if command -v jq >/dev/null 2>&1; then
    jq -Rs . <<< "$text"
    return 0
  fi
  if py="$(_json_py)" && [[ -n "$py" ]]; then
    "$py" -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<< "$text"
    return 0
  fi
  echo '""'
}

json_additional_context() {
  local text="$1"
  echo "{\"additional_context\": $(json_string "$text")}"
}

json_followup() {
  local text="$1"
  echo "{\"followup_message\": $(json_string "$text")}"
}
