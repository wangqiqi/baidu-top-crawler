#!/usr/bin/env bash
# Smoke: trae core_skills_export install (temp dir only).
set -euo pipefail

# 兼容两种入口：CI 的 .cursor/bin（符号链接）与母版 .cursor/harness/core/bin
_walk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_DIR=""
while [[ "$_walk" != "/" ]]; do
  if [[ -f "$_walk/harness/assemble.sh" && -d "$_walk/adaptors" ]]; then
    CURSOR_DIR="$_walk"
    break
  fi
  _walk="$(dirname "$_walk")"
done
[[ -n "$CURSOR_DIR" ]] || { echo "FAIL: cannot find .cursor pack root" >&2; exit 1; }

# shellcheck source=../lib/temp-cleanup.sh
source "$CURSOR_DIR/harness/core/lib/temp-cleanup.sh"
# shellcheck source=../lib/platform.sh
source "$CURSOR_DIR/harness/core/lib/platform.sh"
sc_temp_trap_cleanup
INSTALL="$CURSOR_DIR/harness/core/bin/install-adaptor-skills-export.sh"
[[ -f "$INSTALL" ]] || INSTALL="$CURSOR_DIR/bin/install-adaptor-skills-export.sh"

sc_mktemp_dir sc-verify-skills-export
TMP="$SC_MKTEMP_LAST"

# 消费方自有 skill 不得被导出覆盖/删除
mkdir -p "$TMP/.trae/skills/local-keep"
printf '%s\n' '---' 'name: local-keep' 'description: consumer own skill' '---' > "$TMP/.trae/skills/local-keep/SKILL.md"

if ! bash "$INSTALL" --adaptor trae "$TMP" >/dev/null 2>&1; then
  echo "FAIL: install-adaptor-skills-export --adaptor trae" >&2
  exit 1
fi

[[ -f "$TMP/.trae/skills/local-keep/SKILL.md" ]] \
  || { echo "FAIL: existing consumer skill removed" >&2; exit 1; }
[[ ! -d "$TMP/.trae/rules" ]] \
  || { echo "FAIL: skills export must not create .trae/rules/" >&2; exit 1; }

for f in api/SKILL.md plan/SKILL.md week/SKILL.md; do
  [[ -f "$TMP/.trae/skills/$f" ]] || { echo "FAIL: missing .trae/skills/$f" >&2; exit 1; }
done

src_n="$(find -L "$CURSOR_DIR/harness/core/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
dst_n="$(find "$TMP/.trae/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
# 目标多一个 local-keep
[[ "$dst_n" == "$((src_n + 1))" ]] \
  || { echo "FAIL: .trae/skills dirs=$dst_n (expected $((src_n + 1)) = $src_n + local-keep)" >&2; exit 1; }

py="$(sc_python)" || { echo "FAIL: python required to check skill frontmatter" >&2; exit 1; }
"$py" - "$TMP/.trae/skills" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
bad = []
for skill in sorted(p for p in root.iterdir() if p.is_dir()):
    md = skill / "SKILL.md"
    if not md.is_file():
        bad.append(f"{skill.name}: missing SKILL.md")
        continue
    head = md.read_text(encoding="utf-8")[:2000]
    m = re.search(r"(?m)^name:\s*(\S+)\s*$", head.split("\n---", 1)[0])
    if not m or m.group(1).strip('"') != skill.name:
        bad.append(f"{skill.name}: frontmatter name mismatch")
if bad:
    for b in bad[:10]:
        print(f"FAIL: {b}", file=sys.stderr)
    sys.exit(1)
print(f"OK  frontmatter names match dirs ({len(list(root.iterdir()))} skills)")
PY

# 与 Cursor 一致：逐字节复制，不改写 frontmatter（含 disable-model-invocation）、
# 不改写正文 .cursor/… 路径、不增删 reference/ scripts。任何"适配性改写"都必须先改本断言。
for src_skill in "$CURSOR_DIR/harness/core/skills"/*/; do
  name="$(basename "${src_skill%/}")"
  diff -r "${src_skill%/}" "$TMP/.trae/skills/$name" >/dev/null 2>&1 \
    || { echo "FAIL: exported skill diverges from source: $name" >&2; exit 1; }
done
grep -q '^disable-model-invocation: true' "$TMP/.trae/skills/plan/SKILL.md" \
  || { echo "FAIL: disable-model-invocation must be preserved (Cursor parity)" >&2; exit 1; }
echo "OK  byte-identical export (frontmatter · .cursor paths · reference/scripts preserved)"

# --skills-bundle core → 23 skills，五工具 skill 不导出
CORE_DIR="$TMP/core-bundle"
bash "$INSTALL" --adaptor trae "$CORE_DIR" --skills-bundle core >/dev/null 2>&1 \
  || { echo "FAIL: install-adaptor-skills-export --skills-bundle core" >&2; exit 1; }
core_n="$(find "$CORE_DIR/.trae/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$core_n" == "23" ]] || { echo "FAIL: core bundle skills=$core_n (expected 23)" >&2; exit 1; }
for s in week disk maintain ops-deploy code-stats-viz; do
  [[ ! -d "$CORE_DIR/.trae/skills/$s" ]] || { echo "FAIL: core bundle still has skills/$s" >&2; exit 1; }
done

# kiro 无 skills 机制：必须拒绝
if bash "$INSTALL" --adaptor kiro "$TMP/kiro" >/dev/null 2>&1; then
  echo "FAIL: --adaptor kiro must be rejected" >&2
  exit 1
fi

echo "OK: verify-install-skills-export (trae skills=$src_n · core=$core_n · load-bearing frontmatter)"
