#!/usr/bin/env bash
# Doc-coherence checks for Super Cursor mother repo (aggregated by verify-super-cursor.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CUR="$ROOT/.cursor"

# shellcheck source=../lib/verify-common.sh
source "$CUR/lib/verify-common.sh" "verify-doc-super-cursor"

echo "=== verify-doc-super-cursor ==="

# --- README skills count vs disk ---
disk_skills="$(find "$CUR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
readme_line="$(grep -E 'skills/.*[0-9]+ 个' "$ROOT/README.md" 2>/dev/null | head -1 || true)"
if [[ -z "$readme_line" ]]; then
  vc_fail "README.md missing skills count line (N 个)"
else
  readme_skills="$(echo "$readme_line" | grep -oE '[0-9]+ 个' | head -1 | grep -oE '[0-9]+' || true)"
  if [[ "$readme_skills" == "$disk_skills" ]]; then
    vc_ok "README skills count=$disk_skills matches disk"
  else
    vc_fail "README skills count=$readme_skills disk=$disk_skills"
  fi
fi

# --- migration-catalog skills/rules counts (optional line) ---
mc="$CUR/docs/migration-catalog.md"
if [[ -f "$mc" ]]; then
  disk_rules="$(find "$CUR/rules" -name '*.mdc' | wc -l | tr -d ' ')"
  if grep -qE "${disk_skills} skills" "$mc" && grep -qE "${disk_rules} rules" "$mc"; then
    vc_ok "migration-catalog counts skills=$disk_skills rules=$disk_rules"
  else
    vc_fail "migration-catalog counts mismatch (expect ${disk_skills} skills · ${disk_rules} rules)"
  fi
else
  vc_fail "missing $mc"
fi

# --- doc-hygiene rule registered ---
check_rule() {
  [[ -f "$1" ]] && vc_ok "exists $1" || vc_fail "missing $1"
}
check_rule "$CUR/rules/execution/doc-hygiene.mdc"

# --- 双语最低集（A5）：英文入口存在且被主 README 链接 ---
if [[ -f "$ROOT/README.en.md" ]] \
  && grep -q 'README\.en\.md' "$ROOT/README.md" \
  && [[ -f "$CUR/docs/quickstart.en.md" ]]; then
  vc_ok "bilingual entry (README.en.md + docs/quickstart.en.md) present and linked"
else
  vc_fail "bilingual entry missing or not linked from README.md (README.en.md · docs/quickstart.en.md)"
fi

# --- skill metadata 契约：description ≤85 字 + dmi 分桶（防再次被删的回归）---
# 该节曾在 ef5521b 被静默删除且无人发现；此处断言存在性 + 实际元数据
training="$CUR/docs/training/skills.md"
if grep -q 'disable-model-invocation' "$training" 2>/dev/null \
  && grep -q '≤85' "$training" 2>/dev/null; then
  vc_ok "training/skills.md documents dmi policy + description cap"
else
  vc_fail "training/skills.md missing disable-model-invocation policy section"
fi

vc_py "$CUR" <<'PY'
import re, sys
from pathlib import Path

cur = Path(sys.argv[1])
dmi_expected = {
    "plan", "run", "learn", "scaffold", "release", "long",
    "week", "disk", "maintain", "code-stats-viz", "ops-deploy",
}
fails = []

for p in sorted((cur / "skills").glob("*/SKILL.md")):
    name = p.parent.name
    text = p.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        fails.append(f"{name}: missing frontmatter")
        continue
    fm = m.group(1)
    dm = re.search(r"^description:\s*(.*?)(?=\n[A-Za-z_-]+:|\Z)", fm, re.S | re.M)
    desc = re.sub(r"\s+", " ", (dm.group(1) if dm else "")).strip()
    if len(desc) > 85:
        fails.append(f"{name}: description {len(desc)} chars (>85)")
    has_dmi = bool(re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M))
    if has_dmi != (name in dmi_expected):
        fails.append(f"{name}: disable-model-invocation={has_dmi}, policy expects {name in dmi_expected}")

# master 路由 payload：主路由须内联在 SKILL.md（routes.md 为按需二级索引）
master = cur / "skills/master/SKILL.md"
if not master.is_file():
    fails.append("skills/master/SKILL.md missing")
else:
    mt = master.read_text(encoding="utf-8")
    if len(mt) > 3000:
        fails.append(f"master/SKILL.md {len(mt)} chars (>3000): routing payload must stay inline and small")
    for rid in ("scaffold", "plan", "run", "learn", "fix", "ship", "more"):
        if not re.search(r"\|\s*`?" + rid + r"`?\s*\|", mt):
            fails.append(f"master/SKILL.md missing main route id '{rid}' (routing moved out of the default payload)")

# 巨型 SKILL 必须瘦身到 reference/（C5）：主流程留 SKILL，细节按需加载
for name, limit in (("run", 5000), ("plan", 5000)):
    p = cur / f"skills/{name}/SKILL.md"
    if not p.is_file():
        fails.append(f"skills/{name}/SKILL.md missing")
        continue
    size = len(p.read_text(encoding="utf-8"))
    if size > limit:
        fails.append(f"skills/{name}/SKILL.md {size} chars (>{limit}): move detail into reference/")
    if not (cur / f"skills/{name}/reference").is_dir():
        fails.append(f"skills/{name}/reference missing (detail must live there, not in SKILL)")

if fails:
    for f in fails:
        print("FAIL skill metadata:", f)
    sys.exit(1)
print(f"OK  skill metadata (28 files · description <=85 · dmi buckets · run/plan slim)")
PY

# --- relative markdown links under .cursor/docs ---
vc_py "$CUR/docs" <<'PY'
import re, sys
from pathlib import Path

docs_root = Path(sys.argv[1])
link_re = re.compile(r'\]\(([^)]+)\)')
skip_prefix = ("http://", "https://", "mailto:", "#")
broken = []

for md in sorted(docs_root.rglob("*.md")):
    text = md.read_text(encoding="utf-8", errors="replace")
    for raw in link_re.findall(text):
        target = raw.split()[0].strip()
        if not target or target.startswith(skip_prefix):
            continue
        # strip anchor
        path_part = target.split("#", 1)[0]
        if not path_part:
            continue
        resolved = (md.parent / path_part).resolve()
        if not resolved.exists():
            broken.append(f"{md.relative_to(docs_root).as_posix()} -> {target}")

if broken:
    for b in broken[:20]:
        print("FAIL broken link:", b)
    if len(broken) > 20:
        print("FAIL ... and", len(broken) - 20, "more")
    sys.exit(1)
print("OK  relative links in .cursor/docs (%d files)" % len(list(docs_root.rglob('*.md'))))
sys.exit(0)
PY

vc_summary "verify-doc-super-cursor passed."
