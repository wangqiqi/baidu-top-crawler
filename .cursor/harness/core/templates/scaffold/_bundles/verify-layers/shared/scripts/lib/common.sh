#!/usr/bin/env bash
# Shared factors for layered verify (scaffold bundle verify-layers).
# Layer L0–L3: see scripts/README-verify-layers.md

_SC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC_SCRIPTS_DIR="$(cd "${_SC_LIB_DIR}/.." && pwd)"
SC_ROOT="$(cd "${SC_SCRIPTS_DIR}/.." && pwd)"
SC_VERIFY_DIR="${SC_SCRIPTS_DIR}/verify"

sc_cd_root() {
  ROOT="${SC_ROOT}"
  cd "$ROOT"
}

sc_vpath() {
  echo "${SC_VERIFY_DIR}/$1"
}

sc_pick_port() {
  node -e "const net=require('net');const s=net.createServer();s.listen(0,'127.0.0.1',()=>{console.log(s.address().port);s.close(()=>process.exit(0));});"
}

sc_section() {
  echo "=== $1 ==="
}

sc_pass() {
  echo "[✓] $1"
}
