#!/usr/bin/env bash
# Smoke-test install-super-cursor.sh (temp dirs only; no side effects on repo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/install-super-cursor.sh"
TMP_ROOT="$(mktemp -d)"
FAIL=0

fail() { echo "FAIL $1"; FAIL=$((FAIL + 1)); }

# set -e 下"哪一行中止"必须可见 —— 曾出现「无 FAIL 行、秒退」，导致 macOS/Windows 失败无法定位
trap 'echo "FAIL install smoke aborted at line $LINENO (unguarded command under set -e)" >&2' ERR
ok() { echo "OK  $1"; }

cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

assert_file() {
  local path="$1" label="$2"
  [[ -f "$path" ]] && ok "$label" || fail "$label (missing $path)"
}

assert_absent() {
  local path="$1" label="$2"
  [[ ! -e "$path" ]] && ok "$label" || fail "$label (unexpected $path)"
}

assert_grep() {
  local file="$1" pattern="$2" label="$3"
  grep -qE "$pattern" "$file" 2>/dev/null && ok "$label" || fail "$label ($file)"
}

# 安装必须「失败可见」：捕获输出，失败时打 FAIL 并回显尾部，且不中止整个 smoke
run_install() {
  local label="$1" out="$2"
  shift 2
  local rc=0
  "$INSTALL" "$@" >"$out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    ok "$label"
  else
    fail "$label (installer exit $rc)"
    echo "  ---- installer output (tail) ----" >&2
    tail -15 "$out" 2>/dev/null | sed 's/^/  | /' >&2
    echo "  --------------------------------" >&2
  fi
  return 0
}

assert_git_ignored() {
  local dir="$1" file="$2" label="$3"
  (
    cd "$dir"
    git init -q
    git add -A
    if git status --short | grep -qF "$file"; then
      echo "FAIL $label (would be tracked)"
      exit 1
    fi
    echo "OK  $label"
  ) || FAIL=$((FAIL + 1))
}

[[ -x "$INSTALL" ]] || { echo "FAIL install script not executable: $INSTALL"; exit 1; }

echo "=== install smoke ==="

# 1. full · empty target
FULL="$TMP_ROOT/full-empty"
run_install "full: install into empty target" "$TMP_ROOT/full.out" "$FULL" --profile full
assert_file "$FULL/.cursorGrowth/plan.md" "full: .cursorGrowth/plan.md copied"
assert_file "$FULL/.cursorGrowth/learn/plan-conventions.md" "full: learn seeds"
# B4：安装输出必须把「首次必做 /learn」讲清楚，否则闸门与验收会空转
assert_grep "$TMP_ROOT/full.out" '/learn' "full: output points at /learn first-run"
assert_grep "$FULL/.gitignore" 'cursorGrowth' "full: gitignore .cursorGrowth/"
assert_absent "$FULL/plan.md" "full: no root plan.md"
assert_grep "$FULL/.cursorGrowth/plan.md" '执行顺序' "full: plan template 执行顺序"
# Windows/Git Bash 的 ln -s 可能退化为复制 → 断言「可达」而非「必须是符号链接」
if [[ -L "$FULL/.cursor/rules/local" ]] || [[ -e "$FULL/.cursor/rules/local/README.md" ]]; then
  ok "full: rules/local resolvable"
else
  fail "full: rules/local not resolvable"
fi
(
  cd "$FULL"
  bash .cursor/bin/runner.sh plan-check >/dev/null 2>&1
) && fail "full: plan-check must report not-ready before approval" \
  || ok "full: plan-check reports not-ready before approval"
# 闸门必须 fail-closed：模板默认 PLAN_APPROVED:(none) 不得放行（P0-3 回归）
(
  cd "$FULL"
  bash .cursor/bin/runner.sh gate-check >/dev/null 2>&1
) && fail "full: gate-check must BLOCK before PLAN_APPROVED" \
  || ok "full: gate-check blocks unapproved plan"
assert_grep "$FULL/.cursor/bin/runner.sh" 'release-tag' "full: runner.sh release-tag"

# 2. lite · no --copy-plan
LITE="$TMP_ROOT/lite-no-plan"
run_install "lite: install" "$TMP_ROOT/lite.out" "$LITE" --profile lite
assert_absent "$LITE/.cursorGrowth/plan.md" "lite: no plan without --copy-plan"
assert_grep "$LITE/.gitignore" 'cursorGrowth' "lite: gitignore .cursorGrowth/"

# 3. lite · --copy-plan
LITE_COPY="$TMP_ROOT/lite-copy"
run_install "lite --copy-plan: install" "$TMP_ROOT/lite-copy.out" "$LITE_COPY" --profile lite --copy-plan
assert_file "$LITE_COPY/.cursorGrowth/plan.md" "lite --copy-plan: .cursorGrowth/plan.md"

# 4. merge existing .gitignore
EXISTING="$TMP_ROOT/existing"
mkdir -p "$EXISTING"
echo 'node_modules/' >"$EXISTING/.gitignore"
run_install "merge: install onto existing .gitignore" "$TMP_ROOT/existing.out" "$EXISTING" --profile full
assert_grep "$EXISTING/.gitignore" 'node_modules' "merge: keeps node_modules/"
assert_grep "$EXISTING/.gitignore" 'cursorGrowth' "merge: adds .cursorGrowth/"

# 5. .cursorGrowth not tracked after git init
assert_git_ignored "$FULL" ".cursorGrowth/plan.md" "full: .cursorGrowth/plan.md gitignored"

# 6. --here / auto git root from subdirectory
HERE_ROOT="$TMP_ROOT/here-project"
mkdir -p "$HERE_ROOT/src/pkg"
git -C "$HERE_ROOT" init -q
HERE_OUT="$TMP_ROOT/here.out"
if ( cd "$HERE_ROOT/src/pkg" && "$INSTALL" --replace >"$HERE_OUT" 2>&1 ); then
  ok "here: install from nested dir"
else
  fail "here: install from nested dir (see output)"
  tail -10 "$HERE_OUT" 2>/dev/null | sed 's/^/  | /' >&2
fi
assert_file "$HERE_ROOT/.cursor/rules/core.mdc" "here: .cursor at git root"

# 7. --setup-shell
HOME_SAVE="$HOME"
export HOME="$TMP_ROOT/home-setup"
mkdir -p "$HOME"
touch "$HOME/.bashrc"
run_install "setup-shell" "$TMP_ROOT/setup-shell.out" --setup-shell
grep -qF 'SUPER_CURSOR_HOME=' "$HOME/.bashrc" && ok "setup-shell: SUPER_CURSOR_HOME" || fail "setup-shell: SUPER_CURSOR_HOME"
grep -qF 'install-super-cursor' "$HOME/.bashrc" && ok "setup-shell: alias" || fail "setup-shell: alias"
export HOME="$HOME_SAVE"

# 8. self-replace guard（P0-4）：目标 == 母版目录时必须拒绝且不删 .cursor/
# 需要符号链接来构造「source==target」；无符号链接权限的平台（Windows/Git Bash）显式 SKIP，
# 而不是让裸 ln -s 在 set -e 下中止整个 smoke（曾导致 Windows 腿秒退且无 FAIL 行）
SELF="$TMP_ROOT/self-replace"
mkdir -p "$SELF"
cp "$INSTALL" "$SELF/install-super-cursor.sh"
if ln -s "$ROOT/.cursor" "$SELF/.cursor" 2>/dev/null; then
  (
    cd "$SELF"
    env -u SUPER_CURSOR_HOME -u CURSOR_AI_HOME \
      bash ./install-super-cursor.sh "$SELF" --replace >/dev/null 2>&1
  ) && fail "self-replace: must refuse source==target" || ok "self-replace: refuses source==target"
  assert_file "$SELF/.cursor/hooks.json" "self-replace: .cursor intact"
  assert_file "$ROOT/.cursor/hooks.json" "self-replace: mother repo untouched"
else
  echo "SKIP  self-replace guard（本平台无符号链接权限，无法构造 source==target）"
fi

echo "---"
if [[ "$FAIL" -eq 0 ]]; then
  echo "install smoke passed."
  exit 0
fi
echo "$FAIL install smoke check(s) failed."
exit 1
