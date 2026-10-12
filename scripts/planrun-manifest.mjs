#!/usr/bin/env node
/**
 * planrun-manifest.mjs — record what `install-planrun.sh` seeded into a project,
 * so version drift is *provable* instead of a feeling.
 *
 * Why this exists: the install seeds `.dsh/growth/`, the guard scripts and the
 * npm scripts, while the DSH profile carries its own `planrun` package. Nothing
 * recorded which version seeded which project — a project could keep running
 * 1.8.1 guard scripts under a 1.9.0 session and nobody got told (that is exactly
 * how SPRINT-01 was born).
 *
 * Written to `<project>/.dsh/growth/.planrun-manifest.json`:
 * {
 *   "schema": 1,
 *   "planrunVersion": "1.9.0",
 *   "planrunSource": "/path/to/planrun",
 *   "installedAt": "2026-10-12T07:20:00.000Z",
 *   "planTemplateSchema": 1,
 *   "files": { "scripts/dsh-guard.sh": "<sha256>" }
 * }
 *
 * Usage:
 *   node planrun-manifest.mjs write <project-root> --source <planrun-root> [--version x.y.z]
 *   node planrun-manifest.mjs read  <project-root>
 *   node planrun-manifest.mjs --help
 */
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const MANIFEST_SCHEMA = 1
export const PLAN_TEMPLATE_SCHEMA = 1
export const MANIFEST_REL = join('.dsh', 'growth', '.planrun-manifest.json')

/**
 * Files `install-planrun.sh` drops next to the guard. Hashed at install time so
 * a later hand-edit (or a half-finished upgrade) is detectable.
 */
export const TRACKED_FILES = [
  'scripts/dsh-guard.sh',
  'scripts/plan-parse.sh',
  'scripts/run-bash.mjs',
]

export function manifestPath(projectRoot) {
  return join(resolve(projectRoot), MANIFEST_REL)
}

export function sha256File(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex')
}

export function packageVersion(dir) {
  const pkg = join(resolve(dir), 'package.json')
  if (!existsSync(pkg)) return null
  try {
    return JSON.parse(readFileSync(pkg, 'utf8')).version ?? null
  } catch {
    return null
  }
}

/** Resolve the version to record: explicit flag → source package.json → null. */
export function resolveVersion(explicit, sourceRoot) {
  if (explicit) return explicit
  if (sourceRoot) {
    const version = packageVersion(sourceRoot)
    if (version) return version
  }
  return null
}

/**
 * Build a manifest object without touching the filesystem beyond hashing.
 * Missing tracked files are skipped — `--no-guard` installs seed no scripts.
 */
export function buildManifest(projectRoot, { source = null, version = null, now = new Date() } = {}) {
  const root = resolve(projectRoot)
  const files = {}
  for (const rel of TRACKED_FILES) {
    const abs = join(root, rel)
    if (existsSync(abs)) files[rel.split('\\').join('/')] = sha256File(abs)
  }
  return {
    schema: MANIFEST_SCHEMA,
    planrunVersion: version,
    planrunSource: source ? resolve(source) : null,
    installedAt: now.toISOString(),
    planTemplateSchema: PLAN_TEMPLATE_SCHEMA,
    files,
  }
}

export function writeManifest(projectRoot, options = {}) {
  const manifest = buildManifest(projectRoot, options)
  const target = manifestPath(projectRoot)
  mkdirSync(dirname(target), { recursive: true })
  writeFileSync(target, `${JSON.stringify(manifest, null, 2)}\n`)
  return { path: target, manifest }
}

/**
 * Read a manifest for the doctor. Never throws: the doctor must be able to
 * report *why* it cannot prove anything (missing file, bad JSON, old schema).
 */
export function readManifest(projectRoot) {
  const path = manifestPath(projectRoot)
  if (!existsSync(path)) {
    return { ok: false, path, reason: 'missing', manifest: null, error: null }
  }
  let parsed
  try {
    parsed = JSON.parse(readFileSync(path, 'utf8'))
  } catch (error) {
    return { ok: false, path, reason: 'unparsable', manifest: null, error: error.message }
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { ok: false, path, reason: 'not-an-object', manifest: null, error: null }
  }
  if (parsed.schema !== MANIFEST_SCHEMA) {
    return {
      ok: false,
      path,
      reason: 'schema-mismatch',
      manifest: parsed,
      error: `manifest schema ${JSON.stringify(parsed.schema)} != ${MANIFEST_SCHEMA}`,
    }
  }
  return { ok: true, path, reason: null, manifest: parsed, error: null }
}

const USAGE = `用法:
  node planrun-manifest.mjs write <project-root> --source <planrun-root> [--version x.y.z]
  node planrun-manifest.mjs read  <project-root>

说明:
  write  记录 planrun 版本 · guard 脚本 sha256 · 模板 schema · 安装时间
         → <project-root>/.dsh/growth/.planrun-manifest.json
  read   打印清单 JSON（缺失或损坏时退出码 1）
`

function parseArgs(argv) {
  const positional = []
  const flags = { source: null, version: null }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--source') {
      flags.source = argv[i + 1] ?? null
      i += 1
    } else if (arg.startsWith('--source=')) {
      flags.source = arg.slice('--source='.length)
    } else if (arg === '--version') {
      flags.version = argv[i + 1] ?? null
      i += 1
    } else if (arg.startsWith('--version=')) {
      flags.version = arg.slice('--version='.length)
    } else {
      positional.push(arg)
    }
  }
  return { positional, flags }
}

function main(argv) {
  if (argv.length === 0 || argv.includes('-h') || argv.includes('--help')) {
    process.stdout.write(USAGE)
    return 0
  }
  const { positional, flags } = parseArgs(argv)
  const [command, projectRoot] = positional
  if (!command || !projectRoot) {
    process.stderr.write(USAGE)
    return 2
  }

  if (command === 'write') {
    const version = resolveVersion(flags.version, flags.source)
    const { path, manifest } = writeManifest(projectRoot, {
      source: flags.source,
      version,
    })
    const hashed = Object.keys(manifest.files).length
    console.log(`OK: 版本清单 → ${path}`)
    console.log(
      `    planrun ${manifest.planrunVersion ?? '(unknown)'} · schema ${manifest.schema} · 模板 schema ${manifest.planTemplateSchema} · ${hashed} 个 guard 文件已记录 sha256`,
    )
    return 0
  }

  if (command === 'read') {
    const result = readManifest(projectRoot)
    if (!result.ok) {
      console.error(`FAIL: 无法读取版本清单 (${result.reason}): ${result.path}`)
      if (result.error) console.error(`      ${result.error}`)
      return 1
    }
    process.stdout.write(`${JSON.stringify(result.manifest, null, 2)}\n`)
    return 0
  }

  console.error(`未知命令: ${command}`)
  process.stderr.write(USAGE)
  return 2
}

/**
 * Only run as a CLI when invoked directly; the doctor imports these helpers.
 *
 * Compare *real* paths: the ESM loader canonicalizes module URLs (resolving
 * symlinks) while `process.argv[1]` keeps the path as typed. On macOS `/tmp` and
 * `/var` are symlinks, so a `resolve()` comparison was false and the CLI exited 0
 * without doing anything — `install-planrun.sh` wrote no manifest and `doctor`
 * then reported a clean install it had never inspected.
 */
function isDirectInvocation(entry) {
  if (!entry) return false
  try {
    return realpathSync(entry) === realpathSync(fileURLToPath(import.meta.url))
  } catch {
    return false
  }
}

if (isDirectInvocation(process.argv[1])) {
  process.exit(main(process.argv.slice(2)))
}
