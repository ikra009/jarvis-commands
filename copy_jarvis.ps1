$src = Join-Path $PSScriptRoot "commands"
$dst = "C:\Program Files\jarvis-app\commands"
foreach ($f in @("photoshop","happr","opencode","steam","telegram_proxy","youtube_close","zapret","youtube","yamusic","volume_extra","obsidian","animix","rest","pause","note","reply","ask")) {
  robocopy (Join-Path $src $f) (Join-Path $dst $f) /E /R:1 /W:1 /NFL /NDL /NJH /NJS
}
$sil = Join-Path $PSScriptRoot "sound\silence.wav"
Copy-Item $sil "C:\Program Files\jarvis-app\sound\jarvis-remake\silence.wav" -Force
Copy-Item $sil "C:\Program Files\jarvis-app\sound\jarvis-og\silence.wav" -Force
Write-Host "COPIED_OK"
