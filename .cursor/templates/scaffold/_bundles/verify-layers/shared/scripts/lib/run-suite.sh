#!/usr/bin/env bash
# Serial or parallel runner for independent verify slices.

run_suite() {
  local mode="$1"
  shift
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  if [[ "$mode" == "serial" ]]; then
    local script
    for script in "$@"; do
      bash "$script"
    done
    return 0
  fi

  if [[ "$mode" == "parallel" ]]; then
    local -a pids=()
    local -a scripts=()
    local logdir
    logdir="$(mktemp -d)"
    local script base
    for script in "$@"; do
      base="$(basename "$script")"
      scripts+=("$base")
      bash "$script" >"$logdir/$base.log" 2>&1 &
      pids+=("$!")
    done
    local failed=0
    local i pid
    for i in "${!pids[@]}"; do
      pid="${pids[$i]}"
      base="${scripts[$i]}"
      if ! wait "$pid"; then
        echo "=== FAILED: $base ===" >&2
        sed "s/^/[$base] /" "$logdir/$base.log" >&2
        failed=1
      fi
    done
    rm -rf "$logdir"
    return "$failed"
  fi

  echo "run_suite: unknown mode '$mode' (use serial|parallel)" >&2
  return 1
}
