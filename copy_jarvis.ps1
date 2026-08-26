$src = Join-Path $PSScriptRoot "commands"
$dst = "C:\Program Files\jarvis-app\commands"
foreach ($f in @("photoshop","happr","opencode","steam","telegram_proxy","youtube_close","volume_extra")) {
  robocopy (Join-Path $src $f) (Join-Path $dst $f) /E /NFL /NDL /NJH /NJS
}
Write-Host "COPIED_OK"
