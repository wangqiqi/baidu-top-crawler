#!/usr/bin/env bash
# Growth SPIKE 归档门禁公因子。
#
# `.growing/` 是本地私有目录（`.gitignore`，不入 git），因此 SPIKE 归档在
# 新克隆 / CI 里**必然不存在**。门禁语义（勿改，CI 绿依赖它）：
#   - `archive/meta/` 目录不存在 → 归档从未引导 → SKIP（本地证据无从校验，放行）
#   - 目录存在但目标归档缺失 → 真回归（误删 / 未归档）→ 调用方 FAIL
# 本地开发保留严格校验；母版 CI 不再因缺少本地私有证据而连红。
[[ -n "${SC_GROWTH_ARCHIVE_LOADED:-}" ]] && return 0
SC_GROWTH_ARCHIVE_LOADED=1

# sc_growth_archive_available <archive_dir> [label]
#   返回 0 = 目录存在（调用方继续严格校验）
#   返回 1 = 未引导（已打印 SKIP；调用方应 `|| exit 0` 放行）
sc_growth_archive_available() {
  local dir="$1" label="${2:-growth archive}"
  if [[ -d "$dir" ]]; then
    return 0
  fi
  echo "SKIP  ${label}: .growing/archive/meta 未引导（本地私有 · 不入 git）— fresh clone / CI 跳过 SPIKE 归档门禁"
  return 1
}
