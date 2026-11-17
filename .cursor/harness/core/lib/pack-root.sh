#!/usr/bin/env bash
# Pack 根解析 —— 兼容两种脚本入口：
#   .cursor/bin/<script>                 符号链接入口（CI / 正常检出）
#   .cursor/harness/core/bin/<script>    真实入口（Windows core.symlinks=false 时必须走这里）
#
# 为什么需要：Windows 无符号链接权限时，`.cursor/bin` 等会被检出为**文本指针**，
# 直接 `bash .cursor/bin/x.sh` 会报 Not a directory，`source "$CUR/lib/..."` 也随之失效。
#
# 用法（脚本顶部，source 前不得依赖 $CUR）：
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"
#
# 产出变量：
#   CURSOR_DIR  .cursor pack 根
#   CUR         harness/core 目录（legacy 扁平 pack 时同 CURSOR_DIR）
#   ROOT        pack 的父目录（母版 / 安装项目的仓库根）

_sc_pack_root_from() {
  local w
  w="$(cd "$1" && pwd)"
  while [[ "$w" != "/" ]]; do
    if [[ -d "$w/harness/core" ]]; then
      echo "$w"
      return 0
    fi
    # legacy 扁平 pack / 已安装的工具根（.cursor · .zcode · .workbuddy …）：
    # 同时具备 config/workflow.json + rules + bin，且自身不是 harness/core 分区
    if [[ -f "$w/config/workflow.json" && -d "$w/rules" && -d "$w/bin" \
      && "$(basename "$(dirname "$w")")" != "harness" ]]; then
      echo "$w"
      return 0
    fi
    w="$(dirname "$w")"
  done
  return 1
}

CURSOR_DIR="$(_sc_pack_root_from "$(dirname "${BASH_SOURCE[0]}")")" || CURSOR_DIR=""
if [[ -z "$CURSOR_DIR" ]]; then
  echo "FAIL: cannot find .cursor pack root (harness/core or hooks.json+rules)" >&2
  exit 1
fi
ROOT="$(cd "$CURSOR_DIR/.." && pwd)"
if [[ -d "$CURSOR_DIR/harness/core" ]]; then
  CUR="$CURSOR_DIR/harness/core"
else
  CUR="$CURSOR_DIR"
fi
