#!/usr/bin/env bash
# project-profile.sh — read .growing/project-profile.json (按需启用元数据)
set -euo pipefail

_SC_PP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=platform.sh
source "$_SC_PP_LIB/platform.sh"

sc_project_profile_path() {
  local root="${1:-}"
  [[ -n "$root" ]] || return 1
  echo "$root/.growing/project-profile.json"
}

sc_profile_ignore() {
  [[ "${VERIFY_IGNORE_PROFILE:-}" == "1" ]]
}

# 0 = apply profile filters · 1 = no profile or ignore
sc_profile_filter_enabled() {
  local root="${1:-}"
  sc_profile_ignore && return 1
  local path
  path="$(sc_project_profile_path "$root" 2>/dev/null || true)"
  [[ -n "$path" && -f "$path" ]]
}

sc_profile_normalize_manifest_tier() {
  local tier="${1:-}"
  case "$tier" in
    l2-standard) echo "l2-domain" ;;
    l2-core | l2-domain | l3 | l0 | l1 | changed) echo "$tier" ;;
    *) echo "$tier" ;;
  esac
}

sc_profile_tier_rank() {
  case "$(sc_profile_normalize_manifest_tier "$1")" in
    l0) echo 0 ;;
    l1) echo 1 ;;
    l2-core) echo 2 ;;
    l2-domain) echo 3 ;;
    l3) echo 4 ;;
    changed) echo 5 ;;
    *) echo -1 ;;
  esac
}

# Exit 0 if tier may run (manifest runner / verify layer)
sc_profile_tier_allowed() {
  local root="${1:-}"
  local tier="${2:-}"
  if ! sc_profile_filter_enabled "$root"; then
    return 0
  fi
  local path rank want max=0
  path="$(sc_project_profile_path "$root")"
  want="$(sc_profile_tier_rank "$tier")"
  [[ "$want" -ge 0 ]] || return 0

  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r en; do
      [[ -n "$en" ]] || continue
      local r
      r="$(sc_profile_tier_rank "$en")"
      [[ "$r" -ge "$max" ]] && max="$r"
    done < <(jq -r '.verify.enabled_tiers[]? // empty' "$path" 2>/dev/null || true)
  else
    local py
    py="$(sc_python 2>/dev/null || true)"
    [[ -n "$py" ]] || return 0
    max="$("$py" - "$path" <<'PY'
import json, sys
path = sys.argv[1]
ranks = {"l0":0,"l1":1,"l2-core":2,"l2-domain":3,"l2-standard":3,"l3":4,"changed":5}
try:
    d = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    print(-1); sys.exit(0)
tiers = (d.get("verify") or {}).get("enabled_tiers") or []
mx = -1
for t in tiers:
    mx = max(mx, ranks.get(t, ranks.get("l2-domain" if t == "l2-standard" else "", -1)))
print(mx)
PY
)"
  fi

  [[ "$max" -lt 0 ]] && return 0
  [[ "$want" -le "$max" ]]
}

# Exit 0 if manifest row stacks column matches profile primary (or stacks is * / empty)
sc_profile_stacks_allow_row() {
  local root="${1:-}"
  local stacks_col="${2:-*}"
  stacks_col="${stacks_col//$'\r'/}"
  if ! sc_profile_filter_enabled "$root"; then
    return 0
  fi
  if [[ -z "$stacks_col" || "$stacks_col" == "*" ]]; then
    return 0
  fi

  local path
  path="$(sc_project_profile_path "$root")"
  local primary_csv
  if command -v jq >/dev/null 2>&1; then
    primary_csv="$(jq -r '[.stacks.primary[]?] | join(" ")' "$path" 2>/dev/null || true)"
  else
    local py
    py="$(sc_python 2>/dev/null || true)"
    [[ -n "$py" ]] || return 0
    primary_csv="$("$py" - "$path" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print(" ".join((d.get("stacks") or {}).get("primary") or []))
except (OSError, json.JSONDecodeError):
    pass
PY
)"
  fi

  [[ -n "${primary_csv// }" ]] || return 0

  local s p
  stacks_col="${stacks_col//,/ }"
  for s in $stacks_col; do
    for p in $primary_csv; do
      [[ "$s" == "$p" ]] && return 0
    done
  done
  return 1
}

# One-line hint for run-start (empty if missing / invalid)
sc_project_profile_hint() {
  local root="${1:-}"
  local path py
  path="$(sc_project_profile_path "$root" 2>/dev/null || true)"
  [[ -n "$path" && -f "$path" ]] || return 0

  py="$(sc_python 2>/dev/null || true)"
  [[ -n "$py" ]] || return 0
  "$py" - "$path" <<'PY'
import json, sys
path = sys.argv[1]
try:
    d = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    sys.exit(0)
st = d.get("stacks") or {}
primary = ",".join(st.get("primary") or [])
detected = ",".join(st.get("detected") or [])
if not primary and not detected:
    sys.exit(0)
ver = d.get("verify") or {}
tiers = ",".join(ver.get("enabled_tiers") or [])
slices = ver.get("enabled_slices") or []
slice_n = len(slices)
tier_part = f"tiers={tiers or '?'}"
slice_part = f"slices={slice_n}" if slice_n else "slices=0"
print(
    f"Project profile: primary={primary or '?'} · detected={detected or '?'} · "
    f"{tier_part} · {slice_part} · SSOT=.growing/project-profile.json"
)
PY
}

# Print DAILY/LIBRARY preview lines (adapt dry-run / --write)
sc_profile_print_daily_library() {
  local py
  py="$(sc_python 2>/dev/null || true)"
  [[ -n "$py" ]] || return 0
  PRIMARY_CSV="${1:-}" "$py" <<'PY'
import os
primary = [s.strip() for s in os.environ.get("PRIMARY_CSV", "").replace(",", " ").split() if s.strip()]
STACK_RULES = {
    "go": ["go.mdc"],
    "rust": ["rust.mdc"],
    "python": ["python.mdc"],
    "java": ["java.mdc"],
    "cpp": ["cpp.mdc"],
    "c": ["c.mdc"],
    "react": ["react.mdc", "typescript.mdc", "javascript.mdc", "eslint.mdc"],
    "vue": ["vue.mdc", "typescript.mdc", "javascript.mdc", "eslint.mdc"],
    "nextjs": ["nextjs.mdc", "react.mdc", "typescript.mdc", "eslint.mdc"],
    "nodejs": ["javascript.mdc", "typescript.mdc", "eslint.mdc"],
    "svelte": ["svelte.mdc", "typescript.mdc", "eslint.mdc"],
}
ALL_TECH = sorted({
    "c.mdc", "cpp.mdc", "eslint.mdc", "go.mdc", "java.mdc", "javascript.mdc",
    "nextjs.mdc", "python.mdc", "react.mdc", "rust.mdc", "svelte.mdc", "typescript.mdc", "vue.mdc",
})
daily_rules = []
for p in primary:
    for r in STACK_RULES.get(p, []):
        if r not in daily_rules:
            daily_rules.append(r)
library_rules = [r for r in ALL_TECH if r not in daily_rules]
DAILY_SKILLS = ["plan", "run", "learn", "master", "git"]
LIBRARY_SKILLS = ["perf", "mcp", "study", "delivery", "debug", "review"]
print("DAILY rules/tech: " + (", ".join(f"rules/tech/{r}" for r in daily_rules) or "(none)"))
print("LIBRARY rules/tech: " + (", ".join(f"rules/tech/{r}" for r in library_rules) or "(none)"))
print("DAILY skills: " + ", ".join(DAILY_SKILLS))
print("LIBRARY skills (sample): " + ", ".join(LIBRARY_SKILLS))
PY
}

# Merge profile into learn/dev-conventions.md (SC_PROFILE_SYNC block)
sc_profile_sync_dev_conventions() {
  local root="${1:-}" cursor_dir="${2:-}"
  [[ -n "$root" && -n "$cursor_dir" ]] || return 1
  local profile_path learn_path template_path py
  profile_path="$(sc_project_profile_path "$root")"
  [[ -f "$profile_path" ]] || return 1
  learn_path="$root/.growing/learn/dev-conventions.md"
  template_path="$cursor_dir/templates/growing/learn/dev-conventions.md"
  mkdir -p "$root/.growing/learn"
  if [[ ! -f "$learn_path" && -f "$template_path" ]]; then
    cp "$template_path" "$learn_path"
  fi
  [[ -f "$learn_path" ]] || return 1
  py="$(sc_python 2>/dev/null || true)"
  [[ -n "$py" ]] || return 1
  PROFILE_PATH="$profile_path" LEARN_PATH="$learn_path" "$py" <<'PY'
import json, os, re, sys

profile_path = os.environ["PROFILE_PATH"]
learn_path = os.environ["LEARN_PATH"]
d = json.load(open(profile_path, encoding="utf-8"))
st = d.get("stacks") or {}
primary = st.get("primary") or []
detected = st.get("detected") or []
ver = d.get("verify") or {}
tiers = ver.get("enabled_tiers") or []
slices = ver.get("enabled_slices") or []
adapted = d.get("adapted_at") or "—"

STACK_RULES = {
    "go": ["go.mdc"], "rust": ["rust.mdc"], "python": ["python.mdc"], "java": ["java.mdc"],
    "cpp": ["cpp.mdc"], "c": ["c.mdc"],
    "react": ["react.mdc", "typescript.mdc", "javascript.mdc", "eslint.mdc"],
    "vue": ["vue.mdc", "typescript.mdc", "javascript.mdc", "eslint.mdc"],
    "nextjs": ["nextjs.mdc", "react.mdc", "typescript.mdc", "eslint.mdc"],
    "nodejs": ["javascript.mdc", "typescript.mdc", "eslint.mdc"],
    "svelte": ["svelte.mdc", "typescript.mdc", "eslint.mdc"],
}
ALL_TECH = sorted({
    "c.mdc", "cpp.mdc", "eslint.mdc", "go.mdc", "java.mdc", "javascript.mdc",
    "nextjs.mdc", "python.mdc", "react.mdc", "rust.mdc", "svelte.mdc", "typescript.mdc", "vue.mdc",
})
daily_rules = []
for p in primary:
    for r in STACK_RULES.get(p, []):
        if r not in daily_rules:
            daily_rules.append(r)
library_rules = [r for r in ALL_TECH if r not in daily_rules]
DAILY_SKILLS = ["plan", "run", "learn", "master", "git"]
LIBRARY_SKILLS = ["perf", "mcp", "study", "delivery", "debug", "review"]

def bullets(items):
    if not items:
        return "- （无）\n"
    return "".join(f"- {x}\n" for x in items)

daily_rule_lines = [f"rules/tech/{r}" for r in daily_rules]
library_rule_lines = [f"rules/tech/{r}" for r in library_rules]
daily_skill_lines = [f"skill {s}" for s in DAILY_SKILLS]
library_skill_lines = [f"skill {s}" for s in LIBRARY_SKILLS]

block = f"""<!-- SC_PROFILE_SYNC:BEGIN -->
<!-- 机器维护：`scaffold adapt --write` 覆盖本节；勿手改。 -->

| 项 | 值 |
|----|-----|
| 主栈 (primary) | {", ".join(primary) or "—"} |
| detected | {", ".join(detected) or "—"} |
| adapted_at | {adapted} |
| verify.enabled_tiers | {", ".join(tiers) or "—"} |
| verify.enabled_slices | {", ".join(slices) if slices else "（空 · tier 策略）"} |

**DAILY**（本会话优先 · 证据：profile primary）

{bullets(daily_rule_lines + daily_skill_lines)}

**LIBRARY**（离栈 · 需要时再 `@` 或 slash）

{bullets(library_rule_lines + library_skill_lines)}

<!-- SC_PROFILE_SYNC:END -->"""

text = open(learn_path, encoding="utf-8").read()
pat = re.compile(
    r"<!-- SC_PROFILE_SYNC:BEGIN -->.*?<!-- SC_PROFILE_SYNC:END -->",
    re.DOTALL,
)
if not pat.search(text):
    sys.stderr.write(f"FAIL: missing SC_PROFILE_SYNC markers in {learn_path}\n")
    sys.exit(1)
new_text = pat.sub(block.strip(), text, count=1)
with open(learn_path, "w", encoding="utf-8") as f:
    f.write(new_text)
print(f"SYNC {learn_path}")
PY
}

# Default verify tiers when adapt creates a new profile
sc_project_profile_default_verify_tiers() {
  echo "l0 l1 l2-core"
}
