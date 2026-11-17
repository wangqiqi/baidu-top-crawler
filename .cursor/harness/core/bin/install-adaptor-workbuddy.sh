#!/usr/bin/env bash
# Install Harness Core into target/.workbuddy/ (adaptor workbuddy · includes: core).
set -euo pipefail

usage() {
  cat <<EOF
用法: $0 <目标项目根> [选项]

将母版 harness/core 写入 <目标>/.workbuddy/（见 adaptors/workbuddy/docs/layout.md）。

选项:
  --dry-run              只打印将拷贝的源/目标，不写磁盘
  --skills-bundle full|core   默认 full
  --profile full|lite|rules-only   合并 workflow profile（默认 full）
  -h, --help

环境: SUPER_CURSOR_HOME / CURSOR_AI_HOME（母版仓库根）
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

TARGET=""
DRY_RUN="false"
PROFILE="full"
SKILLS_BUNDLE="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "错误: --profile 需要取值" >&2; exit 1; }
      PROFILE="$2"
      shift 2
      ;;
    --skills-bundle)
      [[ $# -ge 2 ]] || { echo "错误: --skills-bundle 需要取值" >&2; exit 1; }
      SKILLS_BUNDLE="$2"
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

[[ -n "$TARGET" ]] || { echo "错误: 需要目标项目路径" >&2; usage; exit 1; }

case "$PROFILE" in full|lite|rules-only) ;; *)
  echo "错误: 无效 profile: $PROFILE" >&2; exit 1 ;;
esac
case "$SKILLS_BUNDLE" in full|core) ;; *)
  echo "错误: 无效 skills-bundle: $SKILLS_BUNDLE" >&2; exit 1 ;;
esac

SOURCE="$(resolve_source_root)" || exit 1
PACK="$SOURCE/.cursor"
CORE_SRC="$PACK/harness/core"
WB_README="$PACK/adaptors/workbuddy/README.md"

[[ -d "$CORE_SRC" ]] || { echo "错误: 缺少 $CORE_SRC" >&2; exit 1; }

# shellcheck source=../lib/platform.sh
source "$CORE_SRC/lib/platform.sh"

DEST="$TARGET/.workbuddy"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN: core $CORE_SRC -> $DEST"
  echo "DRY RUN: README $WB_README -> $DEST/README.md"
  echo "DRY RUN: skills-bundle=$SKILLS_BUNDLE profile=$PROFILE"
  exit 0
fi

mkdir -p "$TARGET"
mkdir -p "$DEST"

sc_copy_tree "$CORE_SRC" "$DEST" "rules/local"
if [[ -f "$WB_README" ]]; then
  cp -a "$WB_README" "$DEST/README.md"
fi

sc_apply_skills_bundle "$TARGET" "$SKILLS_BUNDLE" ".workbuddy" || exit 1

# WorkBuddy skill 识别需要 version / display_name / description_zh / description_en 等 frontmatter 字段；
# Super Cursor 的 SKILL.md 只有 name + description（部分含 Cursor 专属 disable-model-invocation）。
# 此处补全为 WorkBuddy 兼容 frontmatter，正文原样保留。缺 python 时跳过（skill 仍可用，只是缺元数据）。

# 版本号来源：优先 CHANGELOG 最新 `## [x.y.z]`，回退 git tag，再回退占位。
sc_resolve_version() {
  local changelog="$SOURCE/CHANGELOG.md"
  if [[ -f "$changelog" ]]; then
    local v
    v="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$changelog" | head -1)"
    [[ -n "$v" ]] && { echo "$v"; return 0; }
  fi
  if command -v git >/dev/null 2>&1; then
    local tag
    tag="$(git -C "$SOURCE" describe --tags --abbrev=0 2>/dev/null || true)"
    tag="${tag#v}"
    [[ -n "$tag" ]] && { echo "$tag"; return 0; }
  fi
  echo "1.0.0"
}

sc_adapt_workbuddy_frontmatter() {
  local skills_dir="$1" version="$2"
  local py
  py="$(sc_python)" || { echo "WARN: 无 python，跳过 .workbuddy skill frontmatter 补全" >&2; return 0; }
  SKILLS_DIR="$skills_dir" SC_SKILL_VERSION="$version" "$py" <<'PY'
import os, re, sys
from pathlib import Path

skills_dir = Path(os.environ["SKILLS_DIR"])
version = os.environ.get("SC_SKILL_VERSION", "1.0.0")

def parse_frontmatter(text: str):
    """返回 (fm_dict, body)。无 frontmatter 返回 (None, text)。"""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 3)
    if end == -1:
        return None, text
    fm_block = text[4:end]  # 去掉首行 '---\n'
    body = text[end + 4:]   # 去掉 '\n---'
    fm = {}
    lines = fm_block.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key = m.group(1)
        val = m.group(2).strip()
        # YAML 折叠标量：`key: >-` / `key: |` 等，续行为缩进内容
        if val in (">-", ">", "|-", "|"):
            folded = []
            i += 1
            while i < len(lines) and (lines[i].startswith("  ") or lines[i].strip() == ""):
                folded.append(lines[i].strip())
                i += 1
            fm[key] = " ".join(folded)
            continue
        fm[key] = val
        i += 1
    return fm, body

def fold_description(desc: str) -> str:
    """把 YAML 折叠标量 >- 或换行拼成单行。"""
    return " ".join(part.strip() for part in desc.splitlines() if part.strip())

for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
    name = skill_md.parent.name
    text = skill_md.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    if fm is None:
        continue
    desc_zh = fold_description(fm.get("description", ""))
    desc_en = fm.get("description_en", f"Super Cursor workflow skill '{name}'.")
    display_name = fm.get("display_name", name)
    # 重建 frontmatter：保留 name/description，补 version/display_name/描述双语，剔除 Cursor 专属字段
    lines = [
        "---",
        f"name: {fm.get('name', name)}",
        f"version: {version}",
        f"display_name: {display_name}",
        f"description: {desc_zh}",
        f"description_zh: {desc_zh}",
        f"description_en: {desc_en}",
        "---",
    ]
    # 保留原有额外字段（除 name/description/disable-model-invocation/version 之外）
    for k, v in fm.items():
        if k in ("name", "description", "disable-model-invocation", "version"):
            continue
        lines.append(f"{k}: {v}")
    skill_md.write_text("\n".join(lines) + "\n" + body.lstrip("\n"), encoding="utf-8")
print("OK: workbuddy frontmatter 已补全")
PY
}

sc_adapt_workbuddy_frontmatter "$DEST/skills" "$(sc_resolve_version)"

if sc_has_json_tool; then
  profile_file="$DEST/config/profiles/${PROFILE}.json"
  if [[ -f "$profile_file" ]]; then
    tmp="$(mktemp)"
    sc_json_merge_files "$DEST/config/workflow.json" "$profile_file" > "$tmp"
    mv "$tmp" "$DEST/config/workflow.json"
  fi
else
  echo "WARN: jq/python 未安装，跳过 .workbuddy profile 合并" >&2
fi

sc_chmod_scripts "$DEST"

mkdir -p "$TARGET/.growing/archive" "$TARGET/.growing/rules/local" 2>/dev/null || true

echo "OK: Harness Core 已安装 → $DEST"
