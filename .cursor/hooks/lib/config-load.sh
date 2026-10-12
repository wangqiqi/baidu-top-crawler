#!/usr/bin/env bash
# Load .cursor/config/workflow.json
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/platform.sh
source "$_LIB_DIR/../../lib/platform.sh"

SC_CONFIG="${SC_CONFIG:-}"
SC_PROJECT_ROOT="${SC_PROJECT_ROOT:-}"
SC_PLAN_REL="${SC_PLAN_REL:-.cursorGrowth/plan.md}"
SC_WORKFLOW_ENABLED="${SC_WORKFLOW_ENABLED:-true}"
SC_HOOKS_ENABLED="${SC_HOOKS_ENABLED:-true}"
SC_GROWTH_ENABLED="${SC_GROWTH_ENABLED:-false}"
SC_SKIP_PREFIXES="${SC_SKIP_PREFIXES:-REV- SPIKE- DOC-}"
SC_TASK_PREFIX="${SC_TASK_PREFIX:-TASK-}"
SC_HEURISTICS_ENABLED="${SC_HEURISTICS_ENABLED:-false}"

sc_resolve_project_root() {
  local hooks_dir="${1:-}"
  local root
  root="$(cd "${hooks_dir}/../.." && pwd)"
  if [[ -f "${root}/.cursor/config/workflow.json" ]]; then
    SC_PROJECT_ROOT="$root"
    return 0
  fi
  SC_PROJECT_ROOT="$(cd "${hooks_dir}/../../.." && pwd)"
}

sc_init_config() {
  local cursor_dir="$1"
  SC_CONFIG="${cursor_dir}/config/workflow.json"
  SC_PLAN_REL="$(sc_cfg '.plan_file' '.cursorGrowth/plan.md')"
  SC_WORKFLOW_ENABLED="$(sc_cfg '.workflow.enabled' 'true')"
  SC_HOOKS_ENABLED="$(sc_cfg '.workflow.hooks_enabled' 'true')"
  SC_GROWTH_ENABLED="$(sc_cfg '.growth.enabled' 'false')"
  SC_SKIP_PREFIXES="$(sc_cfg_join '.task_id.prefixes_skip' 'REV- SPIKE- DOC-')"
  SC_TASK_PREFIX="$(sc_cfg_first '.task_id.prefixes_autonomous' 'TASK-')"
  SC_HEURISTICS_ENABLED="$(sc_cfg '.task_verify_heuristics.enabled' 'false')"
}

sc_plan_path() {
  echo "${SC_PROJECT_ROOT}/${SC_PLAN_REL}"
}

sc_cfg() {
  local jqpath="$1"
  local default="$2"
  json_cfg "$SC_CONFIG" "${jqpath#.}" "$default"
}

sc_cfg_join() {
  local jqpath="$1"
  local default="$2"
  json_cfg_join "$SC_CONFIG" "${jqpath#.}" "$default"
}

sc_cfg_first() {
  local jqpath="$1"
  local default="$2"
  local val
  val="$(sc_cfg_join "$jqpath" "$default")"
  echo "${val%% *}"
}
