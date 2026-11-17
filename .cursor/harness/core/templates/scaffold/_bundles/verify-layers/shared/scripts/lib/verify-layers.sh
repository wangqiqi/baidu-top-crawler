#!/usr/bin/env bash
# Layered verify (L1–L3). L2+ 切片 SSOT：scripts/verify/manifest.tsv（见 README-verify-layers.md）
VERIFY_SLICES_CORE=()
VERIFY_SLICES_STANDARD=()
VERIFY_SLICES_HEAVY=()
VERIFY_SLICES_TASK=()

sc_verify_usage() {
  cat <<'EOF'
用法: ./scripts/verify.sh [层]

  (无参) · --l1 · --fast       L1 快速（stack test.sh + 可选 lint/build）
  --core · --l2-core           L2-core：L1 + CORE 切片
  --l2 · --standard            L2 标准：L1 + STANDARD 切片
  --changed                    按 git 变更跑最小层（见 changed-map.json）
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
  # L1 SSOT: project test loop. Stack hooks (npm lint/build, etc.) → manifest command / bundle-commands.
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

sc_verify_run_manifest() {
  local tier="$1"
  bash "$(dirname "${BASH_SOURCE[0]}")/../verify/run-manifest-tier.sh" "$tier"
}

sc_verify_l2_core() {
  sc_section "L2-core"
  sc_verify_l1_fast
  sc_verify_run_manifest "l2-core"
  sc_pass "verify (L2-core)"
}

sc_verify_l2() {
  sc_section "L2 · standard"
  sc_verify_l1_fast
  sc_verify_run_manifest "l2-standard"
  sc_pass "verify (L2)"
}

sc_verify_l3() {
  sc_section "L3 · full"
  sc_verify_l1_fast
  sc_verify_run_manifest "l3"
  sc_pass "verify (L3)"
}
