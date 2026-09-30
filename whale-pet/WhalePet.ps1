<#
  WhalePet.ps1 — DeepSeek Harness 鲸鱼娘桌面宠物
  ---------------------------------------------------------------------------
  行为：Harness 窗口最小化后，桌面上浮出鲸鱼娘；窗口恢复后自动隐藏。

  特性
    * 零安装：Windows PowerShell 5.1 + WPF，无需 Node/Electron/第三方模块
    * 透明置顶无边框浮窗，空白处鼠标穿透，可拖动，位置自动记忆
    * 优先使用 assets/ 里现成的开源鲸鱼娘素材（GIF 动图 / PNG 静图），
      没有素材时自动回退到内置矢量自绘鲸鱼娘（WhaleArt.xaml）
    * 感知 Harness 状态：干活中 / 等你回答 / 空闲 / 睡着
    * 单击摸摸头、双击恢复 Harness、右键菜单、托盘图标、滚轮缩放、气泡台词
    * 单实例运行，开机自启可选

  用法
    powershell -NoProfile -ExecutionPolicy Bypass -File WhalePet.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File WhalePet.ps1 -ForceShow   # 立即常驻显示
    powershell -NoProfile -ExecutionPolicy Bypass -File WhalePet.ps1 -ListWindows # 诊断窗口匹配
#>
[CmdletBinding()]
param(
  [string]$TargetProcess = 'DeepSeek Harness',
  [string]$TargetTitleLike = 'Harness',
  [int]$ShowDelayMs = 450,          # 最小化后延迟多久浮出（防抖）
  [double]$Scale = 1.0,             # 初始缩放
  [int]$SleepAfterSec = 0,          # 最小化后多久转打瞌睡（0=不转；关闭到托盘一律用 sleep）
  [int]$HarnessGoneGraceSec = 20,   # Harness 彻底消失多久后桌宠自行退出
  [switch]$KeepAlive,               # 不做「Harness 消失就退出」的看门狗
  [switch]$NoFocusTrigger,          # 关掉「Harness 失去焦点/被压住也浮出」这条触发
  [switch]$ForceShow,               # 调试：忽略 Harness 状态，一直显示
  [switch]$NoTray,                  # 不创建托盘图标
  [switch]$Log,                     # 同时在控制台输出日志（日志文件始终会写）
  [string]$Snapshot = '',           # 调试：把窗口内容渲染成 PNG 后退出
  [string]$ForceState = '',         # 调试：强制停在某个状态（idle/busy/waiting/sleep/pat/greet）
  [switch]$ListWindows              # 列出候选窗口后退出
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. 基础环境
# ---------------------------------------------------------------------------
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $here) { $here = (Get-Location).Path }

$script:LogPath = Join-Path $here 'whale-pet.log'
$script:SettingsPath = Join-Path $here 'settings.json'
$script:AssetsDir = Join-Path $here 'assets'

function Write-Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss.fff'), $msg
  if ($Log) { Write-Host $line }
  try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
if (-not $NoTray) { Add-Type -AssemblyName System.Windows.Forms }

# Win32 互操作（窗口枚举 / 最小化判断 / 恢复窗口）
if (-not ('WhaleWin32' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WhaleWin32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int val);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    public class WinInfo {
        public IntPtr Handle;
        public uint Pid;
        public string Title;
        public string Class;
        public bool Visible;
        public bool Minimized;
        public int Area;
    }

    public static List<WinInfo> TopLevelWindows() {
        List<WinInfo> list = new List<WinInfo>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            StringBuilder t = new StringBuilder(512);
            GetWindowTextW(h, t, 512);
            StringBuilder c = new StringBuilder(256);
            GetClassNameW(h, c, 256);
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r; GetWindowRect(h, out r);
            WinInfo w = new WinInfo();
            w.Handle = h; w.Pid = pid; w.Title = t.ToString(); w.Class = c.ToString();
            w.Visible = IsWindowVisible(h); w.Minimized = IsIconic(h);
            w.Area = Math.Max(0, r.Right - r.Left) * Math.Max(0, r.Bottom - r.Top);
            list.Add(w);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static bool RestoreWindow(IntPtr h) {
        ShowWindow(h, 9);        // SW_RESTORE
        BringWindowToTop(h);
        SetForegroundWindow(h);
        return true;
    }

    public static void MarkToolWindow(IntPtr h) {
        int ex = GetWindowLong(h, -20);
        SetWindowLong(h, -20, ex | 0x00000080);   // WS_EX_TOOLWINDOW -> 不出现在 Alt+Tab
    }
}
'@
}

# ---------------------------------------------------------------------------
# 1. 配置读写
# ---------------------------------------------------------------------------
$script:Cfg = [ordered]@{
  Left        = $null
  Top         = $null
  Scale       = $Scale
  ShowBubble  = $true
  Topmost     = $true
  UseAssetArt = $true
  ArtMode     = 'stills'            # stills = 512px 高清静图；gifs = 居中裁剪的动图
  Autostart   = $false
  # 注意：不持久化 TargetProcess —— 它是启动参数，写进配置文件后会让
  # 插件（不带参数）启动的桌宠读到过期的目标进程名。
}

function Import-Settings {
  if (-not (Test-Path $script:SettingsPath)) { return }
  try {
    $raw = [System.IO.File]::ReadAllText($script:SettingsPath, [System.Text.Encoding]::UTF8)
    $o = $raw | ConvertFrom-Json
    foreach ($p in $o.PSObject.Properties) {
      if ($script:Cfg.Contains($p.Name)) { $script:Cfg[$p.Name] = $p.Value }
    }
    if ($script:Cfg.Scale) { $script:ScaleFactor = [double]$script:Cfg.Scale } else { $script:ScaleFactor = 1.0 }
    Write-Log "settings loaded: scale=$($script:ScaleFactor) bubble=$($script:Cfg.ShowBubble)"
  } catch { Write-Log "settings load failed: $($_.Exception.Message)" }
}

function Export-Settings {
  try {
    $script:Cfg.Scale = $script:ScaleFactor
    $json = $script:Cfg | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
  } catch { Write-Log "settings save failed: $($_.Exception.Message)" }
}

Import-Settings
# TargetProcess / TargetTitleLike 只认命令行（插件启动时不带参数，用默认的 Harness 匹配）
if ($PSBoundParameters.ContainsKey('TargetProcess')) { $script:TargetProcess = $TargetProcess }
if ($PSBoundParameters.ContainsKey('TargetTitleLike')) { $script:TargetTitleLike = $TargetTitleLike }
if ($PSBoundParameters.ContainsKey('Scale')) { $script:ScaleFactor = $Scale }
if (-not $script:ScaleFactor) { $script:ScaleFactor = 1.0 }

# ---------------------------------------------------------------------------
# 2. 找到 Harness 主窗口
# ---------------------------------------------------------------------------
function Test-TargetWindow([object]$w, [hashtable]$pids) {
  if ([string]::IsNullOrWhiteSpace($w.Title)) { return $false }
  if ($w.Area -le 0) { return $false }
  # 排除控制台/输入法/工具类窗口：它们常常比真正的主窗口还大
  if ($w.Class -match '^(ConsoleWindowClass|GDI\+ Hook Window Class|IME|MSCTFIME UI|CiceroUIWndFrame|Shell_TrayWnd|Progman|WorkerW)') { return $false }
  if ($w.Class -like '.NET-BroadcastEventWindow*') { return $false }
  if ($w.Class -like 'HwndWrapper*') { return $false }          # WPF 窗口（含桌宠自己）
  if ($w.Title -eq 'DSH 鲸鱼娘') { return $false }

  $byName = $pids.ContainsKey($w.Pid)
  $byTitle = $false
  if (-not [string]::IsNullOrWhiteSpace($script:TargetTitleLike)) {
    $byTitle = $w.Title.IndexOf($script:TargetTitleLike, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  }
  return ($byName -or $byTitle)
}

function Get-TargetWindow {
  $pids = @{}
  try {
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
      if ($p.ProcessName -like "*$script:TargetProcess*") { $pids[[uint32]$p.Id] = $true }
    }
  } catch { }

  $best = $null; $bestScore = -1
  foreach ($w in [WhaleWin32]::TopLevelWindows()) {
    if (-not (Test-TargetWindow $w $pids)) { continue }

    # 优先浏览器/Electron 主窗口（Chrome_WidgetWin_*），其次可见的大窗口
    $score = $w.Area
    if ($w.Class -eq 'Chrome_WidgetWin_1' -or $w.Class -eq 'Chrome_WidgetWin_0') { $score += 1000000000 }
    if ($w.Visible) { $score += 1000000 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $w }
  }
  return $best
}

if ($ListWindows) {
  Write-Host ("候选窗口（进程名含 '{0}' 或标题含 '{1}'）：" -f $TargetProcess, $TargetTitleLike)
  $pids = @{}
  foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
    if ($p.ProcessName -like "*$TargetProcess*") { $pids[[uint32]$p.Id] = $true }
  }
  $any = $false
  foreach ($w in [WhaleWin32]::TopLevelWindows()) {
    $hit = Test-TargetWindow $w $pids
    $titleHit = $w.Title -and ($w.Title.IndexOf($TargetTitleLike, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    $nameHit = $pids.ContainsKey($w.Pid)
    if (-not ($hit -or $titleHit -or $nameHit)) { continue }
    $any = $true
    Write-Host ("  {0} hwnd=0x{1:X}  pid={2}  class={3}  visible={4}  minimized={5}  area={6}  title='{7}'" -f `
        $(if ($hit) { '[√]' } else { '[×]' }), [int64]$w.Handle, $w.Pid, $w.Class, $w.Visible, $w.Minimized, $w.Area, $w.Title)
  }
  if (-not $any) { Write-Host '  （没有任何窗口匹配）' }
  $picked = Get-TargetWindow
  if ($picked) {
    Write-Host ("=> 会监视：hwnd=0x{0:X}  pid={1}  class={2}  minimized={3}" -f [int64]$picked.Handle, $picked.Pid, $picked.Class, $picked.Minimized)
    Write-Host ("   title='{0}'" -f $picked.Title)
  } else {
    Write-Host '=> 没找到可用窗口'
  }
  return
}

# ---------------------------------------------------------------------------
# 3. 素材：优先现成开源素材，其次内置矢量自绘
# ---------------------------------------------------------------------------
# 两套现成素材风格，按状态取候选（按顺序尝试；WPF 原生不支持 webp，所以 gif/png 优先）
#   norm-* —— prepare-assets.py 归一化过的素材（角色尺寸统一，首选，见该脚本注释）
#   stills —— 512px 高清静图（蓝色大肥鱼鲸鱼娘），由 WPF 做呼吸/摇摆动作
#   gifs   —— GIF 动图
$script:AssetPatternsStills = [ordered]@{
  idle    = @('norm-idle.png', 'bigfish-idle.png', '*idle*.png', '*idle*.gif', '*idle*.webp')
  busy    = @('norm-busy.png', 'bigfish-running.png', '*running*.png', '*thinking*.png', '*coding*.gif', '*thinking*.gif', '*running*.webp')
  waiting = @('norm-waiting.png', 'bigfish-thinking.png', '*question*.gif', '*approval*.gif', '*thinking*.png', '*question*.webp')
  sleep   = @('norm-sleep.png', 'bigfish-sleep.png', '*sleep*.png', '*sleep*.gif', '*sleep*.webp')
  pat     = @('norm-pat.png', 'bigfish-wink.png', '*wink*.png', '*pat*.gif', '*happy*.gif', '*happy*.webp')
  greet   = @('norm-greet.png', 'bigfish-greet.png', '*greet*.png', '*greet*.gif', '*wink*.gif', '*tail-swing*.webp')
}
$script:AssetPatternsGifs = [ordered]@{
  idle    = @('norm-idle.gif', 'pet-idle.gif', '*idle*.gif', '*idle*.png', '*idle*.webp')
  busy    = @('norm-busy.gif', 'pet-busy.gif', '*thinking*.gif', '*coding*.gif', '*running*.gif', '*running*.png', '*thinking*.webp')
  waiting = @('norm-waiting.gif', 'pet-question.gif', '*approval*.gif', '*question*.gif', '*thinking*.png')
  sleep   = @('norm-sleep.gif', 'pet-sleep.gif', '*sleep*.gif', '*sleep*.png', '*sleep*.webp')
  pat     = @('norm-pat.gif', 'pet-pat.gif', '*pat*.gif', '*happy*.gif', '*wink*.png', '*happy*.webp')
  greet   = @('norm-greet.gif', 'pet-happy.gif', '*greet*.gif', '*greet*.png', '*wink*.gif', '*wink*.webp')
}
$script:ArtMode = if ($script:Cfg.ArtMode -eq 'gifs') { 'gifs' } else { 'stills' }

function Resolve-AssetFiles([string]$mode) {
  $map = @{}
  if (-not (Test-Path $script:AssetsDir)) { return $map }
  $patterns = if ($mode -eq 'gifs') { $script:AssetPatternsGifs } else { $script:AssetPatternsStills }
  $files = Get-ChildItem $script:AssetsDir -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Extension -match '(?i)^\.(gif|png|webp|jpg|jpeg)$' }
  foreach ($state in $patterns.Keys) {
    $cands = New-Object System.Collections.ArrayList
    foreach ($pat in $patterns[$state]) {
      foreach ($hit in ($files | Where-Object { $_.Name -like $pat } | Sort-Object Name)) {
        if (-not $cands.Contains($hit.FullName)) { [void]$cands.Add($hit.FullName) }
      }
    }
    if ($cands.Count -gt 0) { $map[$state] = @($cands) }
  }
  return $map
}

$script:AssetMap = Resolve-AssetFiles $script:ArtMode
$script:UseAssetArt = ($script:Cfg.UseAssetArt -and $script:AssetMap.Count -gt 0)
Write-Log ("art mode = {0}; assets: {1}" -f $script:ArtMode, (($script:AssetMap.GetEnumerator() | ForEach-Object { "$($_.Key)=$(($_.Value | ForEach-Object { Split-Path $_ -Leaf }) -join '|')" }) -join ', '))

$script:AnimCache = [ordered]@{}
$script:AnimOrder = New-Object System.Collections.ArrayList

function Get-Animation([string]$path) {
  if ($script:AnimCache.Contains($path)) { return $script:AnimCache[$path] }
  $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
  $anim = $null
  try {
    if ($ext -eq '.gif') {
      $dec = New-Object System.Windows.Media.Imaging.GifBitmapDecoder(
        ([Uri]$path),
        [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
        [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $frames = @(); $delays = @()
      foreach ($f in $dec.Frames) {
        $frames += $f
        $d = 100
        try {
          $q = $f.Metadata.GetQuery('/grctlext/Delay')
          if ($q) { $d = [int]([uint16]$q) * 10 }
        } catch { }
        if ($d -lt 30) { $d = 100 }
        $delays += $d
      }
      if ($frames.Count -gt 0) { $anim = @{ Frames = $frames; Delays = $delays; Kind = 'gif' } }
    } else {
      $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
      $bmp.BeginInit()
      $bmp.UriSource = [Uri]$path
      $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
      $bmp.EndInit()
      $bmp.Freeze()
      $anim = @{ Frames = @($bmp); Delays = @(0); Kind = 'still' }
    }
  } catch { Write-Log "load animation failed: $path -> $($_.Exception.Message)" }

  if ($anim) {
    $script:AnimCache[$path] = $anim
    [void]$script:AnimOrder.Add($path)
    # 缓存上限 4 个状态，避免 GIF 解码占内存
    while ($script:AnimOrder.Count -gt 4) {
      $old = $script:AnimOrder[0]
      [void]$script:AnimOrder.RemoveAt(0)
      $script:AnimCache.Remove($old)
    }
  }
  return $anim
}

# 内置矢量鲸鱼娘
$script:ArtXaml = $null
function Get-ArtXaml {
  if ($script:ArtXaml) { return $script:ArtXaml }
  $p = Join-Path $here 'WhaleArt.xaml'
  if (Test-Path $p) {
    $text = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $script:ArtXaml = [System.Windows.Markup.XamlReader]::Parse($text)
  }
  return $script:ArtXaml
}

# ---------------------------------------------------------------------------
# 4. Harness 状态感知（读取 DSH 会话缓存）
# ---------------------------------------------------------------------------
function Get-DshStatus {
  $res = @{ Ok = $false; Busy = $false; Waiting = $false; AgoSec = 9999; ContextPct = $null
            Tokens = $null; Title = ''; At = (Get-Date); Err = '' }
  try {
    $home2 = Join-Path $env:USERPROFILE '.dsh'
    $dir = Join-Path $home2 'storages\session_projcache\sessions'
    if (-not (Test-Path $dir)) { $res.Err = 'no session cache dir'; return $res }
    $f = Get-ChildItem $dir -Filter '*.json' -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { $res.Err = 'no session cache file'; return $res }
    $res.AgoSec = [int]((Get-Date) - $f.LastWriteTime).TotalSeconds

    # 缓存文件经常正被 Harness 写入，读到半截会解析失败 -> 重试几次
    $o = $null
    for ($i = 0; $i -lt 3 -and -not $o; $i++) {
      try { $o = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
      catch { $res.Err = $_.Exception.Message; Start-Sleep -Milliseconds 60 }
    }
    if (-not $o) { return $res }

    $rows = $o.record.rows
    if (-not $rows) { $res.Err = 'unexpected json shape'; return $res }
    $res.Ok = $true
    $res.Err = ''
    $stats = $rows.sessionStats.val
    # 超过 5 分钟没写过，即便 openStep 还挂着也不算"正在干活"，避免状态卡死
    if ($stats -and $stats.openStep -and $res.AgoSec -lt 300) { $res.Busy = $true }
    $q = $rows.userQuestions.val.questions.active
    if ($q -and @($q).Count -gt 0) { $res.Waiting = $true }
    $plan = $rows.plan.val
    if ($plan -and $plan.wanted) { $res.Waiting = $true }
    if ($rows.title.val) { $res.Title = [string]$rows.title.val }
    $cp = $rows.contextPressure.val
    if ($cp -and $cp.contextWindow -gt 0) { $res.ContextPct = [int](100.0 * $cp.surfaceTokens / $cp.contextWindow) }
    $tu = $rows.tokenUsage.val.totals
    if ($tu) { $res.Tokens = [int64]$tu.uncachedInputTokens + [int64]$tu.outputTokens + [int64]$tu.cacheReadTokens }
  } catch { $res.Err = $_.Exception.Message }
  return $res
}

# ---------------------------------------------------------------------------
# 5. UI 搭建
# ---------------------------------------------------------------------------
$script:WinW = 300
$script:WinH = 360

$win = New-Object System.Windows.Window
$win.WindowStyle = [System.Windows.WindowStyle]::None
$win.AllowsTransparency = $true
$win.Background = $null
$win.Topmost = [bool]$script:Cfg.Topmost
$win.ShowInTaskbar = $false
# 关键：浮出来时不抢焦点（否则 Harness 一失焦、桌宠弹出就会打断你在别的软件里打字）
$win.ShowActivated = $false
$win.ResizeMode = [System.Windows.ResizeMode]::NoResize
$win.Width = $script:WinW
$win.Height = $script:WinH
$win.Title = 'DSH 鲸鱼娘'

$root = New-Object System.Windows.Controls.Canvas
$root.Width = $script:WinW
$root.Height = $script:WinH
$root.Background = $null
$win.Content = $root

# 角色容器（带呼吸/摇摆变换）
$artBox = New-Object System.Windows.Controls.Canvas
$artBox.Width = $script:WinW
$artBox.Height = $script:WinH
$tt = New-Object System.Windows.Media.TranslateTransform
$rt = New-Object System.Windows.Media.RotateTransform
$rt.CenterX = $script:WinW / 2
$rt.CenterY = $script:WinH * 0.72
$tg = New-Object System.Windows.Media.TransformGroup
[void]$tg.Children.Add($rt)
[void]$tg.Children.Add($tt)
$artBox.RenderTransform = $tg
[void]$root.Children.Add($artBox)

# 命中区：只有角色本体附近才吃鼠标事件。
# 贴图元素的整个矩形（含透明留白）默认都会命中，会挡住底下的窗口/桌面，
# 所以把贴图设为不参与命中，另放一块透明的矩形只盖住角色核心区域。
$hitArea = New-Object System.Windows.Shapes.Rectangle
$hitArea.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Colors]::Transparent)
[void]$artBox.Children.Add($hitArea)

$artImage = New-Object System.Windows.Controls.Image
$artImage.Stretch = [System.Windows.Media.Stretch]::Uniform
$artImage.IsHitTestVisible = $false
$artImage.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 1.0)
$script:ArtScale = New-Object System.Windows.Media.ScaleTransform(1, 1)
$artImage.RenderTransform = $script:ArtScale
[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($artImage, [System.Windows.Media.BitmapScalingMode]::HighQuality)
[void]$artBox.Children.Add($artImage)

$vectorArt = $null
if (-not $script:UseAssetArt) {
  $vectorArt = Get-ArtXaml
  if ($vectorArt) { $vectorArt.IsHitTestVisible = $false; [void]$artBox.Children.Add($vectorArt) }
}

function Set-ArtScale {
  # 归一化素材的构图：静图 512x512 / 动图 320x256，角色高都约 0.80 画布
  # 这个框(300x280)让两类素材渲染出来的角色高度都约 225px，且随状态不变
  $w = [int](300 * $script:ScaleFactor)
  $h = [int](280 * $script:ScaleFactor)
  $artImage.Width = $w
  $artImage.Height = $h
  [System.Windows.Controls.Canvas]::SetLeft($artImage, ($script:WinW - $w) / 2)
  [System.Windows.Controls.Canvas]::SetTop($artImage, $script:WinH - $h - 16)
  if ($vectorArt) {
    [System.Windows.Controls.Canvas]::SetLeft($vectorArt, ($script:WinW - $w) / 2)
    [System.Windows.Controls.Canvas]::SetTop($vectorArt, $script:WinH - $h - 16)
    $s = New-Object System.Windows.Media.ScaleTransform($script:ScaleFactor, $script:ScaleFactor)
    $vectorArt.RenderTransform = $s
  }
  # 命中区随缩放走：两类素材角色核心区的交集（换算到 300x280 框内的坐标）
  $hw = [int](190 * $script:ScaleFactor)
  $hh = [int](207 * $script:ScaleFactor)
  $hitArea.Width = $hw
  $hitArea.Height = $hh
  [System.Windows.Controls.Canvas]::SetLeft($hitArea, ($script:WinW - $hw) / 2)
  [System.Windows.Controls.Canvas]::SetTop($hitArea, $script:WinH - [int](280 * $script:ScaleFactor) - 16 + [int](48 * $script:ScaleFactor))
}
Set-ArtScale

# 气泡
$bubblePanel = New-Object System.Windows.Controls.StackPanel
$bubblePanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
$bubblePanel.Width = 270
[System.Windows.Controls.Canvas]::SetLeft($bubblePanel, 14)
[System.Windows.Controls.Canvas]::SetTop($bubblePanel, 4)
[void]$root.Children.Add($bubblePanel)

$bubbleBorder = New-Object System.Windows.Controls.Border
$bubbleBorder.CornerRadius = New-Object System.Windows.CornerRadius(13)
$bubbleBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(242, 255, 255, 255))
$bubbleBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(77, 107, 254))
$bubbleBorder.BorderThickness = New-Object System.Windows.Thickness(2)
$bubbleBorder.Padding = New-Object System.Windows.Thickness(11, 7, 11, 7)
[void]$bubblePanel.Children.Add($bubbleBorder)

$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$bubbleText.TextAlignment = [System.Windows.TextAlignment]::Center
$bubbleText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI, Segoe UI')
$bubbleText.FontSize = 13
$bubbleText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(38, 52, 122))
$bubbleBorder.Child = $bubbleText

$bubbleTail = New-Object System.Windows.Shapes.Path
$bubbleTail.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(77, 107, 254))
$bubbleTail.Data = [System.Windows.Media.Geometry]::Parse('M 0,0 L 18,0 L 6,12 Z')
$bubbleTail.Margin = New-Object System.Windows.Thickness(40, -1, 0, 0)
$bubbleTail.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
[void]$bubblePanel.Children.Add($bubbleTail)

$bubblePanel.Visibility = [System.Windows.Visibility]::Collapsed

function Show-Bubble([string]$text, [int]$ms = 4200) {
  if (-not $script:Cfg.ShowBubble) { return }
  $bubbleText.Text = $text
  $bubblePanel.Visibility = [System.Windows.Visibility]::Visible
  $script:BubbleUntil = (Get-Date).AddMilliseconds($ms)
}

# ---------------------------------------------------------------------------
# 6. 状态机 / 动画
# ---------------------------------------------------------------------------
$script:State = ''                # idle | busy | waiting | sleep | pat | greet（初值为空，保证首次必定应用）
$script:PatUntil = [datetime]::MinValue
$script:LastInteract = Get-Date
$script:FrameIdx = 0
$script:FrameMs = 0
$script:T = 0.0
$script:CurrentAnimPath = $null
$script:BubbleUntil = [datetime]::MinValue
$script:TickCount = 0

$script:IdleLines = @(
  'Harness 最小化啦，我替你守着桌面～',
  '我在这儿哦，有事双击我就把你叫回来 ✧',
  '蓝色大肥鱼，随时待命！',
  '桌面交给我，你放心去摸鱼吧～',
  '需要我帮忙就把我戳醒 ^ ^'
)
$script:BusyLines = @(
  '在搬砖…别催我 >_<',
  '正在努力思考中，等我一下下！',
  '写代码写代码～',
  '正在吃 token，嗡嗡嗡…'
)
$script:WaitLines = @(
  '有人在等你回答哦！快回去看看～',
  '有提问卡住啦，双击我回去处理！',
  '审批/提问进行中，别晾着它呀 >_<'
)
$script:SleepLines = @('Zzz… 我先睡一会儿', '呼…呼…（打呼噜的鲸鱼）')
# Harness 被关到托盘（点了关闭按钮）时说的话
$script:TrayLines = @(
  'Harness 收进托盘啦，我先躺下打个盹…',
  'Zzz… 要找我就在托盘图标上把它叫出来',
  '关到托盘了，那我就趴一会儿～'
)
$script:PatLines = @('呜哇！别戳我 >w<', '摸头摸头，好舒服～', '咦？我在我在！', '再摸一下也可以哦～')

function Set-PetState([string]$state, [switch]$KeepBubble) {
  if ($script:State -eq $state) { return }
  $script:State = $state
  $script:FrameIdx = 0
  $script:FrameMs = 0

  if ($script:UseAssetArt) {
    $key = $state
    if (-not $script:AssetMap.Contains($key)) { $key = 'idle' }
    $cands = $script:AssetMap[$key]
    $loaded = $false
    if ($cands) {
      foreach ($path in $cands) {
        $anim = Get-Animation $path
        if ($anim) {
          $script:CurrentAnimPath = $path
          $artImage.Source = $anim.Frames[0]
          $artImage.Visibility = [System.Windows.Visibility]::Visible
          if ($vectorArt) { $vectorArt.Visibility = [System.Windows.Visibility]::Collapsed }
          $loaded = $true
          break
        }
      }
    }
    if (-not $loaded) {
      # 素材都读不了（例如只有 WPF 不支持的 webp）时，回退到内置矢量画
      Write-Log "no usable asset for state '$state'; using built-in vector art"
      $v = Get-ArtXaml
      if ($v) {
        if (-not $vectorArt) {
          $script:vectorArt = $v
          [void]$artBox.Children.Add($v)
          Set-ArtScale
        }
        $artImage.Visibility = [System.Windows.Visibility]::Collapsed
        $script:vectorArt.Visibility = [System.Windows.Visibility]::Visible
        Apply-VectorState $state
      }
      if ($key -eq 'idle') { $script:UseAssetArt = $false }
    }
  } else {
    Apply-VectorState $state
  }
  Write-Log "state -> $state"
}

function Apply-VectorState([string]$state) {
  if (-not $vectorArt) { return }
  $eyeL = $vectorArt.FindName('eyeL'); $eyeR = $vectorArt.FindName('eyeR')
  $smile = $vectorArt.FindName('eyeSmile'); $zzz = $vectorArt.FindName('zzz')
  $mouth = $vectorArt.FindName('mouth'); $tailRot = $vectorArt.FindName('tailRot')
  $eyeLScale = $vectorArt.FindName('eyeLScale'); $eyeRScale = $vectorArt.FindName('eyeRScale')

  if ($smile) { $smile.Visibility = [System.Windows.Visibility]::Collapsed }
  if ($zzz) { $zzz.Visibility = [System.Windows.Visibility]::Collapsed }
  if ($eyeL) { $eyeL.Visibility = [System.Windows.Visibility]::Visible }
  if ($eyeR) { $eyeR.Visibility = [System.Windows.Visibility]::Visible }
  if ($eyeLScale) { $eyeLScale.ScaleY = 1 }
  if ($eyeRScale) { $eyeRScale.ScaleY = 1 }
  if ($tailRot) { $tailRot.Angle = 0 }
  if ($mouth) { $mouth.Data = [System.Windows.Media.Geometry]::Parse('M 122,124 C 126,131 134,131 138,124') }

  switch ($state) {
    'busy' {
      if ($mouth) { $mouth.Data = [System.Windows.Media.Geometry]::Parse('M 122,126 C 126,131 134,131 138,126') }
    }
    'waiting' {
      if ($mouth) { $mouth.Data = [System.Windows.Media.Geometry]::Parse('M 124,126 C 128,133 132,133 136,126') }
    }
    'sleep' {
      if ($eyeLScale) { $eyeLScale.ScaleY = 0.08 }
      if ($eyeRScale) { $eyeRScale.ScaleY = 0.08 }
      if ($zzz) { $zzz.Visibility = [System.Windows.Visibility]::Visible }
      if ($mouth) { $mouth.Data = [System.Windows.Media.Geometry]::Parse('M 124,128 C 128,132 132,132 136,128') }
    }
    'pat' {
      if ($eyeL) { $eyeL.Visibility = [System.Windows.Visibility]::Collapsed }
      if ($eyeR) { $eyeR.Visibility = [System.Windows.Visibility]::Collapsed }
      if ($smile) { $smile.Visibility = [System.Windows.Visibility]::Visible }
      if ($mouth) { $mouth.Data = [System.Windows.Media.Geometry]::Parse('M 118,122 C 124,134 136,134 142,122') }
    }
    'greet' {
      if ($tailRot) { $tailRot.Angle = 10 }
    }
  }
}

function Update-Animation {
  if (-not $script:UseAssetArt) {
    # 矢量模式：眨眼 & 尾巴（仅 idle 时）
    if ($vectorArt -and $script:State -eq 'idle') {
      $eyeLScale = $vectorArt.FindName('eyeLScale'); $eyeRScale = $vectorArt.FindName('eyeRScale')
      $tailRot = $vectorArt.FindName('tailRot')
      if ($tailRot) { $tailRot.Angle = [math]::Sin($script:T * 2.2) * 9 }
      $cycle = $script:T % 4.2
      $closed = ($cycle -gt 3.9)
      if ($eyeLScale) { $eyeLScale.ScaleY = $(if ($closed) { 0.08 } else { 1 }) }
      if ($eyeRScale) { $eyeRScale.ScaleY = $(if ($closed) { 0.08 } else { 1 }) }
    }
    return
  }

  $path = $script:CurrentAnimPath
  if (-not $path) { return }
  $anim = $script:AnimCache[$path]
  if (-not $anim -or $anim.Frames.Count -le 1) { return }

  $script:FrameMs += 33
  $delay = $anim.Delays[$script:FrameIdx % $anim.Delays.Count]
  if ($script:FrameMs -ge $delay) {
    $script:FrameMs = 0
    $script:FrameIdx = ($script:FrameIdx + 1) % $anim.Frames.Count
    $artImage.Source = $anim.Frames[$script:FrameIdx]
  }
}

# ---------------------------------------------------------------------------
# 7. 交互
# ---------------------------------------------------------------------------
function Invoke-Pat {
  if ($ForceState) { return }        # 调试锁定时不受点击影响
  $script:LastInteract = Get-Date
  $script:PatUntil = (Get-Date).AddMilliseconds(1400)
  $script:State = ''                 # 强制重新应用 'pat'（连点也能重放）
  Set-PetState 'pat'
  Show-Bubble ($script:PatLines | Get-Random) 2000
}

function Restore-Harness {
  $w = Get-TargetWindow
  if ($w) {
    Write-Log ("restore harness hwnd=0x{0:X}" -f [int64]$w.Handle)
    [void][WhaleWin32]::RestoreWindow($w.Handle)
    Show-Bubble '欢迎回来！' 1800
  } else {
    Show-Bubble '咦，没找到 Harness 窗口…' 2200
  }
}

$artBox.Add_MouseLeftButtonDown({
    $before = "$($win.Left),$($win.Top)"
    $script:LastInteract = Get-Date
    try { $win.DragMove() } catch { }
    if ("$($win.Left),$($win.Top)" -eq $before) {
      Invoke-Pat
    } else {
      $script:Cfg.Left = [int]$win.Left
      $script:Cfg.Top = [int]$win.Top
      Export-Settings
    }
  })

$artBox.Add_MouseWheel({
    $e = $args[1]
    $script:LastInteract = Get-Date
    if ($e.Delta -gt 0) { $script:ScaleFactor = [math]::Min(1.8, $script:ScaleFactor + 0.1) }
    else { $script:ScaleFactor = [math]::Max(0.6, $script:ScaleFactor - 0.1) }
    Set-ArtScale
    Export-Settings
  })

# 切换素材风格：立刻生效，不用重启
function Switch-ArtMode([string]$mode) {
  if ($mode -eq 'vector') {
    $script:Cfg.UseAssetArt = $false
    $script:UseAssetArt = $false
  } else {
    $script:Cfg.UseAssetArt = $true
    $script:ArtMode = $mode
    $script:Cfg.ArtMode = $mode
    $script:AssetMap = Resolve-AssetFiles $mode
    $script:UseAssetArt = ($script:AssetMap.Count -gt 0)
  }
  $script:AnimCache = [ordered]@{}
  $script:AnimOrder.Clear()
  $script:CurrentAnimPath = $null

  if (-not $script:UseAssetArt) {
    $v = Get-ArtXaml
    if ($v) {
      if (-not $vectorArt) { $script:vectorArt = $v; [void]$artBox.Children.Add($v); Set-ArtScale }
      $script:vectorArt.Visibility = [System.Windows.Visibility]::Visible
      $artImage.Visibility = [System.Windows.Visibility]::Collapsed
    }
  } elseif ($vectorArt) {
    $script:vectorArt.Visibility = [System.Windows.Visibility]::Collapsed
  }

  $prev = $script:State
  $script:State = ''
  Set-PetState $(if ($prev) { $prev } else { 'idle' })

  if ($miStyleStills) {
    $miStyleStills.IsChecked = ($mode -eq 'stills')
    $miStyleGifs.IsChecked = ($mode -eq 'gifs')
    $miStyleVector.IsChecked = ($mode -eq 'vector')
  }
  $label = switch ($mode) { 'gifs' { 'GIF 动图' } 'vector' { '内置矢量画' } default { '高清静图' } }
  Show-Bubble ("换成 $label 啦～") 2200
  Export-Settings
}

# 右键菜单
$ctxMenu = New-Object System.Windows.Controls.ContextMenu
function Add-MenuItem([string]$header, [scriptblock]$action, [bool]$checkable = $false, [bool]$checked = $false) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $header
  if ($checkable) { $mi.IsCheckable = $true; $mi.IsChecked = $checked }
  $mi.Add_Click($action)
  [void]$ctxMenu.Items.Add($mi)
  return $mi
}

[void](Add-MenuItem '恢复 Harness 窗口' { Restore-Harness })
[void](Add-MenuItem '显示气泡' {
      $script:Cfg.ShowBubble = -not $script:Cfg.ShowBubble
      if (-not $script:Cfg.ShowBubble) { $bubblePanel.Visibility = [System.Windows.Visibility]::Collapsed }
      Export-Settings
    } $true ([bool]$script:Cfg.ShowBubble))
[void](Add-MenuItem '总在最前' {
      $script:Cfg.Topmost = -not $script:Cfg.Topmost
      $win.Topmost = [bool]$script:Cfg.Topmost
      Export-Settings
    } $true ([bool]$script:Cfg.Topmost))
$miStyle = Add-MenuItem '素材风格' {}
$miStyleStills = New-Object System.Windows.Controls.MenuItem
$miStyleStills.Header = '高清静图（512px）'
$miStyleStills.IsCheckable = $true
$miStyleStills.IsChecked = ($script:ArtMode -eq 'stills')
$miStyleStills.Add_Click({ Switch-ArtMode 'stills' })
[void]$miStyle.Items.Add($miStyleStills)
$miStyleGifs = New-Object System.Windows.Controls.MenuItem
$miStyleGifs.Header = 'GIF 动图'
$miStyleGifs.IsCheckable = $true
$miStyleGifs.IsChecked = ($script:ArtMode -eq 'gifs')
$miStyleGifs.Add_Click({ Switch-ArtMode 'gifs' })
[void]$miStyle.Items.Add($miStyleGifs)
$miStyleVector = New-Object System.Windows.Controls.MenuItem
$miStyleVector.Header = '内置矢量画（不用素材）'
$miStyleVector.IsCheckable = $true
$miStyleVector.IsChecked = (-not $script:Cfg.UseAssetArt)
$miStyleVector.Add_Click({ Switch-ArtMode 'vector' })
[void]$miStyle.Items.Add($miStyleVector)
[void](Add-MenuItem '回到右下角' {
      $wa = [System.Windows.SystemParameters]::WorkArea
      $win.Left = $wa.Right - $win.Width - 24
      $win.Top = $wa.Bottom - $win.Height - 24
      $script:Cfg.Left = [int]$win.Left; $script:Cfg.Top = [int]$win.Top
      Export-Settings
    })
[void](Add-MenuItem '打开素材文件夹' { Start-Process explorer.exe $script:AssetsDir })
[void](Add-MenuItem '退出鲸鱼娘' { $script:Quit = $true; $win.Close() })
$root.ContextMenu = $ctxMenu

# ---------------------------------------------------------------------------
# 8. 开机自启 / 托盘
# ---------------------------------------------------------------------------
function Get-StartupLink { Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH-WhalePet.lnk' }
function Test-Autostart { Test-Path (Get-StartupLink) }
function Set-Autostart([bool]$on) {
  $lnk = Get-StartupLink
  try {
    if ($on) {
      $vbs = Join-Path $here 'start-whale-pet.vbs'
      $ws = New-Object -ComObject WScript.Shell
      $sc = $ws.CreateShortcut($lnk)
      $sc.TargetPath = 'wscript.exe'
      $sc.Arguments = '"' + $vbs + '"'
      $sc.WorkingDirectory = $here
      $sc.Description = 'DeepSeek Harness 鲸鱼娘桌宠'
      $sc.Save()
    } elseif (Test-Path $lnk) {
      Remove-Item $lnk -Force
    }
  } catch { Write-Log "autostart failed: $($_.Exception.Message)"; Show-Bubble '自启设置失败（可能被权限拦截）' 3000 }
}
[void](Add-MenuItem '开机自动启动' {
      Set-Autostart (-not (Test-Autostart))
      Show-Bubble $(if (Test-Autostart) { '好耶，下次开机我自动出现！' } else { '好吧，那我不自启了…' }) 2600
    } $true (Test-Autostart))

$tray = $null
function New-TrayIcon {
  $iconPath = $null
  foreach ($cand in @('rlw-tray.png', 'rlw-avatar.png')) {
    $p = Join-Path $script:AssetsDir $cand
    if (Test-Path $p) { $iconPath = $p; break }
  }
  $icon = $null
  try {
    if ($iconPath) {
      $bmp = New-Object System.Drawing.Bitmap($iconPath)
      $hicon = $bmp.GetHicon()
      $icon = [System.Drawing.Icon]::FromHandle($hicon)
    }
  } catch { Write-Log "tray icon failed: $($_.Exception.Message)" }
  if (-not $icon) {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(77, 107, 254))
    $g.FillEllipse($brush, 1, 1, 30, 30)
    $g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)), @(
        (New-Object System.Drawing.Point(16, 9)), (New-Object System.Drawing.Point(24, 5)), (New-Object System.Drawing.Point(21, 13)),
        (New-Object System.Drawing.Point(25, 19)), (New-Object System.Drawing.Point(16, 22)), (New-Object System.Drawing.Point(7, 19)),
        (New-Object System.Drawing.Point(11, 13)), (New-Object System.Drawing.Point(8, 5))))
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $g.Dispose()
  }

  $ni = New-Object System.Windows.Forms.NotifyIcon
  $ni.Icon = $icon
  $ni.Text = 'DSH 鲸鱼娘桌宠'
  $ni.Visible = $true
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $itemRestore = $menu.Items.Add('恢复 Harness 窗口')
  $itemRestore.Add_Click({ Restore-Harness })
  $itemShow = $menu.Items.Add('立即现身')
  $itemShow.Add_Click({
      $wa = [System.Windows.SystemParameters]::WorkArea
      if (-not $win.Left -or $win.Left -lt $wa.Left -or $win.Left -gt $wa.Right) {
        $win.Left = $wa.Right - $win.Width - 24; $win.Top = $wa.Bottom - $win.Height - 24
      }
      $win.Show(); $win.Topmost = $true
      Set-PetState 'greet'
      Show-Bubble (($script:IdleLines | Get-Random))
    })
  $itemQuit = $menu.Items.Add('退出')
  $itemQuit.Add_Click({ $script:Quit = $true; $win.Close() })
  $ni.ContextMenuStrip = $menu
  $ni.Add_MouseDoubleClick({ Restore-Harness })
  $ni.Visible = $true
  return $ni
}

# ---------------------------------------------------------------------------
# 9. 主循环：最小化 -> 浮出
# ---------------------------------------------------------------------------
$script:Quit = $false
$script:PetShown = $false
$script:AwaySince = $null        # 当前这种"收起来"状态从何时开始
$script:ShowMode = $null         # minimized（点了最小化）| tray（关闭到托盘）
$script:SawWindow = $false       # 是否见过 Harness 窗口（用来区分"还在启动"和"收进托盘"）
$script:BaseState = 'idle'       # 收起状态下该用的素材：最小化 -> idle，托盘 -> sleep
$script:HarnessSeen = $false
$script:HintUntil = [datetime]::MinValue
$script:GoneSince = $null

function Update-PetVisibility {
  if ($script:Quit) { return }

  if ($ForceShow) {
    if (-not $script:PetShown) {
      $win.Show()
      $script:PetShown = $true
      Set-PetState 'idle'
    }
    return
  }

  # 启动时的"报到"：先露个脸，告诉用户最小化 Harness 就会浮出来
  if ($script:HintUntil -and (Get-Date) -lt $script:HintUntil) {
    if (-not $script:PetShown) {
      $win.Show()
      $script:PetShown = $true
      Set-PetState 'greet'
      Show-Bubble '鲸鱼娘来啦～把 Harness 最小化，我就浮在桌面上陪你 ✧' 3200
    }
    return
  }

  # 判定 Harness 现在处于哪种"不在眼前"的状态：
  #   front     —— 窗口正常显示且在最前面（桌宠该躲回去）
  #   minimized —— 点了最小化按钮（桌宠用 idle 素材）
  #   behind    —— 窗口还在，但被别的窗口压住/失了焦点，不是当前活动窗口（同样按 idle 处理）
  #   tray      —— 点了关闭按钮、最小化到托盘（窗口隐藏或窗口已销毁但进程还在；桌宠用 sleep 素材）
  #   gone      —— 进程和窗口都没了（桌宠躲起来，看门狗随后让它退出）
  $w = Get-TargetWindow
  if ($w) { $script:SawWindow = $true }
  $mode = 'front'
  if (-not $w) {
    # 窗口整个不见了：只有"以前见过它的窗口"才算被收进托盘；
    # 否则就是 Harness 还在启动（窗口没建出来），别急着弹 sleep。
    if ($script:SawWindow -and (Test-HarnessAlive)) { $mode = 'tray' } else { $mode = 'gone' }
  } elseif ($w.Minimized) {
    $mode = 'minimized'
  } elseif (-not $w.Visible) {
    $mode = 'tray'
  } elseif ((-not $NoFocusTrigger) -and (Test-HarnessUnfocused $w)) {
    $mode = 'behind'
  }

  if ($mode -eq 'front' -or $mode -eq 'gone') {
    if ($mode -eq 'gone' -and $script:HarnessSeen) { Write-Log 'harness window gone' }
    $script:HarnessSeen = ($mode -ne 'gone')
    $script:AwaySince = $null
    $script:ShowMode = $null
    if ($script:PetShown) {
      $win.Hide()
      $script:PetShown = $false
      Write-Log 'pet hidden (harness front)'
    }
    return
  }

  $script:HarnessSeen = $true
  $script:HarnessHwnd = if ($w) { $w.Handle } else { [IntPtr]::Zero }

  # 换了收起来的方式（最小化 <-> 关闭到托盘）就重新计时并换素材
  if ($script:ShowMode -ne $mode) {
    $script:ShowMode = $mode
    $script:AwaySince = Get-Date
    $script:BaseState = if ($mode -eq 'tray') { 'sleep' } else { 'idle' }
    if ($script:PetShown) {
      Set-PetState $script:BaseState
      if ($mode -eq 'tray') { Show-Bubble ($script:TrayLines | Get-Random) 5000 }
      Write-Log ("show mode -> {0} (base={1})" -f $mode, $script:BaseState)
    }
  }
  if (-not $script:AwaySince) { $script:AwaySince = Get-Date }

  $elapsed = ((Get-Date) - $script:AwaySince).TotalMilliseconds
  if (-not $script:PetShown -and $elapsed -ge $ShowDelayMs) {
    if ($script:Cfg.Left -ne $null -and $script:Cfg.Top -ne $null) {
      $win.Left = [double]$script:Cfg.Left
      $win.Top = [double]$script:Cfg.Top
    } else {
      $wa = [System.Windows.SystemParameters]::WorkArea
      $win.Left = $wa.Right - $win.Width - 24
      $win.Top = $wa.Bottom - $win.Height - 24
    }
    $win.Show()
    $script:PetShown = $true
    Set-PetState $script:BaseState
    $st = Get-DshStatus
    if ($st.Waiting) { Show-Bubble ($script:WaitLines | Get-Random) 6000 }
    elseif ($st.Busy) { Show-Bubble ($script:BusyLines | Get-Random) 5000 }
    elseif ($mode -eq 'tray') { Show-Bubble ($script:TrayLines | Get-Random) 5000 }
    else { Show-Bubble ($script:IdleLines | Get-Random) 5000 }
    Write-Log ("pet shown ({0} {1:N0}ms, base={2})" -f $mode, $elapsed, $script:BaseState)
  }
}

# 看门狗：Harness 彻底不在了（进程名和窗口标题都匹配不到）就自行退出，
# 免得 Harness 被强杀后桌宠变成孤儿进程。
function Test-HarnessUnfocused([object]$w) {
  # Harness 窗口还在，但已经不是当前活动窗口（被别的窗口压住 / 切到别的软件了）
  try {
    $fg = [WhaleWin32]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero) { return $false }        # 拿不到前台窗口就别乱弹
    if ($fg -eq $w.Handle) { return $false }

    # 前台窗口在它的属主链上（Harness 自己的对话框、Tooltip 之类）也算在前台
    $h = $fg
    for ($i = 0; $i -lt 4 -and $h -ne [IntPtr]::Zero; $i++) {
      if ($h -eq $w.Handle) { return $false }
      $h = [WhaleWin32]::GetWindow($h, 4)                # GW_OWNER
    }
    # 前台窗口和 Harness 主窗口属于同一个进程，也算 Harness 还在前台
    $fgPid = [uint32]0
    [void][WhaleWin32]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    if ($fgPid -eq $w.Pid) { return $false }
    return $true
  } catch { return $false }
}

function Test-HarnessAlive {
  try {
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
      if ($p.ProcessName -like "*$script:TargetProcess*") { return $true }
    }
  } catch { }
  if (-not [string]::IsNullOrWhiteSpace($script:TargetTitleLike)) {
    foreach ($w in [WhaleWin32]::TopLevelWindows()) {
      if ($w.Title -and $w.Title.IndexOf($script:TargetTitleLike, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
  }
  return $false
}

function Test-HarnessLifecycle {
  if ($KeepAlive) { return }
  if (Test-HarnessAlive) {
    if ($script:GoneSince) { Write-Log 'harness back' }
    $script:GoneSince = $null
    return
  }
  if (-not $script:GoneSince) {
    $script:GoneSince = Get-Date
    Write-Log 'harness not found; exit grace timer started'
    return
  }
  $gone = ((Get-Date) - $script:GoneSince).TotalSeconds
  if ($gone -ge $HarnessGoneGraceSec) {
    Write-Log ("harness gone {0:N0}s -> pet exits" -f $gone)
    $script:Quit = $true
    $win.Close()
  }
}

function Update-PetMood {
  if ($ForceState) { return }      # 调试：锁在指定状态
  if (-not $script:PetShown) { return }
  $idleSec = ((Get-Date) - $script:LastInteract).TotalSeconds

  if ((Get-Date) -lt $script:PatUntil) { return }

  # busy / waiting 逻辑保持不变：DSH 会话真在干活时优先显示对应素材
  $st = $script:DshStatus
  if ($st -and $st.Waiting) { Set-PetState 'waiting'; return }
  if ($st -and $st.Busy) { Set-PetState 'busy'; return }

  # 干活状态结束后，回到与"收起来的方式"对应的素材：
  #   点最小化 -> idle；点关闭收到托盘 -> sleep
  if ($SleepAfterSec -gt 0 -and $script:ShowMode -eq 'minimized' -and $script:AwaySince) {
    $minSec = ((Get-Date) - $script:AwaySince).TotalSeconds
    if ($minSec -ge $SleepAfterSec -and $idleSec -ge 60) { Set-PetState 'sleep'; return }
  }
  Set-PetState $script:BaseState
}

function Update-StatusBubble {
  if (-not $script:PetShown) { return }
  if ((Get-Date) -lt $script:BubbleUntil) { return }
  if (-not $script:Cfg.ShowBubble) { return }
  # 每 45 秒左右用状态换一句台词
  if (((Get-Date) - $script:LastBubble).TotalSeconds -lt 45) { return }
  $script:LastBubble = Get-Date
  $st = $script:DshStatus
  $wa = [System.Windows.SystemParameters]::WorkArea
  $lines = New-Object System.Collections.ArrayList
  if ($st.Waiting) { [void]$lines.Add(($script:WaitLines | Get-Random)) }
  elseif ($st.Busy) { [void]$lines.Add(($script:BusyLines | Get-Random)) }
  if ($script:AwaySince) {
    $span = (Get-Date) - $script:AwaySince
    $what = switch ($script:ShowMode) {
      'tray' { '已收进托盘' }
      'behind' { 'Harness 不在前台' }
      default { '已最小化' }
    }
    $txt = if ($span.TotalMinutes -ge 1) { '{0} {1} 分 {2} 秒' -f $what, [int]$span.TotalMinutes, $span.Seconds } else { '{0} {1} 秒' -f $what, [int]$span.TotalSeconds }
    [void]$lines.Add($txt + '，我帮你盯着～')
  }
  if ($st.ContextPct -ne $null) { [void]$lines.Add('上下文已用 ' + $st.ContextPct + '%') }
  if ($st.Tokens) { [void]$lines.Add('大肥鱼已经吃掉 {0:N0} token 啦' -f $st.Tokens) }
  if ($lines.Count -eq 0) { [void]$lines.Add(($script:IdleLines | Get-Random)) }
  Show-Bubble ($lines | Get-Random) 5000
}
$script:LastBubble = Get-Date
$script:DshStatus = $null

# 调试用：把窗口内容渲染成 PNG（用于验证素材/布局，不依赖抓屏）
function Save-Snapshot([string]$path) {
  try {
    $w = [int]$win.Width; $h = [int]$win.Height
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($root)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($path)
    $enc.Save($fs)
    $fs.Close()
    Write-Log "snapshot -> $path"
  } catch { Write-Log "snapshot failed: $($_.Exception.Message)" }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({
    $script:TickCount++
    $script:T += 0.033

    # 呼吸 + 轻微摇摆；被摸头时蹦一下
    $bob = [math]::Sin($script:T * 1.7) * 4.0
    if ((Get-Date) -lt $script:PatUntil) { $bob -= 7.0 }
    $tt.Y = $bob
    $rt.Angle = [math]::Sin($script:T * 0.85) * 2.0
    if ($script:ArtScale) {
      if ($script:UseAssetArt -and $script:ArtMode -eq 'stills') {
        $script:ArtScale.ScaleX = 1.0 + [math]::Sin($script:T * 1.7) * 0.012
        $script:ArtScale.ScaleY = 1.0 + [math]::Sin($script:T * 1.7) * 0.018
      } elseif ($script:ArtScale.ScaleX -ne 1.0) {
        $script:ArtScale.ScaleX = 1.0
        $script:ArtScale.ScaleY = 1.0
      }
    }

    Update-Animation

    if ($script:TickCount % 9 -eq 0) { Update-PetVisibility }
    if ($script:TickCount % 90 -eq 0) {
      # 会话缓存可能正被 Harness 写入，解析失败时保留上一次的有效状态；
      # 注意失败结果不能覆盖掉有效状态，否则一次失败就把状态永久钉死。
      $stProbe = Get-DshStatus
      $prev = $script:DshStatus
      if ($stProbe.Ok) {
        if (-not $prev -or -not $prev.Ok -or $prev.Busy -ne $stProbe.Busy -or $prev.Waiting -ne $stProbe.Waiting) {
          Write-Log ("dsh: ok busy={0} waiting={1} ctx={2}% ago={3}s" -f $stProbe.Busy, $stProbe.Waiting, $stProbe.ContextPct, $stProbe.AgoSec)
        }
        $script:DshStatus = $stProbe
      } elseif (-not $prev -or -not $prev.Ok) {
        $script:DshStatus = $stProbe
        Write-Log ("dsh: probe failed ({0})" -f $stProbe.Err)
      }
    }
    if ($script:TickCount % 15 -eq 0) { Update-PetMood }
    if ($script:TickCount % 60 -eq 0) { Update-StatusBubble }
    if ($script:TickCount % 60 -eq 7) { Test-HarnessLifecycle }

    if ($Snapshot -and $script:TickCount -eq 75) {
      Save-Snapshot $Snapshot
      $script:Quit = $true
      $win.Close()
    }

    if ($script:BubbleUntil -ne [datetime]::MinValue -and (Get-Date) -gt $script:BubbleUntil) {
      $bubblePanel.Visibility = [System.Windows.Visibility]::Collapsed
      $script:BubbleUntil = [datetime]::MinValue
    }
  })

# 单实例（按被监视的进程区分，方便同时试用不同目标）
# 已有实例在跑时不直接退出，而是把旧实例关掉再接管：
# 这样升级/重启桌宠不用先手动去右键菜单点「退出」。
$mutexName = 'Local\DshWhalePet_' + ($script:TargetProcess -replace '[^A-Za-z0-9]', '_')
$mutex = New-Object System.Threading.Mutex($false, $mutexName)

function Acquire-PetMutex([int]$timeoutMs = 0) {
  try { return $mutex.WaitOne($timeoutMs, $false) }
  catch [System.Threading.AbandonedMutexException] { return $true }   # 上一个持有者被我们杀了
}

if (-not (Acquire-PetMutex 0)) {
  $oldPids = @([WhaleWin32]::TopLevelWindows() |
               Where-Object { $_.Title -eq 'DSH 鲸鱼娘' -and $_.Pid -ne $PID } |
               ForEach-Object { [int]$_.Pid } | Select-Object -Unique)
  if ($oldPids.Count -gt 0) {
    Write-Log ("found running pet (pid {0}), taking over" -f ($oldPids -join ','))
    foreach ($procId in $oldPids) { try { Stop-Process -Id $procId -Force -ErrorAction Stop } catch { Write-Log "takeover kill failed: $($_.Exception.Message)" } }
    Start-Sleep -Milliseconds 900
  }
  if (-not (Acquire-PetMutex 3000)) {
    Write-Host ("鲸鱼娘已经在运行啦（单实例：{0}）" -f $mutexName)
    exit 0
  }
}

if (-not $NoTray) { $tray = New-TrayIcon }

# 初始位置：优先记忆坐标，否则右下角
$wa0 = [System.Windows.SystemParameters]::WorkArea
if ($script:Cfg.Left -ne $null -and $script:Cfg.Top -ne $null) {
  $win.Left = [double]$script:Cfg.Left
  $win.Top = [double]$script:Cfg.Top
} else {
  $win.Left = $wa0.Right - $win.Width - 24
  $win.Top = $wa0.Bottom - $win.Height - 24
}

$win.Add_Closed({ [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })

Write-Log ("started: target='{0}' assets={1} vector={2} mode={3}" -f $script:TargetProcess, $script:AssetMap.Count, (-not $script:UseAssetArt), $script:ArtMode)

try {
  # 先建好窗口再立刻隐藏，等 Harness 最小化时才浮出
  $win.Show()
  $win.Hide()
  if ($ForceShow) {
    $win.Show(); $script:PetShown = $true
    Set-PetState $(if ($ForceState) { $ForceState } else { 'idle' })
  } elseif (-not $Snapshot) {
    $script:HintUntil = (Get-Date).AddSeconds(4.2)   # 启动报到，见 Update-PetVisibility
  }
  $timer.Start()
  [System.Windows.Threading.Dispatcher]::Run()
} finally {
  try { $timer.Stop() } catch { }
  if ($tray) { $tray.Visible = $false; $tray.Dispose() }
  Export-Settings
  try { $mutex.ReleaseMutex() } catch { }
  Write-Log 'exited'
}
