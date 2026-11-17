#!/usr/bin/env bash
# Smoke fixtures: git init with LF policy (Windows CI / Git for Windows).
#
# Usage:
#   source "$CURSOR_DIR/lib/smoke-git.sh"
#   sc_smoke_git_init_repo /path/to/project [/path/to/mother-repo]
sc_smoke_git_init_repo() {
  local dir="$1"
  local mother="${2:-}"
  if [[ -z "$mother" ]]; then
    mother="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  (
    cd "$dir"
    git init -q
    git config core.autocrlf false
    git config core.safecrlf false
    git config core.eol lf
    if [[ -f "$mother/.gitattributes" ]]; then
      cp "$mother/.gitattributes" .gitattributes
    fi
  )
}
