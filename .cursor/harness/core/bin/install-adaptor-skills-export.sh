#!/usr/bin/env bash
# Install core_skills_export → .trae/skills/ (Trae adaptor).
set -euo pipefail

usage() {
  cat <<EOF
用法: $0 --adaptor trae <目标项目根> [选项]

将 harness/core/skills 导出到 .trae/skills/（见 adaptors/trae/docs/layout.md §Skills）。
只增量复制母版 skill，不删除消费方自有 skill。

选项:
  --skills-bundle full|core   默认 full（core 不含五工具 skill）
  --dry-run                   只打印源/目标
  -h, --help

环境: SUPER_CURSOR_HOME / CURSOR_AI_HOME
EOF
}

resolve_source_root() {
  local candidate _walk
  for candidate in "${SUPER_CURSOR_HOME:-}" "${CURSOR_AI_HOME:-}"; do
    if [[ -n "$candidate" && -d "$candidate/.cursor/harness/core" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  _walk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$_walk" != "/" ]]; do
    if [[ -d "$_walk/harness/core" ]]; then
      echo "$(cd "$_walk/.." && pwd)"
      return 0
    fi
    _walk="$(dirname "$_walk")"
  done
  echo "错误: 未找到母版 .cursor/harness/core" >&2
  return 1
}

ADAPTOR=""
TARGET=""
DRY_RUN="false"
SKILLS_BUNDLE="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --skills-bundle)
      [[ $# -ge 2 ]] || { echo "错误: --skills-bundle 需要取值" >&2; exit 1; }
      SKILLS_BUNDLE="$2"
      shift 2
      ;;
    --adaptor)
      [[ $# -ge 2 ]] || { echo "错误: --adaptor 需要 trae" >&2; exit 1; }
      ADAPTOR="$2"
      shift 2
      ;;
    -*)
      echo "错误: 未知选项 $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        echo "错误: 多余参数 $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -n "$ADAPTOR" ]] || { echo "错误: 需要 --adaptor trae" >&2; usage; exit 1; }
[[ -n "$TARGET" ]] || { echo "错误: 需要目标项目路径" >&2; usage; exit 1; }
case "$SKILLS_BUNDLE" in full|core) ;; *)
  echo "错误: 无效 skills-bundle: ${SKILLS_BUNDLE}（可选 full · core）" >&2
  exit 1
  ;;
esac

case "$ADAPTOR" in
  trae) INSTALL_DIR=".trae" ;;
  *)
    echo "错误: 无效 adaptor: ${ADAPTOR}（仅 trae 支持 skills 导出）" >&2
    exit 1
    ;;
esac

SOURCE="$(resolve_source_root)" || exit 1
PACK="$SOURCE/.cursor"
CORE_SRC="$PACK/harness/core"
SKILLS_SRC="$CORE_SRC/skills"
BUNDLE_CFG="$CORE_SRC/config/skill-bundles.json"
DEST="$TARGET/$INSTALL_DIR/skills"

[[ -d "$SKILLS_SRC" ]] || { echo "错误: 缺少 $SKILLS_SRC" >&2; exit 1; }

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN: skills $SKILLS_SRC -> $DEST (bundle=${SKILLS_BUNDLE}；不删除既有 skill)"
  exit 0
fi

# shellcheck source=../lib/platform.sh
source "$CORE_SRC/lib/platform.sh"

mkdir -p "$TARGET" "$DEST"
sc_copy_tree "$SKILLS_SRC" "$DEST"

# --skills-bundle core：按源侧 SSOT 剔除五工具 skill（导出不带 config/，故在源侧读取）
if [[ "$SKILLS_BUNDLE" != "full" ]]; then
  [[ -f "$BUNDLE_CFG" ]] || { echo "错误: 缺少 $BUNDLE_CFG" >&2; exit 1; }
  py="$(sc_python)" || { echo "错误: 需要 python 读取 skill-bundles.json" >&2; exit 1; }
  if ! excluded="$("$py" - "$BUNDLE_CFG" "$SKILLS_BUNDLE" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
bundle = sys.argv[2]
bundles = cfg.get("bundles") or {}
if bundle not in bundles:
    print(f"unknown bundle: {bundle}", file=sys.stderr)
    sys.exit(2)
for name in bundles[bundle].get("exclude_skills") or []:
    print(name)
PY
  )"; then
    echo "错误: skills bundle '$SKILLS_BUNDLE' 不在 $BUNDLE_CFG" >&2
    exit 1
  fi
  while IFS= read -r skill; do
    # Windows python stdout 为 CRLF：不剥尾 \r 则目录名匹配不上
    skill="${skill%$'\r'}"
    [[ -z "$skill" ]] && continue
    rm -rf "$DEST/$skill"
  done <<< "$excluded"
fi

echo "OK: core_skills_export 已安装 → $DEST ($ADAPTOR · bundle=$SKILLS_BUNDLE)"
