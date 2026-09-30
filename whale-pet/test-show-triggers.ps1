# 回归测试：桌宠的三种"浮出"触发
#   [1] 目标窗口在最前台        -> 躲起来
#   [2] 点最小化                -> 浮出，基准素材 idle
#   [3] 恢复并在最前台          -> 躲起来
#   [4] 点关闭（收进托盘/窗口隐藏）-> 浮出，基准素材 sleep
#   [5] 从托盘恢复并在最前台    -> 躲起来
#   [6] 被别的窗口压住/失焦     -> 浮出，基准素材 idle（按最小化逻辑）
#   [7] 重新回到最前台          -> 躲起来
$ErrorActionPreference = 'Stop'

if (-not ('WX' -as [type])) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WX {
    public delegate bool EP(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);

    public class I { public IntPtr H; public uint Pid; public string C; public bool V; public bool M; }
    public static List<I> All() {
        List<I> res = new List<I>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            var c = new StringBuilder(256); GetClassNameW(h, c, 256);
            I i = new I(); i.H = h; i.Pid = pid; i.C = c.ToString();
            i.V = IsWindowVisible(h); i.M = IsIconic(h);
            res.Add(i); return true;
        }, IntPtr.Zero);
        return res;
    }
    public static uint PetPid() {
        uint found = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
            if (t.ToString() == "DSH 鲸鱼娘") { uint pid; GetWindowThreadProcessId(h, out pid); found = pid; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    // 指定 pid 的桌宠窗口当前是否可见
    // （机器上可能同时跑着别的桌宠实例，必须按 pid 过滤，否则测不准）
    public static bool PetVisibleFor(uint want) {
        bool vis = false;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid != want) return true;
            var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
            if (t.ToString() == "DSH 鲸鱼娘" && IsWindowVisible(h)) { vis = true; return false; }
            return true;
        }, IntPtr.Zero);
        return vis;
    }
    // 前台锁定：先 AttachThreadInput 再 SetForegroundWindow，否则后台进程抢不到前台
    public static void ForceForeground(IntPtr h) {
        IntPtr fg = GetForegroundWindow();
        uint dummy;
        uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out dummy);
        uint myThread = GetCurrentThreadId();
        bool attached = fgThread != 0 && fgThread != myThread && AttachThreadInput(myThread, fgThread, true);
        ShowWindow(h, 9);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        if (attached) AttachThreadInput(myThread, fgThread, false);
    }
}
'@
}

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$qa = Join-Path $env:TEMP 'whale-qa3'
if (Test-Path $qa) { Remove-Item $qa -Recurse -Force }
New-Item -ItemType Directory -Path $qa -Force | Out-Null
$log = Join-Path $here 'whale-pet.log'
if (Test-Path $log) { Remove-Item $log -Force }

$origFg = [WX]::GetForegroundWindow()

# 替身"Harness"窗口（独立进程，进程名 WhaleTestHost）
$hostExe = Join-Path $qa 'WhaleTestHost.exe'
Copy-Item "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" $hostExe -Force
$code = "Add-Type -AssemblyName System.Windows.Forms; `$f = New-Object System.Windows.Forms.Form; `$f.Text = 'WhaleTestHost'; `$f.Width = 460; `$f.Height = 320; [System.Windows.Forms.Application]::Run(`$f)"
$hp = Start-Process $hostExe -PassThru -RedirectStandardOutput (Join-Path $qa 'h.txt') -RedirectStandardError (Join-Path $qa 'he.txt') -ArgumentList @('-NoProfile', '-STA', '-Command', $code)
Start-Sleep -Seconds 3
$tw = @([WX]::All() | Where-Object { $_.Pid -eq $hp.Id -and $_.C -like 'WindowsForms*' }) | Select-Object -First 1
if (-not $tw) { Write-Host 'FAIL: 替身窗口没起来'; Stop-Process -Id $hp.Id -Force -EA SilentlyContinue; exit 1 }

# 另一个无关窗口（用来把"Harness"挤到后面）
$other = New-Object System.Windows.Forms.Form
$other.Text = 'NotTheHarness'
$other.Width = 380; $other.Height = 240
$other.StartPosition = 'CenterScreen'
$other.Show()

# 被测桌宠：只认 WhaleTestHost
$pet = Start-Process powershell.exe -PassThru -RedirectStandardOutput (Join-Path $qa 'p.txt') -RedirectStandardError (Join-Path $qa 'pe.txt') -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'WhalePet.ps1'),
  '-TargetProcess', 'WhaleTestHost', '-TargetTitleLike', 'WhaleTestHost', '-NoTray', '-Log'
)
Start-Sleep -Seconds 6

function PetVisible { [WX]::PetVisibleFor([uint32]$pet.Id) }
function Tail($n) {
  (Get-Content $log -Encoding UTF8 | Select-String -Pattern 'show mode ->|state ->|pet shown|pet hidden' |
    Select-Object -Last $n | ForEach-Object { ($_.Line -replace '^\[\S+\] ', '') }) -join ' | '
}
# 抢前台有时会被 Windows 前台锁定挡住，带校验重试
function Set-Foreground([IntPtr]$h, [string]$what) {
  for ($i = 0; $i -lt 6; $i++) {
    [WX]::ForceForeground($h)
    Start-Sleep -Milliseconds 300
    if ([WX]::GetForegroundWindow() -eq $h) { return $true }
  }
  Write-Host ("     ! 抢前台失败（{0}），本步判断可能不准" -f $what)
  return $false
}

[void](Set-Foreground $tw.H '目标窗口')
Start-Sleep -Seconds 4
"[1] 目标在最前台      -> 桌宠可见=$(PetVisible)  (期望 False)"

[void][WX]::ShowWindow($tw.H, 6)   # SW_MINIMIZE
Start-Sleep -Seconds 4
"[2] 点最小化          -> 桌宠可见=$(PetVisible)  (期望 True)   $(Tail 2)"

[void](Set-Foreground $tw.H '恢复目标')
Start-Sleep -Seconds 4
"[3] 恢复并在最前台    -> 桌宠可见=$(PetVisible)  (期望 False)"

[void][WX]::ShowWindow($tw.H, 0)   # SW_HIDE -> 模拟关闭到托盘
Start-Sleep -Seconds 4
"[4] 关闭（收进托盘）  -> 桌宠可见=$(PetVisible)  (期望 True)   $(Tail 2)"

[void](Set-Foreground $tw.H '从托盘恢复')
Start-Sleep -Seconds 4
"[5] 从托盘恢复+最前台 -> 桌宠可见=$(PetVisible)  (期望 False)"

[void](Set-Foreground $other.Handle '无关窗口')   # 把无关窗口拉到前面 -> Harness 失焦
Start-Sleep -Seconds 4
"[6] Harness 被压住    -> 桌宠可见=$(PetVisible)  (期望 True)   $(Tail 2)"

[void](Set-Foreground $tw.H '回到前台')
Start-Sleep -Seconds 4
"[7] Harness 回到前台  -> 桌宠可见=$(PetVisible)  (期望 False)"

Stop-Process -Id $pet.Id -Force -EA SilentlyContinue
Stop-Process -Id $hp.Id -Force -EA SilentlyContinue
$other.Close(); $other.Dispose()
if ($origFg -ne [IntPtr]::Zero) { [WX]::ForceForeground($origFg) }   # 把焦点还给用户原来的窗口
Start-Sleep -Milliseconds 500
Remove-Item $hostExe -Force -EA SilentlyContinue

Write-Host '--- 全部相关日志 ---'
Get-Content $log -Encoding UTF8 | Select-String -Pattern 'show mode|state ->|pet shown|pet hidden|dsh:' | ForEach-Object { '  ' + ($_.Line -replace '^\[\S+\] ', '') }
