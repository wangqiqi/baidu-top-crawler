#!/usr/bin/env bash
# Resolve git/repo root from any adaptors/cursor/* script.
sc_adaptor_repo_root_from() {
  local start="${1:?}"
  local w="$start"
  while [[ "$w" != "/" ]]; do
    if [[ -f "$w/install-super-cursor.sh" ]]; then
      echo "$w"
      return 0
    fi
    w="$(dirname "$w")"
  done
  return 1
}
