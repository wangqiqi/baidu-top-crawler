#!/usr/bin/env bash
# Layered verify registry (L1–L3). Sourced by scripts/verify.sh.

# L2-core: P0 merge gate. Must be subset of VERIFY_SLICES_STANDARD.
VERIFY_SLICES_CORE=(
  "slices/verify_layers_registry.sh"
)

# L2 standard: register domain slices here.
VERIFY_SLICES_STANDARD=(
  "slices/verify_layers_registry.sh"
  "slices/verify_example_health.sh"
)

# L3 heavy: E2E · perf · docker — run only with --full.
VERIFY_SLICES_HEAVY=()

# Task-only: explicit register; not in L2/L3 runners by default.
VERIFY_SLICES_TASK=()

sc_verify_usage() {
  cat <<'EOF'
用法: ./scripts/verify.sh [层]

  (无参) · --l1 · --fast       L1 快速（stack test.sh + 可选 lint/build）
  --core · --l2-core           L2-core：L1 + CORE 切片
  --l2 · --standard            L2 标准：L1 + STANDARD 切片
  --full · --l3                L3 全量：L2 + HEAVY 切片

环境变量:
  VERIFY_REGISTRY_STRICT=1     未登记 slice 即失败（建议 CI）
EOF
}

sc_verify_resolve_layer() {
  local arg="${1:-}"
  case "$arg" in
    ""|--l1|-f|--fast|l1|L1) echo "l1" ;;
    --core|-c|--l2-core|l2-core|core|L2-core) echo "l2-core" ;;
    --l2|-s|--standard|l2|L2|standard) echo "l2" ;;
    --full|--l3|-F|l3|L3|full) echo "l3" ;;
    -h|--help|help) echo "help" ;;
    *)
      echo "FAIL: unknown verify layer: $arg" >&2
      sc_verify_usage >&2
      return 1
      ;;
  esac
}

sc_verify_l1_fast() {
  if [[ -f package.json ]]; then
    if npm run 2>/dev/null | grep -qE '^  lint'; then
      npm run lint
    fi
    if npm run 2>/dev/null | grep -qE '^  type-check'; then
      npm run type-check
    fi
    bash ./scripts/test.sh
    if npm run 2>/dev/null | grep -qE '^  build'; then
      npm run build
    fi
    return 0
  fi
  if [[ -f go.mod || -f Cargo.toml || -f pyproject.toml ]]; then
    bash ./scripts/test.sh
    return 0
  fi
  bash ./scripts/test.sh
}

sc_verify_run_slices() {
  local -a rels=("$@")
  local -a scripts=()
  local rel
  for rel in ${rels[@]+"${rels[@]}"}; do
    scripts+=("$(sc_vpath "$rel")")
  done
  run_suite parallel ${scripts[@]+"${scripts[@]}"}
}

sc_verify_l1() {
  sc_section "L1 · fast"
  sc_verify_l1_fast
  sc_pass "verify (L1)"
}

sc_verify_l2_core() {
  sc_section "L2-core"
  sc_verify_l1_fast
  sc_verify_run_slices "${VERIFY_SLICES_CORE[@]}"
  sc_pass "verify (L2-core)"
}

sc_verify_l2() {
  sc_section "L2 · standard"
  sc_verify_l1_fast
  sc_verify_run_slices "${VERIFY_SLICES_STANDARD[@]}"
  sc_pass "verify (L2)"
}

sc_verify_l3() {
  sc_section "L3 · full"
  sc_verify_l1_fast
  sc_verify_run_slices \
    "${VERIFY_SLICES_STANDARD[@]}" \
    "${VERIFY_SLICES_HEAVY[@]}"
  sc_pass "verify (L3)"
}
