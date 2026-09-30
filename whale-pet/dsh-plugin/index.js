/**
 * dsh-whale-pet —— 让鲸鱼娘桌宠跟着 DeepSeek Harness 一起启动 / 退出
 *
 * Harness 启动（插件 apply）时拉起桌宠进程；Harness 退出（插件卸载 dispose）时
 * 用 `taskkill /T /F` 连同进程树一起收掉，不留孤儿进程。
 *
 * 配置（profile patch 里这一行的 config，全部可选）：
 *   petScript     桌宠主脚本 WhalePet.ps1 的绝对路径（默认按 bundle 相对位置找）
 *   powershell    powershell.exe 路径（默认用系统自带的 Windows PowerShell）
 *   extraArgs     追加给 WhalePet.ps1 的参数数组，例如 ["-Scale","1.2"]
 *   startDelayMs  启动延迟毫秒，默认 1200（等 Harness 主窗口就绪一点）
 *   环境变量 DSH_WHALE_PET_SCRIPT 也可指定桌宠脚本路径
 *
 * 注意 cordis 的 effect 语义：`ctx.effect(body)` 的 body 会**立即执行**，
 * 它**返回**的函数才是卸载时的清理逻辑。写成 `ctx.effect(() => { cleanup() })`
 * 会在插件加载瞬间就执行 cleanup（即刚拉起桌宠就把它杀掉）。
 */
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'whale-pet'

const here = path.dirname(fileURLToPath(import.meta.url))

function firstExisting(list) {
  for (const p of list) {
    if (!p) continue
    try {
      if (existsSync(p)) return p
    } catch { /* ignore */ }
  }
  return null
}

function resolvePetScript(config) {
  return firstExisting([
    config && config.petScript,
    process.env.DSH_WHALE_PET_SCRIPT,
    path.resolve(here, '..', 'WhalePet.ps1'),        // bundle 与主脚本同级
    path.resolve(here, '..', '..', 'WhalePet.ps1'),  // bundle 位于 <whale-pet>/dsh-plugin/
    path.resolve(here, 'WhalePet.ps1'),
  ])
}

function resolvePowerShell(config) {
  if (config && config.powershell) return config.powershell
  const root = process.env.SystemRoot || 'C:\\Windows'
  return firstExisting([
    path.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
  ]) || 'powershell.exe'
}

function killTree(pid, log) {
  if (!pid) return
  const root = process.env.SystemRoot || 'C:\\Windows'
  const full = path.join(root, 'System32', 'taskkill.exe')
  const exe = existsSync(full) ? full : 'taskkill'
  try {
    const tk = spawn(exe, ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true })
    tk.on('error', (e) => log('warn', '[whale-pet] taskkill 调用失败：' + (e && e.message)))
    tk.on('exit', (code) => {
      if (code !== 0) log('warn', '[whale-pet] taskkill 退出码 ' + code + '（桌宠可能已自行退出）')
    })
    tk.unref()
  } catch (e) {
    log('warn', '[whale-pet] taskkill 异常：' + (e && e.message))
  }
}

/** 只有确认进程还活着才允许对它 taskkill：Node 没收到 exit 事件时 pid 可能已被系统复用。 */
function stillAlive(child) {
  if (child.exitCode !== null || child.signalCode !== null) return false
  try {
    process.kill(child.pid, 0)
    return true
  } catch {
    return false
  }
}

export function apply(ctx, config = {}) {
  const log = (level, msg) => {
    try { ctx?.logger?.[level]?.(msg) } catch { /* ignore */ }
  }

  const script = resolvePetScript(config)
  const powershell = resolvePowerShell(config)
  const delay = Number.isFinite(config.startDelayMs) ? config.startDelayMs : 1200

  let child = null
  let stopped = false

  const start = () => {
    if (stopped || child) return
    if (!script) {
      log('warn', '[whale-pet] 没找到 WhalePet.ps1，跳过桌宠启动（可用 config.petScript 或环境变量 DSH_WHALE_PET_SCRIPT 指定）')
      return
    }
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script]
      .concat(Array.isArray(config.extraArgs) ? config.extraArgs : [])
    try {
      child = spawn(powershell, args, { cwd: path.dirname(script), stdio: 'ignore', windowsHide: true })
      child.on('error', (e) => {
        log('warn', '[whale-pet] 桌宠进程出错：' + (e && e.message))
        child = null
      })
      child.on('exit', (code) => {
        log('info', '[whale-pet] 桌宠进程已退出（code ' + code + '）')
        child = null
      })
      log('info', '[whale-pet] 已拉起桌宠 pid=' + child.pid + ' script=' + script)
    } catch (e) {
      log('warn', '[whale-pet] 启动桌宠失败：' + (e && e.message))
      child = null
    }
  }

  const timer = setTimeout(start, delay)

  // body 立即执行并返回清理函数：卸载（Harness 退出 / 插件被停用）时关闭桌宠
  ctx.effect(() => () => {
    stopped = true
    try { clearTimeout(timer) } catch { /* ignore */ }
    if (child && child.pid && stillAlive(child)) {
      const pid = child.pid
      try { child.kill() } catch { /* ignore */ }
      killTree(pid, log)
      log('info', '[whale-pet] Harness 退出，已关闭桌宠 pid=' + pid)
    } else if (child && child.pid) {
      // 进程早就没了（或本来就因单实例锁立刻退出）：绝不能再按这个 pid 去 taskkill，
      // Windows 会回收复用 pid，盲目 kill 有可能误杀别的进程。
      log('info', '[whale-pet] 桌宠进程已不在，跳过关闭（pid=' + child.pid + '）')
    }
    child = null
  }, 'whale-pet: stop desktop pet')

  start()   // 不依赖延迟回调（某些运行环境不执行 apply 里的 setTimeout）
  log('info', '[whale-pet] 鲸鱼娘桌宠启动器已加载：Harness 启动时拉起，退出时关闭')
}
