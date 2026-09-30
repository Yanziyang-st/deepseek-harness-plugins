# 回归测试：已有桌宠在跑时，新实例应当接管（关掉旧实例）而不是直接退出
$ErrorActionPreference = 'Stop'

if (-not ('WU' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WU {
    public delegate bool EP(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    public static List<uint> Pets() {
        List<uint> res = new List<uint>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
            if (t.ToString() != "DSH 鲸鱼娘") return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (!res.Contains(pid)) res.Add(pid);
            return true;
        }, IntPtr.Zero);
        return res;
    }
}
'@
}

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$qa = Join-Path $env:TEMP 'whale-qa2'
if (Test-Path $qa) { Remove-Item $qa -Recurse -Force }
New-Item -ItemType Directory -Path $qa -Force | Out-Null
$log = Join-Path $here 'whale-pet.log'
if (Test-Path $log) { Remove-Item $log -Force }

$args1 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'WhalePet.ps1'),
           '-TargetProcess', 'TakeoverDummy', '-TargetTitleLike', 'TakeoverDummy', '-NoTray', '-Log')

Write-Host '--- 启动第 1 个实例 ---'
$a = Start-Process powershell.exe -PassThru -RedirectStandardOutput (Join-Path $qa 'a.txt') -RedirectStandardError (Join-Path $qa 'a-err.txt') -ArgumentList $args1
Start-Sleep -Seconds 5
$pids1 = [WU]::Pets()
Write-Host ("第 1 个实例 pid={0}, 桌宠窗口属于: {1}" -f $a.Id, ($pids1 -join ','))

Write-Host '--- 启动第 2 个实例（应当接管）---'
$b = Start-Process powershell.exe -PassThru -RedirectStandardOutput (Join-Path $qa 'b.txt') -RedirectStandardError (Join-Path $qa 'b-err.txt') -ArgumentList $args1
Start-Sleep -Seconds 7
$pids2 = [WU]::Pets()
Write-Host ("第 2 个实例 pid={0}, 桌宠窗口属于: {1}" -f $b.Id, ($pids2 -join ','))
Write-Host ("第 1 个实例还活着吗: {0}" -f (-not $a.HasExited))
Write-Host ("第 2 个实例还活着吗: {0}" -f (-not $b.HasExited))
Write-Host ("窗口 pid 是否已换成第 2 个: {0}" -f (($pids2.Count -eq 1) -and ($pids2[0] -eq $b.Id)))

Write-Host '--- 日志 ---'
Get-Content $log -Encoding UTF8 | Select-String -Pattern 'taking over|takeover|started:|state ->|已启动|already' | ForEach-Object { '  ' + ($_.Line -replace '^\[\S+\] ', '') }

Stop-Process -Id $a.Id -Force -EA SilentlyContinue
Stop-Process -Id $b.Id -Force -EA SilentlyContinue
Start-Sleep -Milliseconds 500
Remove-Item $qa -Recurse -Force -EA SilentlyContinue
