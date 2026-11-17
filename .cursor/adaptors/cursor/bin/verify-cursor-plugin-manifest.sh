#!/usr/bin/env bash
# TASK-001 SPRINT-PLUGIN-MVP: .cursor-plugin/plugin.json scaffold contract.
set -euo pipefail
# shellcheck source=../lib/resolve-root.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/resolve-root.sh"
ROOT="$(sc_adaptor_repo_root_from "$(cd "$(dirname "$0")" && pwd)")"
CUR="$ROOT/.cursor"
PLUGIN="$ROOT/.cursor-plugin"
# shellcheck source=../lib/verify-common.sh
CORE_LIB="$CUR/harness/core/lib"
[[ -d "$CORE_LIB" ]] || CORE_LIB="$CUR/lib"
source "$CORE_LIB/verify-common.sh" "verify-cursor-plugin-manifest"

vc_title
MANIFEST="$PLUGIN/plugin.json"
[[ -f "$MANIFEST" ]] || vc_fail "missing $MANIFEST"

vc_py "$MANIFEST" <<'PY'
import json, re, sys
from pathlib import Path

manifest = Path(sys.argv[1])
plugin_root = manifest.parent
try:
    data = json.loads(manifest.read_text(encoding="utf-8"))
except json.JSONDecodeError as e:
    print(f"FAIL: plugin.json invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

name = data.get("name")
if not name or not isinstance(name, str):
    print("FAIL: plugin.json missing string name", file=sys.stderr)
    sys.exit(1)
if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name):
    print(f"FAIL: plugin name not kebab-case: {name}", file=sys.stderr)
    sys.exit(1)

desc = data.get("description")
if not desc or not isinstance(desc, str) or len(desc.strip()) < 40:
    print("FAIL: plugin.json needs description (>= 40 chars) for Marketplace", file=sys.stderr)
    sys.exit(1)

author = data.get("author")
if not isinstance(author, dict) or not str(author.get("name", "")).strip():
    print("FAIL: plugin.json missing author.name", file=sys.stderr)
    sys.exit(1)

for key in ("rules", "skills", "agents", "hooks"):
    if key not in data:
        print(f"FAIL: plugin.json missing explicit {key} path (marketplace discovery)", file=sys.stderr)
        sys.exit(1)

def check_path_value(val: str, ctx: str) -> None:
    if val.startswith("/") or "\\" in val:
        print(f"FAIL: absolute path in {ctx}: {val}", file=sys.stderr)
        sys.exit(1)
    if ".." in Path(val).parts:
        print(f"FAIL: parent traversal in {ctx}: {val}", file=sys.stderr)
        sys.exit(1)

def walk(obj, prefix=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            walk(v, f"{prefix}.{k}" if prefix else k)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk(v, f"{prefix}[{i}]")
    elif isinstance(obj, str):
        if obj.startswith("http://") or obj.startswith("https://"):
            return
        if ".." in obj or obj.startswith("/"):
            check_path_value(obj, prefix)
        elif "/" in obj and obj.endswith((".mdc", ".md", ".json", ".sh")):
            check_path_value(obj, prefix)

walk(data)

if not (plugin_root / "README.md").is_file():
    print("FAIL: .cursor-plugin/README.md missing", file=sys.stderr)
    sys.exit(1)
if not (plugin_root / "hooks" / "hooks.json").is_file():
    print("FAIL: hooks/hooks.json missing", file=sys.stderr)
    sys.exit(1)

logo = data.get("logo")
if logo and isinstance(logo, str) and not logo.startswith("http"):
    if not (plugin_root / logo).is_file():
        print(f"FAIL: logo file missing: {logo}", file=sys.stderr)
        sys.exit(1)

def resolve_dir(key: str) -> None:
    val = data.get(key)
    if val is None:
        return
    rel = val[0] if isinstance(val, list) else val
    if not isinstance(rel, str):
        print(f"FAIL: invalid {key} path", file=sys.stderr)
        sys.exit(1)
    if not (plugin_root / rel).is_dir():
        print(f"FAIL: {key} path not found: {rel}", file=sys.stderr)
        sys.exit(1)

for k in ("rules", "skills", "agents"):
    resolve_dir(k)

hooks_val = data.get("hooks")
hook_rel = hooks_val if isinstance(hooks_val, str) else None
if hook_rel and not (plugin_root / hook_rel).is_file():
    print(f"FAIL: hooks path not found: {hook_rel}", file=sys.stderr)
    sys.exit(1)

print(f"OK  plugin manifest name={name}")
PY

vc_summary
