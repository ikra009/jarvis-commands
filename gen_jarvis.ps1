$base = Join-Path $PSScriptRoot "commands"
$py = "C:\Program Files\Python314\pythonw.exe"
$cmd = "C:\Users\ikra\Documents\Projects\teos-bot\commands.py"
$ahk2exe = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$bin = "C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin"
$data = Join-Path $PSScriptRoot "jarvis_data.txt"
$enc = [Text.Encoding]::UTF8
$lines = [IO.File]::ReadAllLines($data, $enc)

$swear = @()
foreach ($l in $lines) {
  if ($l.StartsWith("SWEAR|")) { $swear = $l.Substring(6).Split(';') }
}

function Expand($phrases) {
  $out = @()
  foreach ($p in $phrases) {
    $out += $p
    foreach ($w in $swear) { $out += "$w $p"; $out += "$p $w" }
  }
  return $out
}

$folders = @{}
$order = @()
foreach ($l in $lines) {
  if ($l.StartsWith("SWEAR|") -or $l.Trim().Length -eq 0) { continue }
  $parts = $l.Split('|')
  if ($parts.Length -lt 4) { continue }
  $folder = $parts[0]; $exe = $parts[1]; $pyargs = $parts[2]; $ph = $parts[3].Split(';')
  if (-not $folders.ContainsKey($folder)) { $folders[$folder] = @(); $order += $folder }
  $folders[$folder] += @{exe=$exe; py=$pyargs; phrases=$ph}
}

foreach ($f in $order) {
  $fdir = Join-Path $base $f
  $ahkDir = Join-Path $fdir "ahk"
  New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null
  $yaml = "list:`n"
  $names = @()
  foreach ($spec in $folders[$f]) {
    $phrases = Expand $spec.phrases
    $ahkPath = Join-Path $ahkDir "$($spec.exe).ahk"
    $isReply = $spec.py -like "reply_*" -or $spec.py -eq "ask"
    if ($isReply) {
      $trig = "C:\Users\ikra\Documents\Projects\teos-bot\.vn_trigger"
      $ahkLine = "FileDelete, $trig`nFileAppend, $($spec.py), $trig"
    } else {
      $ahkLine = "Run, `"$py`" `"$cmd`" $($spec.py)"
    }
    Set-Content -LiteralPath $ahkPath -Value $ahkLine -Encoding ASCII
    & "$ahk2exe" /in "$ahkPath" /out (Join-Path $ahkDir "$($spec.exe).exe") /bin "$bin" | Out-Null
    $yaml += "- command:`n"
    $yaml += "    action: ahk`n"
    $yaml += "    exe_path: ahk/$($spec.exe).exe`n"
    $yaml += "    exe_args:`n"
    $yaml += "  voice:`n"
    $yaml += "    sounds:`n"
    $yaml += "    - ok1`n    - ok2`n    - ok3`n"
    $yaml += "  phrases:`n"
    foreach ($p in $phrases) { $yaml += "    - $p`n" }
    $names += "$($spec.exe):$($spec.exe)"
  }
  [System.IO.File]::WriteAllText((Join-Path $fdir "command.yaml"), $yaml.TrimEnd("`n"), [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $fdir "names.txt"), ($names -join "`n"), [System.Text.UTF8Encoding]::new($false))
  Write-Host "Built: $f"
}
Write-Host "DONE"
