#!/usr/bin/env bash
# 项目 /tmp 契约清理 — 配置 SSOT：.growing/temp-cleanup.json（见 workflow.json temp_cleanup）
set -euo pipefail

usage() {
  cat <<'EOF'
用法: project-tmp-cleanup.sh --phase test|verify|task-verify|sweep [--root DIR] [--config PATH] [--dry-run]

无配置文件或 enabled=false 时静默退出 0。
EOF
}

CURSOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=platform.sh
source "$CURSOR_DIR/lib/platform.sh"

ROOT="."
CONFIG=""
PHASE=""
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$PHASE" ]] || { usage >&2; exit 2; }

ROOT="$(cd "$ROOT" && pwd)"
WF="$ROOT/.cursor/config/workflow.json"
if [[ -z "$CONFIG" && -f "$WF" ]]; then
  CONFIG="$(json_cfg "$WF" "temp_cleanup.config" ".growing/temp-cleanup.json")"
fi
[[ -n "$CONFIG" ]] || exit 0
[[ "$CONFIG" != /* ]] && CONFIG="$ROOT/$CONFIG"
[[ -f "$CONFIG" ]] || exit 0

enabled="$(json_cfg "$WF" "temp_cleanup.enabled" "true" 2>/dev/null || echo true)"
[[ "$enabled" == "true" ]] || exit 0

py="$(sc_python 2>/dev/null)" || { echo "[tmp-cleanup] SKIP: python 不可用" >&2; exit 0; }

args=(--config "$CONFIG" --phase "$PHASE" --root "$ROOT")
[[ "$DRY" -eq 1 ]] && args+=(--dry-run)

exec "$py" "$CURSOR_DIR/lib/project-tmp-cleanup.py" "${args[@]}"
