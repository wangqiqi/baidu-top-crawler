#!/usr/bin/env bash
# Bootstrap for scripts/verify/** slice scripts.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
sc_cd_root

sc_require_suite() {
  # shellcheck source=run-suite.sh
  source "${_SC_LIB_DIR}/run-suite.sh"
}
