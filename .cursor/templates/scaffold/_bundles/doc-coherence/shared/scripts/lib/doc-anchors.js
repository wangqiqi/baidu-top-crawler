'use strict';

const fs = require('fs');
const path = require('path');

function read(rel, root = process.cwd()) {
  const full = path.join(root, rel);
  if (!fs.existsSync(full)) throw new Error(`missing: ${rel}`);
  return fs.readFileSync(full, 'utf8');
}

function mustInclude(rel, needles, label, root = process.cwd()) {
  const list = Array.isArray(needles) ? needles : [needles];
  const tag = label || rel;
  const text = read(rel, root);
  for (const needle of list) {
    if (!text.includes(needle)) {
      throw new Error(`${rel} missing ${tag}: ${needle}`);
    }
  }
}

function assertVersionAnchors({ packageFile = 'package.json', targets = [] } = {}) {
  const pkg = JSON.parse(read(packageFile));
  const version = pkg.version;
  if (!version) throw new Error(`${packageFile} missing version`);
  for (const rel of targets) {
    mustInclude(rel, version, `version ${version}`);
  }
  return version;
}

module.exports = { read, mustInclude, assertVersionAnchors };
