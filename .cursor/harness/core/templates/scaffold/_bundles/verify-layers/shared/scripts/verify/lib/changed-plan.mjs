/**
 * SPRINT-VERIFY-EFFICIENT · 由变更文件推导 verify 计划（保守 fail-safe）。
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execFileSync } from 'child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const MAP_PATH = path.join(ROOT, 'scripts/verify/changed-map.json');
// Copy from changed-map.example.json on first customize.

const LAYER_RANK = { l1: 1, 'l2-core': 2, 'l2-standard': 3 };
const VALID_LAYERS = ['l1', 'l2-core', 'l2-standard'];

/** @param {Record<string, unknown>} [map] */
export function resolveMinLayer(map = {}) {
  const env = process.env.VERIFY_CHANGED_MIN_LAYER?.trim();
  const fromMap = typeof map.minLayer === 'string' ? map.minLayer.trim() : '';
  const raw = env || fromMap;
  if (!raw) return null;
  if (!VALID_LAYERS.includes(raw)) {
    throw new Error(
      `VERIFY_CHANGED_MIN_LAYER 无效: "${raw}"（允许: ${VALID_LAYERS.join(', ')}）`,
    );
  }
  return raw;
}

/** @param {{ layer: string }} plan @param {string|null} minLayer */
export function applyMinLayer(plan, minLayer) {
  if (!minLayer) return plan;
  if ((LAYER_RANK[minLayer] || 0) > (LAYER_RANK[plan.layer] || 0)) {
    return { ...plan, layer: minLayer };
  }
  return plan;
}

export function loadMap(mapPath = MAP_PATH) {
  return JSON.parse(fs.readFileSync(mapPath, 'utf8'));
}

/** @param {string[]} files */
export function planForChangedFiles(files, map = loadMap()) {
  const order = map.layerOrder || ['l1', 'l2-core', 'l2-standard'];
  let layer = 'l1';
  let unmatched = 0;
  const bash = new Set();

  for (const file of files) {
    const norm = file.replace(/^\.\//, '');
    let matched = false;
    for (const rule of map.prefixRules || []) {
      if (norm === rule.prefix || norm.startsWith(rule.prefix)) {
        matched = true;
        if ((LAYER_RANK[rule.layer] || 0) > (LAYER_RANK[layer] || 0)) {
          layer = rule.layer;
        }
        for (const b of rule.bash || []) bash.add(b);
        break;
      }
    }
    if (!matched) {
      unmatched += 1;
    }
  }

  if (unmatched > 0) {
    const def = map.defaultLayer || 'l2-core';
    if ((LAYER_RANK[def] || 0) > (LAYER_RANK[layer] || 0)) {
      layer = def;
    }
  }

  if (!files.length) {
    layer = 'l1';
  }

  const plan = {
    layer,
    bash: [...bash],
    unmatched,
    files: files.length,
    layerOrder: order,
  };
  return applyMinLayer(plan, resolveMinLayer(map));
}

function resolveChangedBase(base, root) {
  const explicit = base || process.env.VERIFY_CHANGED_BASE;
  if (explicit) return explicit;
  for (const ref of ['origin/master', 'origin/main', 'master', 'main']) {
    try {
      execFileSync('git', ['rev-parse', '--verify', ref], { cwd: root, stdio: 'pipe' });
      return ref;
    } catch {
      /* try next */
    }
  }
  throw new Error(
    'verify:changed 需要有效 git base：设置 VERIFY_CHANGED_BASE=ref，或确保存在 master/main（本地无远端时常用 VERIFY_CHANGED_BASE=master）',
  );
}

export function gitChangedFiles(base, root = ROOT) {
  const ref = resolveChangedBase(base, root);
  execFileSync('git', ['rev-parse', '--verify', ref], { cwd: root, stdio: 'pipe' });
  const range = `${ref}...HEAD`;
  try {
    const out = execFileSync('git', ['diff', '--name-only', range], {
      cwd: root,
      encoding: 'utf8',
    });
    return out.split('\n').map((l) => l.trim()).filter(Boolean);
  } catch (err) {
    throw new Error(`git diff ${range} 失败：${err instanceof Error ? err.message : String(err)}`);
  }
}

export function layerToVerifyArg(layer) {
  switch (layer) {
    case 'l1':
      return [];
    case 'l2-core':
      return ['--core'];
    case 'l2-standard':
      return ['--standard'];
    default:
      return ['--core'];
  }
}

/** @param {{ layer: string, bash?: string[] }} plan */
export function buildChangedSteps(plan) {
  const layerArgs = layerToVerifyArg(plan.layer);
  const steps = [];
  const seen = new Set();
  const add = (cmd, args) => {
    const key = JSON.stringify([cmd, args]);
    if (seen.has(key)) return;
    seen.add(key);
    steps.push([cmd, args]);
  };
  if (layerArgs.length) {
    add('bash', ['scripts/verify.sh', ...layerArgs]);
  } else {
    add('bash', ['scripts/verify.sh']);
  }
  for (const rel of plan.bash || []) {
    add('bash', [rel]);
  }
  return steps;
}
