/**
 * dsh-whale-pet 插件自测：用 mock ctx 复刻 cordis 的 effect 语义
 * （body 立即执行，其返回值是 dispose 时的清理函数），然后：
 *   1. apply 后确认桌宠进程真的被拉起
 *   2. 触发 disposer（模拟 Harness 退出）后确认桌宠进程真的被杀掉
 *
 * 用法: node test-plugin.mjs
 *
 * 存活判定用两个探针取「与」：Node 的 process.kill(pid,0) 和 PowerShell 的
 * Get-Process。受限 shell（比如 DSH 沙箱）里前者会误报存活，靠后者纠正；
 * 若 PowerShell 探针不可用则回退到只用前者。
 */
import path from 'node:path'
import { spawn } from 'node:child_process'
import { existsSync, readFileSync, rmSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
// 脚本既可能放在 whale-pet/ 根目录，也可能放在子目录里
const petDir = existsSync(path.join(here, 'WhalePet.ps1')) ? here : path.resolve(here, '..')
const pluginPath = path.join(petDir, 'dsh-plugin', 'index.js')
const petScript = path.join(petDir, 'WhalePet.ps1')
const pluginUrl = 'file:///' + pluginPath.replace(/\\/g, '/')

const nodeAlive = (p) => {
  if (!p) return false
  try { process.kill(p, 0); return true } catch { return false }
}

/** 让 PowerShell 用 Get-Process 探一次，结果写文件（受限 shell 下不能走管道） */
function psProbe(pid) {
  const file = path.join(petDir, `.probe-${pid}.txt`)
  try { rmSync(file, { force: true }) } catch { /* ignore */ }
  const ps = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32',
    'WindowsPowerShell', 'v1.0', 'powershell.exe')
  const cmd = `$p = Get-Process -Id ${pid} -ErrorAction SilentlyContinue; ` +
    `Set-Content -Path '${file}' -Value $(if ($p) { 'alive' } else { 'gone' }) -Encoding ASCII`
  return new Promise((resolve) => {
    let done = false
    const finish = (v) => { if (!done) { done = true; resolve(v) } }
    try {
      const child = spawn(ps, ['-NoProfile', '-NonInteractive', '-Command', cmd],
        { stdio: 'ignore', windowsHide: true })
      child.on('error', () => finish('unknown'))
      child.on('exit', () => {
        try { finish(readFileSync(file, 'utf8').trim()) } catch { finish('unknown') }
      })
      setTimeout(() => finish('unknown'), 8000)
    } catch { finish('unknown') }
  })
}

async function alive(pid) {
  const n = nodeAlive(pid)
  const p = await psProbe(pid)
  return { node: n, powershell: p, alive: n && (p === 'alive' || p === 'unknown') }
}

const logs = []
const disposers = []
const ctx = {
  logger: {
    info: (m) => logs.push(['info', String(m)]),
    warn: (m) => logs.push(['warn', String(m)]),
    error: (m) => logs.push(['error', String(m)]),
  },
  // cordis: effect(body) —— body 立即执行，返回的 disposer 在 fiber 卸载时运行
  effect(body, label) {
    const disposer = body()
    disposers.push({ disposer, label })
    return disposer
  },
}

const mod = await import(pluginUrl)
const result = { pluginPath, exports: Object.keys(mod), checks: {}, logs }

mod.apply(ctx, {
  petScript,
  startDelayMs: 0,
  // 用一个不存在的目标进程/标题 + KeepAlive，避免影响用户真实桌宠和它的单实例锁
  extraArgs: ['-TargetProcess', 'WhalePetSelfTestDummy', '-TargetTitleLike', 'WhalePetSelfTestDummy', '-NoTray', '-KeepAlive'],
})

await new Promise((r) => setTimeout(r, 5000))

const pidMatch = logs.map((l) => l[1]).join('\n').match(/pid=(\d+)/)
const pid = pidMatch ? Number(pidMatch[1]) : 0

result.pid = pid
result.checks.effectRegistered = disposers.length === 1
result.checks.spawned = pid > 0
result.checks.loggedStart = logs.some((l) => l[0] === 'info' && l[1].includes('已拉起桌宠'))

const before = await alive(pid)
result.probeBeforeDispose = before
result.checks.aliveAfterStart = before.alive

for (const d of disposers) {
  try { await d.disposer() } catch (e) { logs.push(['error', 'disposer threw: ' + e.message]) }
}
await new Promise((r) => setTimeout(r, 3500))

const after = await alive(pid)
result.probeAfterDispose = after
result.checks.aliveAfterDispose = after.alive
result.checks.loggedStop = logs.some((l) => l[1].includes('已关闭桌宠'))

try { rmSync(path.join(petDir, `.probe-${pid}.txt`), { force: true }) } catch { /* ignore */ }

result.pass = result.checks.effectRegistered && result.checks.spawned &&
  result.checks.aliveAfterStart && result.checks.aliveAfterDispose === false

console.log(JSON.stringify(result, null, 2))
process.exit(result.pass ? 0 : 1)
