#!/usr/bin/env bash
# Bidirectional check: verify-layers registry ↔ scripts/verify/slices/*.sh
set -euo pipefail
source "$(dirname "$0")/../../lib/load.sh"
sc_cd_root

node <<'NODE'
const fs = require('fs');
const path = require('path');

const root = process.cwd();
const layersPath = path.join(root, 'scripts/lib/verify-layers.sh');
const text = fs.readFileSync(layersPath, 'utf8');

function extractArray(name) {
  const re = new RegExp(`${name}=\\(\\s*([\\s\\S]*?)\\n\\)`, 'm');
  const match = text.match(re);
  if (!match) throw new Error(`missing ${name} in verify-layers.sh`);
  const entries = [];
  for (const m of match[1].matchAll(/"([^"]+)"/g)) entries.push(m[1]);
  return entries;
}

const core = extractArray('VERIFY_SLICES_CORE');
const standard = extractArray('VERIFY_SLICES_STANDARD');
const heavy = extractArray('VERIFY_SLICES_HEAVY');
const task = extractArray('VERIFY_SLICES_TASK');
const registered = new Set([...standard, ...heavy, ...task]);
const standardSet = new Set(standard);
const strict = process.env.VERIFY_REGISTRY_STRICT === '1';

const missing = [];
for (const rel of [...core, ...standard, ...heavy, ...task]) {
  const full = path.join(root, 'scripts/verify', rel);
  if (!fs.existsSync(full)) missing.push(rel);
}
if (missing.length) {
  throw new Error(`verify-layers entries missing files:\n${missing.join('\n')}`);
}

const coreNotInStandard = core.filter((rel) => !standardSet.has(rel));
if (coreNotInStandard.length) {
  throw new Error(`VERIFY_SLICES_CORE must be subset of STANDARD:\n${coreNotInStandard.join('\n')}`);
}

const slicesDir = path.join(root, 'scripts/verify/slices');
if (!fs.existsSync(slicesDir)) {
  throw new Error(`missing ${slicesDir}`);
}
const sliceFiles = fs
  .readdirSync(slicesDir)
  .filter((f) => f.endsWith('.sh'))
  .map((f) => `slices/${f}`);

const unregistered = sliceFiles.filter((rel) => !registered.has(rel));
if (unregistered.length) {
  const msg = `${unregistered.length} slice scripts not in registry:\n${unregistered.join('\n')}`;
  if (strict) {
    throw new Error(`VERIFY_REGISTRY_STRICT: ${msg}`);
  }
  console.log(`[i] ${msg} (register in scripts/lib/verify-layers.sh)`);
}

console.log(
  `[✓] verify-layers registry: core=${core.length} standard=${standard.length} heavy=${heavy.length} task=${task.length}, files OK, ${unregistered.length} unclassified slices`,
);
NODE

sc_pass "verify_layers_registry"
