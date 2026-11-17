#!/usr/bin/env bash
# 前端栈公因子（Vite / Next 等 npm 系）—— 三栈 verify.sh 共用，勿各自复制
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

sc_frontend_verify() {
  sc_step "lint";        npm run lint
  sc_step "type-check";  npm run type-check
  sc_step "test";        bash ./scripts/test.sh
  sc_step "build";       npm run build
  sc_summary "frontend verify passed."
}
