# 把鲸鱼娘桌宠接成 DSH 插件：Harness 启动时自动拉起，Harness 退出时自动关闭。
#
# 只做两件事（都会先备份）：
#   1. 往 <profile>\cordis.patch.yml 追加一段带标记的 insert 行
#   2. （package 模式）把 dsh-plugin\ 复制到 <profile>\node_modules\dsh-whale-pet\
#
# 用法
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-plugin.ps1              # 安装
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-plugin.ps1 -DryRun      # 只看会改什么
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-plugin.ps1 -Uninstall   # 卸载
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-plugin.ps1 -Mode fileurl # 不复制包，直接指向本目录
[CmdletBinding()]
param(
  [ValidateSet('package', 'fileurl')][string]$Mode = 'package',
  [switch]$Uninstall,
  [switch]$DryRun,
  [string]$ProfileDir = ''
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$bundleSrc = Join-Path $here 'dsh-plugin'
$petScript = Join-Path $here 'WhalePet.ps1'

if (-not (Test-Path (Join-Path $bundleSrc 'index.js'))) { throw "找不到插件目录: $bundleSrc" }
if (-not (Test-Path $petScript)) { throw "找不到桌宠主脚本: $petScript" }

# --- profile 目录 -----------------------------------------------------------
if (-not $ProfileDir) {
  if ($env:DSH_PROFILE_DIR -and (Test-Path $env:DSH_PROFILE_DIR)) { $ProfileDir = $env:DSH_PROFILE_DIR }
  elseif ($env:DSH_HOME -and (Test-Path (Join-Path $env:DSH_HOME 'profiles\desktop'))) { $ProfileDir = Join-Path $env:DSH_HOME 'profiles\desktop' }
  else { $ProfileDir = Join-Path $env:USERPROFILE '.dsh\profiles\desktop' }
}
if (-not (Test-Path $ProfileDir)) { throw "找不到 profile 目录: $ProfileDir" }

$patchFile = Join-Path $ProfileDir 'cordis.patch.yml'
$pkgDir = Join-Path $ProfileDir 'node_modules\dsh-whale-pet'
$pkgName = if ($Mode -eq 'fileurl') {
  'file:///' + ((Join-Path $bundleSrc 'index.js').Replace('\', '/'))
} else {
  'dsh-whale-pet'
}

$BEGIN = '# >>> whale-pet (DSH 鲸鱼娘桌宠启动器) —— 由 install-plugin.ps1 写入，勿手改 >>>'
$END = '# <<< whale-pet <<<'

function Get-PatchText {
  if (-not (Test-Path $patchFile)) { return '' }
  return ([System.IO.File]::ReadAllText($patchFile, [System.Text.Encoding]::UTF8)).TrimStart([char]0xFEFF)
}

function Remove-WhalePetBlock([string]$text) {
  $pattern = "(?s)\r?\n?" + [regex]::Escape($BEGIN) + ".*?" + [regex]::Escape($END) + "\r?\n?"
  return ([regex]::Replace($text, $pattern, "`n")).TrimEnd() + "`n"
}

# YAML 单引号字符串里，单引号用两个单引号转义
$petScriptYaml = $petScript.Replace("'", "''")
$block = @"
$BEGIN
- insert:
    - id: whale-pet
      name: '$pkgName'
      config:
        petScript: '$petScriptYaml'
        startDelayMs: 1200
$END
"@

Write-Host "profile   : $ProfileDir"
Write-Host "patch     : $patchFile"
Write-Host "mode      : $Mode  (row name = $pkgName)"
Write-Host "pet script: $petScript"
Write-Host ""

$original = Get-PatchText
$cleaned = Remove-WhalePetBlock $original

if ($Uninstall) {
  $new = $cleaned
  Write-Host '--- 将要写入的 cordis.patch.yml ---'
  Write-Host $new
  if (-not $DryRun) {
    if (Test-Path $patchFile) {
      $bak = "$patchFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
      Copy-Item $patchFile $bak -Force
      Write-Host "已备份原文件 -> $bak"
    }
    [System.IO.File]::WriteAllText($patchFile, $new, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force; Write-Host "已删除 $pkgDir" }
    Write-Host ''
    Write-Host '卸载完成。重启 Harness 后生效。'
  } else {
    Write-Host '(DryRun：没有写入任何文件)'
  }
  return
}

$new = $cleaned.TrimEnd() + "`n`n" + $block + "`n"
Write-Host '--- 将要写入的 cordis.patch.yml ---'
Write-Host $new

if ($DryRun) {
  Write-Host '(DryRun：没有写入任何文件)'
  return
}

# 备份 + 写 patch
if (Test-Path $patchFile) {
  $bak = "$patchFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Copy-Item $patchFile $bak -Force
  Write-Host "已备份原文件 -> $bak"
}
[System.IO.File]::WriteAllText($patchFile, $new, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写入 $patchFile"

# package 模式：把插件包复制到 profile 的 node_modules
if ($Mode -eq 'package') {
  if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
  New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
  Copy-Item (Join-Path $bundleSrc '*') $pkgDir -Recurse -Force
  Write-Host "已复制插件包 -> $pkgDir"
}

Write-Host ''
Write-Host '安装完成：profile 会被热加载，几秒内 Harness 就会自动拉起鲸鱼娘桌宠；'
Write-Host '若没反应，重启一次 Harness。之后 Harness 启动时自动拉起、退出时自动关闭。'
Write-Host "想撤销：powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here 'install-plugin.ps1')`" -Uninstall"
