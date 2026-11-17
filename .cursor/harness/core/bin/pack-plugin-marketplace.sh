#!/usr/bin/env bash
# Emit Cursor Marketplace layout from .cursor-plugin/ (official: sibling rules + .cursor-plugin/plugin.json).
set -euo pipefail
# shellcheck source=../lib/pack-root.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/pack-root.sh"

SRC="$ROOT/.cursor-plugin"
OUT="${SC_PLUGIN_MARKETPLACE_OUT:-$ROOT/dist/cursor-plugin-marketplace}"
PLUGIN_DIR="$OUT/super-cursor-mvp"
MANIFEST_NESTED="$PLUGIN_DIR/.cursor-plugin/plugin.json"

[[ -d "$SRC" ]] || { echo "FAIL: missing $SRC (run sync-plugin-subset.sh)" >&2; exit 1; }
[[ -f "$SRC/plugin.json" ]] || { echo "FAIL: missing $SRC/plugin.json" >&2; exit 1; }

_tpl="$CUR/templates/cursor-plugin/marketplace.json"
[[ -f "$_tpl" ]] || _tpl="$ROOT/.cursor/harness/core/templates/cursor-plugin/marketplace.json"

rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR/.cursor-plugin" "$OUT/.cursor-plugin"

# Component trees at plugin pack root (sibling of nested manifest)
for d in rules skills agents hooks lib templates assets; do
  [[ -d "$SRC/$d" ]] || continue
  mkdir -p "$PLUGIN_DIR/$d"
  cp -a "$SRC/$d/." "$PLUGIN_DIR/$d/"
done

# Nested manifest + user-facing README at pack root
cp "$SRC/plugin.json" "$MANIFEST_NESTED"
[[ -f "$SRC/README.md" ]] && cp "$SRC/README.md" "$PLUGIN_DIR/README.md"

if [[ -f "$_tpl" ]]; then
  cp "$_tpl" "$OUT/.cursor-plugin/marketplace.json"
fi

echo "pack-plugin-marketplace: → $PLUGIN_DIR (manifest $MANIFEST_NESTED)"
echo "  marketplace.json → $OUT/.cursor-plugin/marketplace.json"
