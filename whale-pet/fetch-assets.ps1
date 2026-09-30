# Fetch ready-made whale-girl (鲸鱼娘) pet assets from open-source projects.
#
# Sources (both permissive):
#   touche-s/rice-loving-whale          MIT  - 傲娇鲸鱼娘 GIF 动作集
#   crossoverthere/dsh-whale-desktop    MIT  - 蓝色大肥鱼 WebP 状态图集
#
# Network mirrors are tried in order, because raw.githubusercontent.com is often
# unreachable from mainland China. Run this again any time to refresh assets.
[CmdletBinding()]
param(
  [string]$OutDir = '',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $here) { $here = (Get-Location).Path }
if (-not $OutDir) { $OutDir = Join-Path $here 'assets' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sources = @(
  # --- rice-loving-whale (MIT): animated GIF states ---------------------------------
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/idle.gif';      Save = 'rlw-idle.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/thinking.gif';  Save = 'rlw-thinking.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/sleep.gif';     Save = 'rlw-sleep.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/happy.gif';     Save = 'rlw-happy.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/pat.gif';       Save = 'rlw-pat.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/question.gif';  Save = 'rlw-question.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/approval.gif';  Save = 'rlw-approval.gif' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/tray.png';      Save = 'rlw-tray.png' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'electron/assets/whale-avatar.png'; Save = 'rlw-avatar.png' }
  @{ Repo = 'touche-s/rice-loving-whale'; Path = 'LICENSE';                       Save = 'LICENSE.rice-loving-whale.txt' }

  # --- dsh-whale-desktop (MIT): 蓝色大肥鱼 state stills ------------------------------
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-idle-cute.webp';  Save = 'bigfish-idle.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-thinking.webp';   Save = 'bigfish-thinking.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-running.webp';    Save = 'bigfish-running.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-sleep.webp';      Save = 'bigfish-sleep.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-wink.webp';       Save = 'bigfish-wink.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-tail-swing.webp'; Save = 'bigfish-tail-swing.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/generated/dsh-whale-state-greet.webp';      Save = 'bigfish-greet.webp' }
  @{ Repo = 'crossoverthere/dsh-whale-desktop'; Path = 'vendor/whale/LICENSE';                                   Save = 'LICENSE.dsh-whale-desktop.txt' }
)

function Get-MirrorUrls([string]$repo, [string]$file) {
  @(
    "https://cdn.jsdelivr.net/gh/$repo@main/$file"
    "https://raw.githubusercontent.com/$repo/main/$file"
    "https://ghproxy.net/https://raw.githubusercontent.com/$repo/main/$file"
    "https://gh-proxy.com/https://raw.githubusercontent.com/$repo/main/$file"
  )
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$ok = 0; $skip = 0; $fail = @()
foreach ($s in $sources) {
  $dest = Join-Path $OutDir $s.Save
  if ((Test-Path $dest) -and -not $Force -and (Get-Item $dest).Length -gt 0) { $skip++; continue }

  $done = $false
  foreach ($url in Get-MirrorUrls $s.Repo $s.Path) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 40
      if ((Get-Item $dest).Length -gt 0) {
        Write-Host ("  ok   {0,-26} {1,9:N0} B  <- {2}" -f $s.Save, (Get-Item $dest).Length, ([Uri]$url).Host)
        $done = $true; $ok++
        break
      }
    } catch {
      # try next mirror
    }
  }
  if (-not $done) {
    $fail += $s.Save
    Write-Warning ("  FAIL {0}" -f $s.Save)
    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host ""
Write-Host "assets -> $OutDir"
Write-Host ("downloaded={0} skipped={1} failed={2}" -f $ok, $skip, $fail.Count)
if ($fail.Count) { Write-Host ("failed: " + ($fail -join ', ')) }

# ---------------------------------------------------------------------------
# 后处理：webp -> png（WPF 不支持 webp）+ 各状态素材尺寸归一化（norm-*）
# 逻辑都在 prepare-assets.py，这里只负责找 python 并调用
# ---------------------------------------------------------------------------
function Find-Python {
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $roots = @()
  if ($env:DSH_HOME) { $roots += (Join-Path $env:DSH_HOME 'dsh-runtimes') }
  $roots += (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes')
  foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    $hit = Get-ChildItem $r -Recurse -Filter python.exe -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\Lib\\' } | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

function Invoke-PrepareAssets([string]$dir) {
  $script = Join-Path $here 'prepare-assets.py'
  if (-not (Test-Path $script)) { return }
  $py = Find-Python
  if (-not $py) {
    Write-Warning '找不到 python/Pillow，跳过素材后处理（.webp 会被桌宠忽略，GIF 保持原尺寸）'
    return
  }
  try { & $py $script $dir } catch { Write-Warning ("素材后处理失败：{0}" -f $_.Exception.Message) }
}
Invoke-PrepareAssets $OutDir

if ($ok -eq 0 -and $skip -eq 0) { exit 1 }
