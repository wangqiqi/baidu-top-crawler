#!/usr/bin/env bash
# 母版 smoke / verify 临时目录：统一前缀 + EXIT 回收（避免 /tmp 无标识堆积）
#
# 用法:
#   source 本文件
#   sc_temp_trap_cleanup
#   sc_mktemp_dir my-label    # 勿用 $(sc_mktemp_dir …) — 子 shell 会丢登记
#   path="$SC_MKTEMP_LAST"
sc_temp_dirs=()
sc_temp_files=()
SC_MKTEMP_LAST=""

sc_mktemp_dir() {
  local label="${1:-sc-cursor}"
  label="${label//\//-}"
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/${label}.XXXXXX")" || return 1
  sc_temp_dirs+=("$d")
  SC_MKTEMP_LAST="$d"
  return 0
}

sc_mktemp_file() {
  local label="${1:-sc-cursor}"
  label="${label//\//-}"
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/${label}.XXXXXX")" || return 1
  sc_temp_files+=("$f")
  SC_MKTEMP_LAST="$f"
  return 0
}

sc_temp_trap_cleanup() {
  trap 'sc_temp_cleanup_all' EXIT
}

sc_temp_cleanup_all() {
  local d f
  for d in ${sc_temp_dirs[@]+"${sc_temp_dirs[@]}"}; do
    [[ -n "$d" && -e "$d" ]] || continue
    rm -rf "$d" 2>/dev/null || true
  done
  for f in ${sc_temp_files[@]+"${sc_temp_files[@]}"}; do
    [[ -n "$f" && -e "$f" ]] || continue
    rm -f "$f" 2>/dev/null || true
  done
}
