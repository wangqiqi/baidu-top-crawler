#!/usr/bin/env bash
# Smoke: install OpenCode adaptor (generate AGENTS.md + opencode.json in temp dir).
set -euo pipefail
# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"
# shellcheck source=../lib/temp-cleanup.sh
source "$CUR/lib/temp-cleanup.sh"
sc_temp_trap_cleanup
INSTALL_OC="$CUR/bin/install-adaptor-opencode.sh"

sc_mktemp_dir sc-verify-install-opencode
TMP="$SC_MKTEMP_LAST"

if ! bash "$INSTALL_OC" "$TMP" >/dev/null 2>&1; then
  echo "FAIL: install-adaptor-opencode exited non-zero" >&2
  exit 1
fi

[[ -f "$TMP/AGENTS.md" ]] || { echo "FAIL: missing AGENTS.md" >&2; exit 1; }
[[ -f "$TMP/opencode.json" ]] || { echo "FAIL: missing opencode.json" >&2; exit 1; }

# opencode.json 必须含 instructions 数组且引用 .cursor/rules
grep -q '"instructions"' "$TMP/opencode.json" || { echo "FAIL: opencode.json missing instructions" >&2; exit 1; }
grep -q '\.cursor/rules' "$TMP/opencode.json" || { echo "FAIL: opencode.json must reference .cursor/rules" >&2; exit 1; }

# 不应再生成 .opencode/ 目录（官方无此约定）
[[ ! -d "$TMP/.opencode" ]] || { echo "FAIL: must NOT create .opencode/ dir (not an official convention)" >&2; exit 1; }

# JSON 有效性（有可用的 python/jq 时校验；sc_python 会排除 Windows Store 假 python）
# shellcheck source=../lib/platform.sh
source "$CUR/lib/platform.sh"
if py="$(sc_python 2>/dev/null)"; then
  # 路径作为 argv 传入：Git Bash 会自动转成 Windows 路径（写进 -c 字符串里则不会）
  "$py" -c 'import json,sys;json.load(open(sys.argv[1],encoding="utf-8"))' "$TMP/opencode.json" \
    || { echo "FAIL: invalid opencode.json" >&2; exit 1; }
elif command -v jq >/dev/null 2>&1; then
  jq empty "$TMP/opencode.json" || { echo "FAIL: invalid opencode.json" >&2; exit 1; }
fi

echo "OK: verify-install-opencode (AGENTS.md + opencode.json)"
