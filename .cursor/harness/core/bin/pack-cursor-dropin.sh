#!/usr/bin/env bash
# 打包「仅 .cursor」拖放包：解压到任意项目根即可被 Cursor IDE 加载（与 install --replace 产物一致）。
set -euo pipefail

usage() {
  cat <<EOF
用法: $0 [母版仓库根] [选项]

产出（默认）: <母版>/.growing/offline-dist/super-cursor-dropin-<version>-<time>.tar.gz
  解压: tar -xzf <包> -C /path/to/your-project
  得到: your-project/.cursor/ + DROPIN-README.md

选项:
  --output-dir <dir>    覆盖产出目录
  --name <basename>     覆盖包文件名（不含 .tar.gz）
  --profile full|lite|rules-only   传给 install（默认 full）
  --skills-bundle full|core        传给 install（默认 full）
  -h, --help

入口: bash install-super-cursor.sh --pack-dropin [选项]
EOF
}

resolve_mother() {
  local arg="${1:-}"
  if [[ -n "$arg" && "$arg" != -* && -d "$arg/.cursor/harness/core" ]]; then
    echo "$(cd "$arg" && pwd)"
    return 0
  fi
  local c
  for c in "${SUPER_CURSOR_HOME:-}" "${CURSOR_AI_HOME:-}"; do
    [[ -n "$c" && -d "$c/.cursor/harness/core" ]] && { echo "$(cd "$c" && pwd)"; return 0; }
  done
  local walk
  walk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$walk" != "/" ]]; do
    if [[ -d "$walk/harness/core" ]]; then
      echo "$(cd "$walk/.." && pwd)"
      return 0
    fi
    walk="$(dirname "$walk")"
  done
  echo "错误: 未找到母版 .cursor/harness/core" >&2
  return 1
}

MOTHER=""
OUTPUT_DIR=""
NAME_OVERRIDE=""
PROFILE="full"
SKILLS_BUNDLE="full"

args=("$@")
if [[ ${#args[@]} -gt 0 && "${args[0]}" != -* ]]; then
  MOTHER="$(resolve_mother "${args[0]}")" || exit 1
  set -- "${args[@]:1}"
else
  MOTHER="$(resolve_mother "")" || exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "错误: --output-dir 需要路径" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || { echo "错误: --name 需要 basename" >&2; exit 1; }
      NAME_OVERRIDE="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --skills-bundle)
      SKILLS_BUNDLE="$2"
      shift 2
      ;;
    *)
      echo "错误: 未知选项 $1" >&2
      usage
      exit 1
      ;;
  esac
done

INSTALL="$MOTHER/install-super-cursor.sh"
[[ -x "$INSTALL" ]] || INSTALL="$MOTHER/install-super-cursor.sh"

# shellcheck source=../lib/platform.sh
source "$MOTHER/.cursor/harness/core/lib/platform.sh"

VER="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$MOTHER/CHANGELOG.md" 2>/dev/null | grep -v Unreleased | head -1)"
VER="${VER:-0.0.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
BASE="${NAME_OVERRIDE:-super-cursor-dropin-${VER}-${STAMP}}"
OUT="${OUTPUT_DIR:-$MOTHER/.growing/offline-dist}"
mkdir -p "$OUT"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/sc-dropin.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
PROJECT="$STAGING/project"
mkdir -p "$PROJECT"

echo "==> staging install (profile=$PROFILE skills-bundle=$SKILLS_BUNDLE)"
bash "$INSTALL" "$PROJECT" --replace --profile "$PROFILE" --skills-bundle "$SKILLS_BUNDLE"

VERIFY="$MOTHER/.cursor/harness/core/bin/verify-cursor-dropin.sh"
[[ -f "$VERIFY" ]] || VERIFY="$MOTHER/.cursor/bin/verify-cursor-dropin.sh"
bash "$VERIFY" "$PROJECT"

cat >"$PROJECT/DROPIN-README.md" <<EOF
# Super Cursor · .cursor 拖放包

| 项 | 值 |
|----|-----|
| 版本 | ${VER} |
| profile | ${PROFILE} |
| skills-bundle | ${SKILLS_BUNDLE} |
| 打包时间 | ${STAMP} |

## 用法（任意 Cursor 项目）

\`\`\`bash
tar -xzf ${BASE}.tar.gz -C /path/to/your-project
\`\`\`

解压后项目根应有 \`.cursor/rules\`、\`.cursor/skills\`、\`.cursor/hooks.json\`。  
在 Cursor 中 **Reload Window**。

## 与完整 install 的区别

| 拖放包 | \`install-super-cursor.sh\` |
|--------|------------------------------|
| 只含 \`.cursor/\` + 本说明 | 另建 \`.growing/\`、合并 \`.gitignore\`、可选 adaptor |
| 适合快速试规则 | 适合长期团队仓库 |

要完整工作流：\`bash install-super-cursor.sh /path/to/project --replace --copy-plan\`

校验：\`bash .cursor/bin/verify-cursor-dropin.sh /path/to/project\`
EOF

ARCHIVE="$OUT/${BASE}.tar.gz"
if [[ -f "$ARCHIVE" ]]; then
  rm -f "$ARCHIVE"
fi

if command -v tar >/dev/null 2>&1; then
  tar -czf "$ARCHIVE" -C "$PROJECT" .cursor DROPIN-README.md
else
  echo "错误: 需要 tar 打 zip 包" >&2
  exit 1
fi

echo "OK  dropin pack: $ARCHIVE"
echo "     unpack: tar -xzf $(basename "$ARCHIVE") -C <your-project-root>"
