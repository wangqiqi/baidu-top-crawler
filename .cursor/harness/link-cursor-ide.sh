#!/usr/bin/env bash
# Cursor / Roo 协议路径：在 pack 根创建相对符号链接 → harness/core + adaptors/cursor（无文件复制）。
# 母版与 install 目标共用同一分区树；拷贝整个 .cursor/ 即可迁移（保留 symlink）。
set -euo pipefail

PACK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE="$PACK/harness/core"
ADAPTOR="$PACK/adaptors/cursor"

if [[ ! -d "$CORE" ]]; then
  echo "FAIL: missing $CORE" >&2
  exit 1
fi

link_rel() {
  local name="$1" target="$2"
  local path="$PACK/$name"
  if [[ -L "$path" ]]; then
    local cur
    cur="$(readlink "$path")"
    # 已是正确的相对符号链接 → 跳过
    [[ "$cur" == "$target" ]] && return 0
    rm -f "$path"
  elif [[ -e "$path" && ! -L "$path" ]]; then
    # 重装 / Windows 降级副本（目录或普通文件）→ 先移除再补链
    rm -rf "$path"
  fi
  # 优先建相对符号链接（无复制、迁移友好）
  if ln -sfn "$target" "$path" 2>/dev/null; then
    return 0
  fi
  # 回退：无法建符号链接（如 Windows core.symlinks=false）时复制实体，保证本地可用
  echo "WARN: 无法创建符号链接 ${name}，回退为复制实体（建议 Windows 设 git config core.symlinks true 后重克隆）" >&2
  rm -rf "$path"
  if [[ -d "$PACK/$target" ]]; then
    # 复制目录「内容」到 path，避免 cp -R 把源目录整体塞成 path/<basename> 嵌套
    mkdir -p "$path"
    cp -R "$PACK/$target/." "$path/"
  else
    cp "$PACK/$target" "$path"
  fi
}

link_rel agents harness/core/agents
link_rel bin harness/core/bin
link_rel config harness/core/config
link_rel lib harness/core/lib
link_rel rules harness/core/rules
link_rel skills harness/core/skills
link_rel templates harness/core/templates
link_rel AGENTS.md harness/core/AGENTS.md
link_rel README.md harness/core/README.md
link_rel verify-super-cursor.sh harness/core/verify-super-cursor.sh
link_rel verify-system.sh harness/core/verify-system.sh

if [[ -d "$ADAPTOR" ]]; then
  link_rel hooks adaptors/cursor/hooks
  link_rel hooks.json adaptors/cursor/hooks.json
fi

# shellcheck source=core/lib/platform.sh
source "$CORE/lib/platform.sh"
sc_chmod_scripts "$PACK"
echo "OK: IDE protocol links → harness/core + adaptors/cursor (no copy)"
