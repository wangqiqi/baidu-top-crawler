#!/usr/bin/env node
/**
 * planrun-doctor.mjs — one command that proves whether the four moving parts of
 * an install still agree with each other:
 *
 *   1. manifest         `.dsh/growth/.planrun-manifest.json` exists and is readable
 *   2. guard-files      installed `scripts/*` match the manifest hashes *and* the
 *                       PlanRun reference copy (templates SSOT)
 *   3. plan-template    recorded template schema vs this build, plan.md present,
 *                       core HTML meta intact
 *   4. packages         installed `planrun` / `@planrun/*` versions agree with each
 *                       other, with the reference build, and with what the project
 *                       recorded at install time
 *
 * Check 4 is the one that would have caught the incident this sprint came from:
 * the DSH profile ran planrun 1.9.0 while the checkout's guard scripts were 1.8.1
 * and nothing said a word.
 *
 * Exit codes: 0 no drift · 1 drift found (with FIX lines) · 2 cannot determine
 * (not a PlanRun project). A check that has no reference to compare against is
 * SKIP — never a fabricated failure.
 *
 * Usage:
 *   node planrun-doctor.mjs [--project <dir>] [--json]
 *                           [--source <planrun-root>] [--expect-guard <dir>]
 *                           [--reference-version x.y.z] [--no-profile]
 */
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  PLAN_TEMPLATE_SCHEMA,
  TRACKED_FILES,
  packageVersion,
  readManifest,
  sha256File,
} from './planrun-manifest.mjs'

export const EXIT_OK = 0
export const EXIT_DRIFT = 1
export const EXIT_CANNOT_DETERMINE = 2

/** HTML meta the guard actually reads; the template ships all of them. */
const CORE_META = ['PLANNING', 'SPRINT', 'PLAN_APPROVED', 'VERIFY']

/* ------------------------------------------------------------------ helpers */

/** Walk up from `start` looking for the project's growth dir. */
export function findProjectRoot(start) {
  let dir = resolve(start)
  while (true) {
    if (existsSync(join(dir, '.dsh', 'growth'))) return dir
    const parent = dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

export function planFileFor(projectRoot, env = process.env) {
  if (env.DSH_GROWTH_PLAN && existsSync(env.DSH_GROWTH_PLAN)) return resolve(env.DSH_GROWTH_PLAN)
  return join(projectRoot, '.dsh', 'growth', 'plan.md')
}

function referenceHasGuard(dir) {
  return dir && existsSync(join(dir, 'dsh-guard.sh'))
}

/**
 * Reference copy of the guard files, most authoritative first. The profile
 * package ships the same templates, but a dev checkout is the SSOT — preferring
 * the profile would flag every uncommitted guard fix as drift.
 */
export function resolveReference({ expectGuard, source, manifest, noProfile, env = process.env }) {
  const candidates = []
  if (expectGuard) candidates.push({ dir: join(resolve(expectGuard)), kind: 'explicit' })
  if (source) candidates.push({ dir: join(resolve(source), 'templates', 'growth', 'scripts'), kind: 'source' })
  if (env.PLANRUN_HOME) {
    candidates.push({ dir: join(resolve(env.PLANRUN_HOME), 'templates', 'growth', 'scripts'), kind: 'PLANRUN_HOME' })
  }
  if (manifest?.planrunSource) {
    candidates.push({
      dir: join(resolve(manifest.planrunSource), 'templates', 'growth', 'scripts'),
      kind: 'manifest source',
    })
  }
  if (!noProfile) {
    const profileDir = env.DSH_PROFILE_DIR
    if (profileDir) {
      candidates.push({
        dir: join(profileDir, 'node_modules', 'planrun', 'templates', 'growth', 'scripts'),
        kind: 'profile package',
      })
    }
  }
  for (const candidate of candidates) {
    if (referenceHasGuard(candidate.dir)) return candidate
  }
  return null
}

/** The PlanRun build version to compare installed packages against. */
export function resolveReferenceVersion({ explicit, source, reference, manifest, env = process.env }) {
  if (explicit) return explicit
  const roots = [source, env.PLANRUN_HOME, reference?.kind === 'profile package' ? dirname(dirname(reference.dir)) : null]
  for (const root of roots) {
    if (!root) continue
    const version = packageVersion(root)
    if (version) return version
  }
  if (reference?.kind === 'profile package') {
    const version = packageVersion(dirname(dirname(reference.dir)))
    if (version) return version
  }
  return manifest?.planrunVersion ?? null
}

/** Discover installed planrun packages in the project and (optionally) the profile. */
export function discoverPackages(projectRoot, { noProfile, env = process.env } = {}) {
  const found = []
  const scan = (nodeModules, origin) => {
    const single = join(nodeModules, 'planrun', 'package.json')
    if (existsSync(single)) {
      found.push({ name: 'planrun', version: packageVersion(join(nodeModules, 'planrun')), origin })
    }
    const scope = join(nodeModules, '@planrun')
    if (!existsSync(scope)) return
    for (const entry of readdirSync(scope)) {
      const dir = join(scope, entry)
      try {
        if (!statSync(dir).isDirectory()) continue
      } catch {
        continue
      }
      const version = packageVersion(dir)
      if (version) found.push({ name: `@planrun/${entry}`, version, origin })
    }
  }
  scan(join(projectRoot, 'node_modules'), 'project')
  if (!noProfile && env.DSH_PROFILE_DIR) {
    scan(join(env.DSH_PROFILE_DIR, 'node_modules'), 'profile')
  }
  return found
}

function readMetaKeys(planFile) {
  if (!existsSync(planFile)) return null
  const keys = new Set()
  const pattern = /<!--\s*([A-Z][A-Z0-9_]*)\s*:/g
  let match
  const text = readFileSync(planFile, 'utf8')
  while ((match = pattern.exec(text)) !== null) keys.add(match[1])
  return keys
}

const ok = (id, title, detail, extra = {}) => ({ id, title, status: 'ok', detail, ...extra })
const drift = (id, title, detail, fix, extra = {}) => ({ id, title, status: 'drift', detail, fix, ...extra })
const skip = (id, title, detail, extra = {}) => ({ id, title, status: 'skip', detail, ...extra })

/* ------------------------------------------------------------------- checks */

export function checkManifest(projectRoot) {
  const result = readManifest(projectRoot)
  if (!result.ok) {
    const detail = {
      missing: '项目里没有 .dsh/growth/.planrun-manifest.json —— 无法证明装的是哪个版本',
      unparsable: `版本清单不是合法 JSON: ${result.error}`,
      'not-an-object': '版本清单不是 JSON 对象',
      'schema-mismatch': `版本清单 schema 不匹配: ${result.error}`,
    }[result.reason]
    return drift('manifest', '版本清单', detail, `bash scripts/install-planrun.sh --here  # 重新播种并记录版本`, {
      path: result.path,
    })
  }
  const files = Object.keys(result.manifest.files ?? {})
  return ok(
    'manifest',
    '版本清单',
    `planrun ${result.manifest.planrunVersion ?? '(unknown)'} · schema ${result.manifest.schema} · 记录了 ${files.length} 个 guard 文件`,
    { path: result.path, manifest: result.manifest },
  )
}

export function checkGuardFiles(projectRoot, { manifest, reference }) {
  const tracked = new Set(TRACKED_FILES)
  for (const rel of Object.keys(manifest?.files ?? {})) tracked.add(rel)

  const problems = []
  const fixes = new Set()
  let compared = 0
  let withoutReference = []

  for (const rel of [...tracked].sort()) {
    const abs = join(projectRoot, ...rel.split('/'))
    const recorded = manifest?.files?.[rel] ?? null
    if (!existsSync(abs)) {
      if (recorded) {
        problems.push(`${rel} 清单里有记录但磁盘上不存在`)
        fixes.add('bash scripts/install-planrun.sh --here')
      }
      continue
    }
    const disk = sha256File(abs)
    if (recorded && disk !== recorded) {
      problems.push(`${rel} 安装后被改动（磁盘 ${disk.slice(0, 12)}… ≠ 清单 ${recorded.slice(0, 12)}…）`)
      fixes.add('bash scripts/install-planrun.sh --here  # 重新播种受管脚本')
    }
    if (!reference) {
      withoutReference.push(rel)
      continue
    }
    const expectedFile = join(reference.dir, basename(rel))
    if (!existsSync(expectedFile)) {
      withoutReference.push(rel)
      continue
    }
    compared += 1
    const expected = sha256File(expectedFile)
    if (disk !== expected) {
      problems.push(`${rel} 与参考副本不一致（${reference.kind}: ${expected.slice(0, 12)}… ≠ 磁盘 ${disk.slice(0, 12)}…）`)
      fixes.add(`cp "${expectedFile}" "${abs}"  # 或重跑 install-planrun.sh --here`)
    }
  }

  if (problems.length > 0) {
    return drift('guard-files', 'guard 脚本', problems.join(' · '), [...fixes].join(' · '), {
      reference: reference?.dir ?? null,
    })
  }
  if (compared === 0) {
    return skip(
      'guard-files',
      'guard 脚本',
      `没有可比的参考副本（${withoutReference.length} 个文件仅校验了清单 hash）—— 设 --source / PLANRUN_HOME 才能比对版本`,
    )
  }
  const note = withoutReference.length > 0 ? ` · ${withoutReference.length} 个文件无参考副本` : ''
  return ok('guard-files', 'guard 脚本', `与参考副本一致（${compared} 个文件 · ${reference.kind}）${note}`, {
    reference: reference.dir,
  })
}

export function checkPlanTemplate(projectRoot, { manifest, planFile }) {
  const schema = manifest?.planTemplateSchema ?? null
  if (schema !== PLAN_TEMPLATE_SCHEMA) {
    return drift(
      'plan-template',
      'plan 模板',
      `模板 schema 漂移：清单 ${JSON.stringify(schema)} → 当前 ${PLAN_TEMPLATE_SCHEMA}`,
      'bash scripts/install-planrun.sh --here --copy-plan  # 覆盖 plan.md 到当前模板',
    )
  }
  if (!existsSync(planFile)) {
    return drift('plan-template', 'plan 模板', `plan.md 不存在: ${planFile}`, 'bash scripts/install-planrun.sh --here')
  }
  const keys = readMetaKeys(planFile)
  const missing = CORE_META.filter((key) => !keys.has(key))
  if (missing.length > 0) {
    return drift(
      'plan-template',
      'plan 模板',
      `plan.md 缺少核心 HTML meta: ${missing.join(' · ')}`,
      `补齐 ${missing.map((key) => `<!-- ${key}: ... -->`).join(' ')}，或重跑 install-planrun.sh --here --copy-plan`,
      { planFile },
    )
  }
  return ok('plan-template', 'plan 模板', `schema ${schema} · 核心 meta 齐全 (${CORE_META.join(' · ')})`, { planFile })
}

export function checkPackages(packages, { referenceVersion, manifest }) {
  if (packages.length === 0) {
    const hint = '未发现已安装的 planrun 包（npm 通道尚未发布时属正常）'
    return skip('packages', 'planrun 包版本', hint)
  }
  const versions = [...new Set(packages.map((entry) => entry.version))]
  if (versions.length > 1) {
    return drift(
      'packages',
      'planrun 包版本',
      `已安装的 planrun 包版本不一致: ${packages.map((p) => `${p.name}@${p.version}`).join(' · ')}`,
      'dsh plugin --profile web add "github:wangqiqi/planrun#<tag>"  # 用同一个 tag 重装整个 bundle',
    )
  }
  const installed = versions[0]
  const recorded = manifest?.planrunVersion ?? null
  if (recorded && installed !== recorded) {
    return drift(
      'packages',
      'planrun 包版本',
      `profile/项目里的 planrun@${installed} 与项目记录的 ${recorded} 不一致`,
      `对齐两条通道：升级项目 → bash scripts/install-planrun.sh --here；升级 profile → dsh plugin --profile web add "github:wangqiqi/planrun#v${recorded}"`,
    )
  }
  if (referenceVersion && installed !== referenceVersion) {
    return drift(
      'packages',
      'planrun 包版本',
      `已安装 planrun@${installed} 落后于参考构建 ${referenceVersion}`,
      `dsh plugin --profile web add "github:wangqiqi/planrun#v${referenceVersion}"`,
    )
  }
  const against = referenceVersion ? `参考构建 ${referenceVersion}` : recorded ? `项目记录 ${recorded}` : '无参考版本'
  return ok('packages', 'planrun 包版本', `${packages.map((p) => `${p.name}@${p.version}`).join(' · ')} · 与${against}一致`)
}

/* --------------------------------------------------------------------- run */

export function runDoctor(options = {}) {
  const env = options.env ?? process.env
  const projectRoot = options.project ? resolve(options.project) : findProjectRoot(options.cwd ?? process.cwd())
  if (!projectRoot || !existsSync(join(projectRoot, '.dsh', 'growth'))) {
    return {
      project: projectRoot ?? resolve(options.cwd ?? process.cwd()),
      exitCode: EXIT_CANNOT_DETERMINE,
      checks: [
        skip('project', '项目定位', '没有找到 .dsh/growth/ —— 这不是一个 PlanRun 项目（先跑 install-planrun.sh）'),
      ],
    }
  }

  const manifestResult = readManifest(projectRoot)
  const manifest = manifestResult.ok ? manifestResult.manifest : null
  const planFile = planFileFor(projectRoot, env)
  const reference = resolveReference({
    expectGuard: options.expectGuard,
    source: options.source,
    manifest,
    noProfile: options.noProfile,
    env,
  })
  const referenceVersion = resolveReferenceVersion({
    explicit: options.referenceVersion,
    source: options.source,
    reference,
    manifest,
    env,
  })
  const packages = discoverPackages(projectRoot, { noProfile: options.noProfile, env })

  const checks = [
    checkManifest(projectRoot),
    checkGuardFiles(projectRoot, { manifest, reference }),
    checkPlanTemplate(projectRoot, { manifest, planFile }),
    checkPackages(packages, { referenceVersion, manifest }),
  ]

  const hasDrift = checks.some((check) => check.status === 'drift')
  return {
    project: projectRoot,
    planFile,
    reference: reference ? { dir: reference.dir, kind: reference.kind } : null,
    referenceVersion,
    checks,
    exitCode: hasDrift ? EXIT_DRIFT : EXIT_OK,
  }
}

/* ---------------------------------------------------------------- rendering */

export function renderText(report) {
  const lines = ['=== planrun doctor ===', `project: ${report.project}`]
  if (report.reference) lines.push(`reference: ${report.reference.dir} (${report.reference.kind})`)
  lines.push('')
  for (const check of report.checks) {
    const label = { ok: 'OK  ', drift: 'FAIL', skip: 'SKIP' }[check.status] ?? check.status
    lines.push(`${label}: ${check.id} — ${check.detail}`)
    if (check.fix) lines.push(`      FIX: ${check.fix}`)
  }
  const count = (status) => report.checks.filter((check) => check.status === status).length
  lines.push('')
  if (report.exitCode === EXIT_CANNOT_DETERMINE) {
    lines.push('doctor: 无法判定（不是 PlanRun 项目）')
  } else if (report.exitCode === EXIT_DRIFT) {
    lines.push(`doctor: ${count('drift')} 项漂移 · ${count('ok')} 项通过 · ${count('skip')} 项跳过`)
  } else {
    lines.push(`doctor: 无漂移 · ${count('ok')} 项通过 · ${count('skip')} 项跳过`)
  }
  return `${lines.join('\n')}\n`
}

const USAGE = `用法: node planrun-doctor.mjs [选项]

选项:
  --project <dir>            项目根（默认从 cwd 向上找 .dsh/growth/）
  --source <dir>             PlanRun 仓库/包根，用作参考副本与版本
  --expect-guard <dir>       直接指定参考 guard 目录（优先于 --source）
  --reference-version x.y.z  直接指定参考版本
  --no-profile               不扫描 DSH profile 里已安装的 planrun 包
  --json                     只输出 JSON
  -h, --help                 显示帮助

退出码: 0 无漂移 · 1 有漂移 · 2 无法判定（不是 PlanRun 项目）
`

export function parseArgs(argv) {
  const options = {}
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const take = () => argv[i + 1] ?? null
    switch (arg) {
      case '--project': options.project = take(); i += 1; break
      case '--source': options.source = take(); i += 1; break
      case '--expect-guard': options.expectGuard = take(); i += 1; break
      case '--reference-version': options.referenceVersion = take(); i += 1; break
      case '--no-profile': options.noProfile = true; break
      case '--json': options.json = true; break
      default:
        if (arg.startsWith('--project=')) options.project = arg.slice(10)
        else if (arg.startsWith('--source=')) options.source = arg.slice(9)
        else if (arg.startsWith('--expect-guard=')) options.expectGuard = arg.slice(15)
        else if (arg.startsWith('--reference-version=')) options.referenceVersion = arg.slice(20)
        else if (arg !== '-h' && arg !== '--help') {
          process.stderr.write(`未知选项: ${arg}\n`)
          process.exit(EXIT_CANNOT_DETERMINE)
        }
    }
  }
  return options
}

function main(argv) {
  if (argv.includes('-h') || argv.includes('--help')) {
    process.stdout.write(USAGE)
    return EXIT_OK
  }
  const options = parseArgs(argv)
  const report = runDoctor(options)
  if (options.json) process.stdout.write(`${JSON.stringify(report, null, 2)}\n`)
  else process.stdout.write(renderText(report))
  return report.exitCode
}

/**
 * Only run as a CLI when invoked directly; the module stays importable (tests,
 * the manifest writer). Compare *real* paths: the ESM loader canonicalizes
 * module URLs while `process.argv[1]` keeps the path as typed, so a `resolve()`
 * comparison silently skipped main() on macOS, where `/tmp` and `/var` are
 * symlinks — `doctor` then exited 0 having checked nothing.
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
