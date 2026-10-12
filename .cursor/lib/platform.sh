#!/usr/bin/env bash
# Cross-platform helpers — Linux · macOS · Git Bash (Windows)
# Source from hooks/, bin/, or install-super-cursor.sh at repo root.
[[ -n "${SC_PLATFORM_LOADED:-}" ]] && return 0
SC_PLATFORM_LOADED=1
set -euo pipefail

# Resolve python3 or python (Git Bash / Windows may only expose `python`)
# Windows 默认 cp1252 stdout：python 块打印中文会 UnicodeEncodeError 而崩。
# 统一强制 UTF-8 stdio（对 3.7+ 生效；已显式设置时不覆盖）。
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export PYTHONUTF8="${PYTHONUTF8:-1}"

sc_python() {
  if [[ -n "${SC_PYTHON_CMD:-}" ]]; then
    echo "$SC_PYTHON_CMD"
    return 0
  fi
  local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then
      SC_PYTHON_CMD="$c"
      echo "$SC_PYTHON_CMD"
      return 0
    fi
  done
  return 1
}

# 强制走 python JSON 回退（CI 验证无 jq 路径 · 排查 jq/python 行为差异）
sc_force_python() {
  [[ "${SC_FORCE_PYTHON:-}" == "1" ]]
}

# true when jq or python is available for JSON CLI
sc_has_json_tool() {
  if sc_force_python; then
    sc_python >/dev/null 2>&1
    return
  fi
  command -v jq >/dev/null 2>&1 && return 0
  sc_python >/dev/null 2>&1
}

# Dotted config path → jq filter (plan_file → .plan_file)
sc_jq_path() {
  local dotted="${1#.}"
  echo ".${dotted}"
}

# ISO-8601 timestamp (BSD date on macOS lacks GNU -Iseconds flag)
iso8601_now() {
  date +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date
}

# Read a dotted path from a JSON file (jq or python)
json_cfg() {
  local file="$1" dotted="$2" default="${3:-}"
  local val="" jqpath py

  [[ -f "$file" ]] || { echo "$default"; return 0; }

  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jqpath="$(sc_jq_path "$dotted")"
    val="$(jq -r "${jqpath} // empty" "$file" 2>/dev/null || true)"
  elif py="$(sc_python)"; then
    val="$("$py" - "$file" "$dotted" <<'PY' 2>/dev/null || true
import json, sys
path, dotted = sys.argv[1], sys.argv[2].lstrip(".")
data = json.load(open(path, encoding="utf-8"))
cur = data
for part in dotted.split("."):
    if part not in cur:
        sys.exit(1)
    cur = cur[part]
if cur in ("", None):
    sys.exit(1)
if isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, ensure_ascii=False))
else:
    print(cur)
PY
)"
  fi

  [[ -n "$val" && "$val" != "null" ]] && echo "$val" || echo "$default"
}

# Join JSON array at dotted path with spaces (jq or python)
json_cfg_join() {
  local file="$1" dotted="$2" default="${3:-}"
  local joined="" jqpath py

  [[ -f "$file" ]] || { echo "$default"; return 0; }

  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jqpath="$(sc_jq_path "$dotted")"
    joined="$(jq -r "${jqpath} // [] | join(\" \")" "$file" 2>/dev/null || true)"
  elif py="$(sc_python)"; then
    joined="$("$py" - "$file" "$dotted" <<'PY' 2>/dev/null || true
import json, sys
path, dotted = sys.argv[1], sys.argv[2].lstrip(".")
data = json.load(open(path, encoding="utf-8"))
cur = data
for part in dotted.split("."):
    cur = cur[part]
if not isinstance(cur, list):
    sys.exit(1)
print(" ".join(str(x) for x in cur))
PY
)"
  fi

  [[ -n "$joined" && "$joined" != "null" ]] && echo "$joined" || echo "$default"
}

# Deep-merge two JSON files to stdout (profile install)
sc_json_merge_files() {
  local base="$1" overlay="$2" py
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -s '.[0] * .[1]' "$base" "$overlay"
    return 0
  fi
  if py="$(sc_python)"; then
    "$py" - "$base" "$overlay" <<'PY'
import json, sys

def deep_merge(a, b):
    for k, v in b.items():
        if k in a and isinstance(a[k], dict) and isinstance(v, dict):
            deep_merge(a[k], v)
        else:
            a[k] = v
    return a

base = json.load(open(sys.argv[1], encoding="utf-8"))
overlay = json.load(open(sys.argv[2], encoding="utf-8"))
print(json.dumps(deep_merge(base, overlay), indent=2, ensure_ascii=False))
PY
    return 0
  fi
  echo "FAIL: jq or python required for JSON merge" >&2
  return 1
}

# Copy directory tree; prefers rsync, falls back to cp -a (Git Bash / minimal macOS)
# Usage: sc_copy_tree <src_dir> <dest_dir> [exclude_glob ...]
sc_copy_tree() {
  local src="$1" dest="$2"
  shift 2
  local excludes=("$@")

  # bash 3.2（macOS 系统 bash）+ set -u 下，空数组 "${arr[@]}" 会报 unbound variable 而中止；
  # bash 4.4+ 才把它当空展开。故一律用 ${arr[@]+"${arr[@]}"} 形式。

  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    local -a args=(-a)
    local ex
    for ex in ${excludes[@]+"${excludes[@]}"}; do
      args+=(--exclude "$ex")
    done
    rsync ${args[@]+"${args[@]}"} "${src}/" "${dest}/"
    return 0
  fi

  cp -a "${src}/." "${dest}/"
  local ex
  for ex in ${excludes[@]+"${excludes[@]}"}; do
    case "$ex" in
      hooks/state/*)
        rm -rf "${dest}/hooks/state/"* 2>/dev/null || true
        mkdir -p "${dest}/hooks/state"
        ;;
      *)
        rm -rf "${dest}/${ex}" 2>/dev/null || true
        ;;
    esac
  done
}

# chmod +x for shipped scripts (install)
sc_chmod_scripts() {
  local cursor_dir="$1"
  chmod +x "${cursor_dir}/bin/"*.sh 2>/dev/null || true
  find "${cursor_dir}/templates/scaffold" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
  chmod +x "${cursor_dir}/hooks/"*.sh 2>/dev/null || true
}

# Tab-separated rows → aligned columns (column(1) optional)
sc_print_columns() {
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t'
  else
    awk -F'\t' '{ printf "%-18s %-10s %s\n", $1, $2, $3 }'
  fi
}

# Node stack hint from package.json (nextjs / react / vue / nodejs)
sc_detect_node_stack() {
  local pkg="$1"
  [[ -f "$pkg" ]] || return 1

  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    if jq -e '.dependencies.next != null' "$pkg" >/dev/null 2>&1; then
      echo "nextjs"
    elif jq -e '(.dependencies.react // .devDependencies.react) != null' "$pkg" >/dev/null 2>&1; then
      echo "react"
    elif jq -e '.dependencies.vue != null' "$pkg" >/dev/null 2>&1; then
      echo "vue"
    else
      echo "nodejs"
    fi
    return 0
  fi

  local py
  py="$(sc_python)" || { echo "nodejs"; return 0; }
  "$py" - "$pkg" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
deps = {**(p.get("dependencies") or {}), **(p.get("devDependencies") or {})}
if "next" in deps:
    print("nextjs")
elif "react" in deps:
    print("react")
elif "vue" in deps:
    print("vue")
else:
    print("nodejs")
PY
}

# --- manifest.json helpers (scaffold CLI) ---

_manifest_py() {
  local manifest="$1" py
  shift
  py="$(sc_python)" || return 1
  "$py" - "$manifest" "$@" <<'PY'
import json, sys

# Windows 文本模式默认把 \n 转成 \r\n → shell `read` 会得到 "react-vite-ts\r"，
# 后续 -d/字符串比较全部失败。强制 LF。
try:
    sys.stdout.reconfigure(newline="\n")
except Exception:
    pass

path = sys.argv[1]
cmd = sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
scaffolds = data.get("scaffolds", [])
bundles = data.get("bundles", [])

def by_id(sid):
    for s in scaffolds:
        if s.get("id") == sid:
            return s
    return None

def bundle_by_id(sid):
    for b in bundles:
        if b.get("id") == sid:
            return b
    return None

if cmd == "list":
    for s in scaffolds:
        print(f"{s['id']}\t{s.get('category', '')}\t{s.get('name', '')}")
elif cmd == "exists":
    sys.exit(0 if by_id(sys.argv[3]) else 1)
elif cmd == "info":
    s = by_id(sys.argv[3])
    if not s:
        sys.exit(1)
    print(f"name: {s.get('name', '')}")
    print(f"description: {s.get('description', '')}")
    print(f"verify: {s.get('verify', '')}")
    print("post_apply:")
    for p in s.get("post_apply") or []:
        print(f"  - {p}")
elif cmd == "field":
    s = by_id(sys.argv[3])
    if not s:
        sys.exit(1)
    print(s.get(sys.argv[4], ""))
elif cmd == "field_join":
    s = by_id(sys.argv[3])
    if not s:
        sys.exit(1)
    v = s.get(sys.argv[4])
    if isinstance(v, list):
        print(" ".join(str(x) for x in v))
    elif v is None:
        print("")
    else:
        print(v)
elif cmd == "post_apply":
    s = by_id(sys.argv[3])
    if not s:
        sys.exit(1)
    for p in s.get("post_apply") or []:
        print(p)
elif cmd == "ids":
    for s in scaffolds:
        print(s["id"])
elif cmd == "bundles_list":
    for b in bundles:
        print(f"{b['id']}\t{b.get('category', '')}\t{b.get('name', '')}")
elif cmd == "bundles_count":
    print(len(bundles))
elif cmd == "bundle_exists":
    sys.exit(0 if bundle_by_id(sys.argv[3]) else 1)
elif cmd == "bundle_web_stack":
    b = bundle_by_id(sys.argv[3])
    sys.exit(0 if b and sys.argv[4] in (b.get("stacks_web") or []) else 1)
elif cmd == "bundle_field":
    b = bundle_by_id(sys.argv[3])
    if not b:
        sys.exit(1)
    print(b.get(sys.argv[4], ""))
elif cmd == "bundle_layer":
    b = bundle_by_id(sys.argv[3])
    if not b:
        sys.exit(1)
    print((b.get("layers") or {}).get(sys.argv[4], ""))
elif cmd == "bundle_post_apply":
    b = bundle_by_id(sys.argv[3])
    if not b:
        sys.exit(1)
    for p in b.get("post_apply") or []:
        print(p)
PY
}

sc_require_json_tool() {
  if sc_has_json_tool; then
    return 0
  fi
  echo "FAIL: jq or python required" >&2
  return 1
}

sc_manifest_list() {
  local manifest="$1"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r '.scaffolds[] | "\(.id)\t\(.category)\t\(.name)"' "$manifest"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" list
  else
    sc_require_json_tool
    return 1
  fi
}

sc_manifest_scaffold_exists() {
  local manifest="$1" id="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -e --arg id "$id" '.scaffolds[] | select(.id == $id)' "$manifest" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" exists "$id"
  else
    return 1
  fi
}

sc_manifest_scaffold_info() {
  local manifest="$1" id="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" '
      .scaffolds[] | select(.id == $id) |
      "name: \(.name)",
      "description: \(.description)",
      "verify: \(.verify)",
      "post_apply:",
      (.post_apply[]? | "  - \(.)")
    ' "$manifest"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" info "$id"
  else
    sc_require_json_tool
    return 1
  fi
}

sc_manifest_scaffold_field() {
  local manifest="$1" id="$2" field="$3"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" --arg f "$field" '.scaffolds[] | select(.id == $id) | .[$f]' "$manifest"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" field "$id" "$field"
  else
    sc_require_json_tool
    return 1
  fi
}

sc_manifest_scaffold_post_apply() {
  local manifest="$1" id="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" '.scaffolds[] | select(.id == $id) | .post_apply[]' "$manifest"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" post_apply "$id"
  else
    sc_require_json_tool
    return 1
  fi
}

# 数组字段 → 空格分隔（jq -r 对数组会多行输出，不便 shell 循环）
sc_manifest_scaffold_field_join() {
  local manifest="$1" id="$2" key="$3"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" --arg k "$key" '.scaffolds[] | select(.id == $id) | (.[$k] // []) | if type == "array" then join(" ") else . end' "$manifest"
  else
    _manifest_py "$manifest" field_join "$id" "$key"
  fi
}

sc_manifest_ids() {
  local manifest="$1"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r '.scaffolds[].id' "$manifest"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    _manifest_py "$manifest" ids
  else
    sc_require_json_tool
    return 1
  fi
}

# --- bundles（scaffold apply-bundle）---
# 与 scaffolds 同一策略：jq 快路径（未被 SC_FORCE_PYTHON 强制时）· 否则 python 回退。
# 历史上 bundle 解析直连 jq，导致无 jq 环境 apply-bundle 直接失败。

sc_manifest_bundles() {
  local manifest="$1"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r '.bundles[] | "\(.id)\t\(.category)\t\(.name)"' "$manifest"
  else
    _manifest_py "$manifest" bundles_list
  fi
}

sc_manifest_bundles_count() {
  local manifest="$1"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r '.bundles | length' "$manifest"
  else
    _manifest_py "$manifest" bundles_count
  fi
}

sc_manifest_bundle_exists() {
  local manifest="$1" id="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -e --arg id "$id" '.bundles[] | select(.id == $id)' "$manifest" >/dev/null 2>&1
  else
    _manifest_py "$manifest" bundle_exists "$id"
  fi
}

sc_manifest_bundle_web_stack() {
  local manifest="$1" id="$2" stack="$3"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -e --arg id "$id" --arg s "$stack" \
      '.bundles[] | select(.id == $id) | .stacks_web[]? | select(. == $s)' "$manifest" >/dev/null 2>&1
  else
    _manifest_py "$manifest" bundle_web_stack "$id" "$stack"
  fi
}

sc_manifest_bundle_field() {
  local manifest="$1" id="$2" key="$3"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" --arg k "$key" '.bundles[] | select(.id == $id) | .[$k]' "$manifest"
  else
    _manifest_py "$manifest" bundle_field "$id" "$key"
  fi
}

sc_manifest_bundle_layer() {
  local manifest="$1" id="$2" key="$3"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" --arg k "$key" '.bundles[] | select(.id == $id) | .layers[$k]' "$manifest"
  else
    _manifest_py "$manifest" bundle_layer "$id" "$key"
  fi
}

sc_manifest_bundle_post_apply() {
  local manifest="$1" id="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$id" '.bundles[] | select(.id == $id) | .post_apply[]' "$manifest"
  else
    _manifest_py "$manifest" bundle_post_apply "$id"
  fi
}

# --- docs-layout（项目文档体系：号位=瀑布阶段）---
# 与 manifest 助手同策略：jq 快路径（未被 SC_FORCE_PYTHON 强制时）· 否则 python。

_docs_layout_py() {
  local cfg="$1" py
  shift
  py="$(sc_python)" || return 1
  "$py" - "$cfg" "$@" <<'PY'
import json, sys

# Windows 文本模式默认把 \n 转成 \r\n → shell `read` 会得到 "react-vite-ts\r"，
# 后续 -d/字符串比较全部失败。强制 LF。
try:
    sys.stdout.reconfigure(newline="\n")
except Exception:
    pass

path, cmd = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
slots = data.get("slots") or {}


def out_slot(num):
    v = slots.get(num) or {}
    names = v.get("names") or []
    return v, names


if cmd == "get":
    key = sys.argv[3]
    v = data.get(key)
    print("" if v is None else v)
elif cmd == "plan":
    profile = sys.argv[3]
    mapping = (data.get("profiles") or {}).get(profile)
    if mapping is None:
        sys.exit(3)
    for num in sorted(slots):
        v, names = out_slot(num)
        name = mapping.get(num) or (names[0] if names else v.get("role", ""))
        kind = "required" if v.get("required") else "optional"
        print(f"{num}\t{name}\t{kind}\t{v.get('generated', '')}")
elif cmd == "set_profile":
    data["profile"] = sys.argv[3]
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
PY
}

# 标量键（dir / profile / max_numbered / roadmap_file）
sc_docs_get() {
  local cfg="$1" key="$2"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$cfg"
  else
    _docs_layout_py "$cfg" get "$key"
  fi
}

# 号位计划：`NN<TAB>名称<TAB>required|optional<TAB>generated`；未知 profile 返回 3
sc_docs_plan() {
  local cfg="$1" profile="$2" out
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    out="$(jq -r --arg p "$profile" '
      (.profiles[$p]) as $m
      | if $m == null then error("unknown profile") else . end
      | .slots | to_entries | sort_by(.key)[]
      | .key as $n | .value as $v
      | [ $n,
          ($m[$n] // ($v.names[0] // $v.role)),
          (if $v.required then "required" else "optional" end),
          ($v.generated // "") ]
      | @tsv' "$cfg" 2>/dev/null)" || true
    [[ -n "$out" ]] || return 3      # 未知 profile（jq error 的退出码归一为 3）
    printf '%s\n' "$out"
  else
    _docs_layout_py "$cfg" plan "$profile"
  fi
}

# 写回 profile（保持 2 空格缩进与中文原样）
sc_docs_set_profile() {
  local cfg="$1" profile="$2" tmp
  tmp="$(mktemp)"
  if ! sc_force_python && command -v jq >/dev/null 2>&1; then
    jq --arg p "$profile" '.profile = $p' "$cfg" >"$tmp" && mv "$tmp" "$cfg"
  else
    _docs_layout_py "$cfg" set_profile "$profile" && rm -f "$tmp"
  fi
}
