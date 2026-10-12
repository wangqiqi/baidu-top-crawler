#!/usr/bin/env node
/**
 * run-bash.mjs — run a POSIX shell script on any platform.
 *
 * The guard and verify scripts are bash, but `bash` is not always where a POSIX
 * user expects it:
 *
 *   * Windows without Git for Windows on PATH has no bash at all;
 *   * Windows *with* the optional WSL/Store shim resolves `bash` to
 *     `%LOCALAPPDATA%\Microsoft\WindowsApps\bash.exe`, which fails with
 *     E_ACCESSDENIED instead of running anything;
 *   * macOS ships bash 3.2 and Linux images sometimes have only `sh`.
 *
 * So this launcher probes for a shell that actually works (`<shell> -c "exit 0"`)
 * and forwards to it, inheriting stdio and the exit code:
 *
 *   node scripts/run-bash.mjs scripts/dsh-guard.sh gate-check
 *   node scripts/run-bash.mjs --selftest
 *
 * Exit codes: the child's own status; 127 when no working shell exists; 2 for
 * usage errors.
 */
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { delimiter, join, resolve } from 'node:path'
import process from 'node:process'

const argv = process.argv.slice(2)
const SELFTEST = argv[0] === '--selftest'
const script = SELFTEST ? undefined : argv[0]
const scriptArgs = SELFTEST ? [] : argv.slice(1)

/** A shell that answers `<shell> -c "exit 0"` is usable; nothing else counts. */
function probe(command, prefixArgs) {
  const result = spawnSync(command, [...prefixArgs, '-c', 'exit 0'], { stdio: 'ignore' })
  return result.status === 0
}

function version(command, prefixArgs) {
  const result = spawnSync(command, [...prefixArgs, '-c', 'echo $BASH_VERSION'], { encoding: 'utf8' })
  return (result.stdout ?? '').trim() || '(no BASH_VERSION)'
}

/**
 * Git for Windows records its install root in the registry even when its `bin`
 * directory never made it onto PATH. Reading it costs one `reg query` and covers
 * the "Git is installed, the terminal just does not know" case.
 */
function gitForWindowsRoots() {
  const result = spawnSync(
    'reg.exe',
    ['query', 'HKLM\\SOFTWARE\\GitForWindows', '/v', 'InstallPath'],
    { encoding: 'utf8' },
  )
  if (result.status !== 0) return []
  const match = /InstallPath\s+REG_\w+\s+(.+)/.exec(result.stdout ?? '')
  return match ? [match[1].trim()] : []
}

/**
 * Windows candidates, most specific first.
 *
 * `%LOCALAPPDATA%\Microsoft\WindowsApps` is deliberately skipped: it is the
 * Store/WSL alias that fails when no distribution is installed.
 */
function windowsCandidates() {
  const env = process.env
  const candidates = []
  const roots = [
    env.ProgramFiles,
    env['ProgramFiles(x86)'],
    env.LOCALAPPDATA ? join(env.LOCALAPPDATA, 'Programs') : undefined,
    env.USERPROFILE ? join(env.USERPROFILE, 'scoop', 'apps', 'git', 'current') : undefined,
    env.ChocolateyInstall,
    ...gitForWindowsRoots(),
  ]
  for (const root of roots) {
    if (root) candidates.push(join(root, 'Git', 'bin', 'bash.exe'), join(root, 'bin', 'bash.exe'))
  }
  for (const dir of (env.PATH ?? env.Path ?? '').split(delimiter)) {
    if (!dir || /[\\/]WindowsApps[\\/]?$/i.test(dir)) continue
    candidates.push(join(dir, 'bash.exe'))
  }
  return candidates
}

function wslCommand() {
  const systemRoot = process.env.SystemRoot ?? 'C:\\Windows'
  return join(systemRoot, 'System32', 'wsl.exe')
}

function resolveShell() {
  const rejected = []
  if (process.platform !== 'win32') {
    for (const command of ['bash', 'sh']) {
      if (probe(command, [])) return { command, prefixArgs: [] }
      rejected.push(command)
    }
    return { rejected }
  }
  for (const candidate of windowsCandidates()) {
    if (!existsSync(candidate)) continue
    if (probe(candidate, [])) return { command: candidate, prefixArgs: [] }
    rejected.push(candidate)
  }
  // Last resort: a WSL distribution can run the script, but it sees a different
  // filesystem view, so the path is converted and the caller is warned.
  const wsl = wslCommand()
  if (probe(wsl, ['-e', 'bash'])) {
    return { command: wsl, prefixArgs: ['-e', 'bash'], wsl: true }
  }
  return { rejected }
}

const shell = resolveShell()
if (shell.command === undefined) {
  console.error('run-bash: no working POSIX shell found.')
  // "Not installed" and "installed but cannot start" need different fixes: a
  // restricted session that denies the MSYS2 runtime its named-pipe namespace
  // looks exactly like a missing install, and telling that user to reinstall Git
  // sends them the wrong way.
  if (shell.rejected.length > 0) {
    console.error(`  Found ${shell.rejected[0]} but it could not start — a sandbox or`)
    console.error('  security policy may be blocking the shell\'s signal pipe / named pipes.')
  }
  console.error('  Windows: install Git for Windows (https://git-scm.com) or a WSL distribution.')
  console.error('  macOS/Linux: install bash or sh.')
  process.exit(127)
}

if (SELFTEST) {
  const detail = shell.wsl ? '(WSL fallback)' : version(shell.command, shell.prefixArgs)
  console.log(`OK: ${shell.command} ${shell.prefixArgs.join(' ')} ${detail}`.trim())
  process.exit(0)
}

if (script === undefined) {
  console.error('usage: node scripts/run-bash.mjs <script.sh> [args...]  |  --selftest')
  process.exit(2)
}
if (!existsSync(script)) {
  console.error(`run-bash: script not found: ${script}`)
  process.exit(2)
}

let target = script
if (shell.wsl) {
  const converted = spawnSync(shell.command, ['wslpath', '-u', resolve(script)], { encoding: 'utf8' })
  const convertedPath = (converted.stdout ?? '').trim()
  if (converted.status === 0 && convertedPath !== '') {
    target = convertedPath
    console.error(`run-bash: using WSL for ${target} (paths are resolved inside the distribution)`)
  } else {
    // wslpath is missing on minimal distributions; map the drive by hand rather
    // than handing the distribution a Windows path it cannot open.
    const mapped = /^([A-Za-z]):[\\/](.*)$/.exec(resolve(script))
    if (mapped === null) {
      console.error(`run-bash: wslpath could not convert ${script} and the path is not a drive path`)
      process.exit(2)
    }
    target = `/mnt/${mapped[1].toLowerCase()}/${mapped[2].replace(/\\/g, '/')}`
    console.error(`run-bash: wslpath unavailable; using ${target} inside the distribution`)
  }
}

const result = spawnSync(shell.command, [...shell.prefixArgs, target, ...scriptArgs], { stdio: 'inherit' })
if (result.error) {
  console.error(`run-bash: ${result.error.message}`)
  process.exit(127)
}
process.exit(result.status ?? 1)
