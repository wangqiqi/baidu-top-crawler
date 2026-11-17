#!/usr/bin/env bash
# Idempotent project-root onekey_start.sh from Super Cursor template.
[[ -n "${SC_ONEKEY_BOOTSTRAP_LOADED:-}" ]] && return 0
SC_ONEKEY_BOOTSTRAP_LOADED=1

# sc_bootstrap_onekey_start <project_root> <cursor_dir> <enabled>
# enabled: true|false|1|0 (default true)
sc_bootstrap_onekey_start() {
  local project_root="$1"
  local cursor_dir="$2"
  local enabled="${3:-true}"

  case "$enabled" in
    false|0|no|NO|False) return 0 ;;
  esac

  [[ -n "$project_root" && -d "$project_root" ]] || return 0
  [[ -n "$cursor_dir" ]] || return 0

  local dest="$project_root/onekey_start.sh"
  if [[ -f "$dest" ]]; then
    return 0
  fi

  local tpl="" base
  for base in \
    "$cursor_dir" \
    "${SC_PROJECT_ROOT:+$SC_PROJECT_ROOT/.cursor}" \
    "${SC_HOOK_CURSOR_DIR:-}"; do
    [[ -z "$base" ]] && continue
    if [[ -f "$base/templates/project-onekey/onekey_start.sh" ]]; then
      tpl="$base/templates/project-onekey/onekey_start.sh"
      break
    fi
  done
  if [[ ! -f "$tpl" ]]; then
    return 0
  fi

  cp "$tpl" "$dest"
  chmod +x "$dest" 2>/dev/null || true
}
