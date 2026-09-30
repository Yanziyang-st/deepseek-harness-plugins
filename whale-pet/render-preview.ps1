# Dev tool: render WhaleArt.xaml in several animation states to a contact sheet PNG.
param(
  [string]$Out = (Join-Path $PSScriptRoot 'preview.png'),
  [double]$Scale = 1.0,
  [string]$Bg = 'checker'   # checker | light | dark
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$artPath = Join-Path $PSScriptRoot 'WhaleArt.xaml'
$artText = [System.IO.File]::ReadAllText($artPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)

function New-Art { [System.Windows.Markup.XamlReader]::Parse($artText) }
function El($root, $name) {
  $o = $root.FindName($name)
  if ($null -eq $o) { throw "element not found: $name" }
  return $o
}

$states = @('idle', 'blink', 'happy', 'sleep', 'wag', 'bubble')
$colW = 260; $rowH = 280
$rows = if ($Bg -eq 'checker') { @('light', 'dark') } else { @($Bg) }
$sheetW = $colW * $states.Count
$sheetH = $rowH * $rows.Count + 26

function Set-State($root, $state) {
  switch ($state) {
    'blink' { (El $root 'eyeLScale').ScaleY = 0.08; (El $root 'eyeRScale').ScaleY = 0.08 }
    'happy' {
      (El $root 'eyeL').Visibility = 'Collapsed'; (El $root 'eyeR').Visibility = 'Collapsed'
      (El $root 'eyeSmile').Visibility = 'Visible'
      (El $root 'mouth').Data = [System.Windows.Media.Geometry]::Parse('M 118,122 C 124,134 136,134 142,122')
      (El $root 'bubbleGroup').Visibility = 'Visible'
      (El $root 'bubbleText').Text = '主人，我在这儿哦～'
    }
    'sleep' {
      (El $root 'eyeLScale').ScaleY = 0.08; (El $root 'eyeRScale').ScaleY = 0.08
      (El $root 'zzz').Visibility = 'Visible'
      (El $root 'mouth').Data = [System.Windows.Media.Geometry]::Parse('M 124,128 C 128,132 132,132 136,128')
    }
    'wag' { (El $root 'tailRot').Angle = 18; (El $root 'ahogeRot').Angle = 10; (El $root 'glow').Opacity = 0.85 }
    'bubble' {
      (El $root 'bubbleGroup').Visibility = 'Visible'
      (El $root 'bubbleText').Text = 'Harness 已最小化，我在桌面上替你看着～'
    }
  }
}

$sheet = New-Object System.Windows.Controls.Canvas
$sheet.Width = $sheetW; $sheet.Height = $sheetH

# backgrounds
$rowIndex = 0
foreach ($bg in $rows) {
  $rect = New-Object System.Windows.Shapes.Rectangle
  $rect.Width = $sheetW; $rect.Height = $rowH
  if ($bg -eq 'dark') { $rect.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(18, 22, 40)) }
  else { $rect.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(233, 236, 244)) }
  [System.Windows.Controls.Canvas]::SetLeft($rect, 0)
  [System.Windows.Controls.Canvas]::SetTop($rect, $rowIndex * $rowH)
  [void]$sheet.Children.Add($rect)

  # checkerboard stripes to reveal alpha
  for ($x = 0; $x -lt $sheetW; $x += 40) {
    if ((($x / 40) % 2) -eq 0) { continue }
    $s = New-Object System.Windows.Shapes.Rectangle
    $s.Width = 40; $s.Height = $rowH; $s.Opacity = 0.25
    $s.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(255, 255, 255))
    [System.Windows.Controls.Canvas]::SetLeft($s, $x)
    [System.Windows.Controls.Canvas]::SetTop($s, $rowIndex * $rowH)
    [void]$sheet.Children.Add($s)
  }
  $rowIndex++
}

for ($r = 0; $r -lt $rows.Count; $r++) {
  for ($c = 0; $c -lt $states.Count; $c++) {
    $art = New-Art
    Set-State $art $states[$c]
    [System.Windows.Controls.Canvas]::SetLeft($art, $c * $colW)
    [System.Windows.Controls.Canvas]::SetTop($art, $r * $rowH)
    [void]$sheet.Children.Add($art)
    if ($r -eq 0) {
      $lbl = New-Object System.Windows.Controls.TextBlock
      $lbl.Text = $states[$c]
      $lbl.FontSize = 13
      $lbl.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(90, 90, 110))
      [System.Windows.Controls.Canvas]::SetLeft($lbl, $c * $colW + 8)
      [System.Windows.Controls.Canvas]::SetTop($lbl, $sheetH - 20)
      [void]$sheet.Children.Add($lbl)
    }
  }
}

$sheet.Measure((New-Object System.Windows.Size($sheetW, $sheetH)))
$sheet.Arrange((New-Object System.Windows.Rect(0, 0, $sheetW, $sheetH)))
$sheet.UpdateLayout()

$pxW = [int][math]::Ceiling($sheetW * $Scale)
$pxH = [int][math]::Ceiling($sheetH * $Scale)
$dpi = [double](96 * $Scale)
$rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($pxW, $pxH, $dpi, $dpi, [System.Windows.Media.PixelFormats]::Pbgra32)
$rtb.Render($sheet)

$enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
$fs = [System.IO.File]::Create($Out)
$enc.Save($fs)
$fs.Close()
"preview -> $Out ($((Get-Item $Out).Length) bytes, ${sheetW}x${sheetH} @${Scale}x)"
