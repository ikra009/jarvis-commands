[CmdletBinding()]
param([switch]$NoRestart)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "common.ps1")

$cfg      = Get-JarvisConfig
$manifest = Import-JarvisManifest (Get-ManifestPath)
$cmdsRoot = Get-CommandsRoot
$dest     = $cfg['JarvisInstallDir']

Assert-Tools $cfg
if (-not (Test-Path -LiteralPath $dest)) { throw "[deploy] нет каталога JARVIS: $dest" }

$app = Join-Path $dest 'Priler.Jarvis.exe'
$wasRunning = $null -ne (Get-Process -Name 'Priler.Jarvis' -ErrorAction SilentlyContinue)

if ($wasRunning -and -not $NoRestart) {
    Write-Host '  JARVIS запущен — останавливаю, чтобы разблокировать exe...'
    Get-Process -Name 'Priler.Jarvis' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

# Список папок = generate + manual (без хардкода)
$allFolders = @($manifest.Generate | ForEach-Object { $_.Folder }) + @($manifest.Manual)
Write-Host ("DEPLOY → {0}  ({1} папок)" -f $dest, $allFolders.Count)

$failed = New-Object 'System.Collections.Generic.List[string]'
foreach ($folder in $allFolders) {
    $src = Join-Path $cmdsRoot $folder
    $dst = Join-Path (Join-Path $dest 'commands') $folder
    if (-not (Test-Path -LiteralPath $src)) { [void]$failed.Add($folder); Write-Host "  FAIL  $folder (нет в репо)" -ForegroundColor Red; continue }
    if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    $null = robocopy $src $dst /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
    if ($LASTEXITCODE -ge 8) {
        [void]$failed.Add($folder)
        Write-Host "  FAIL  $folder (robocopy $LASTEXITCODE)" -ForegroundColor Red
        Start-Sleep -Seconds 2
        $null = robocopy $src $dst /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
        if ($LASTEXITCODE -ge 8) {
            Write-Host "  FAIL  $folder (повтор: robocopy $LASTEXITCODE)" -ForegroundColor Red
        } else {
            [void]$failed.Remove($folder)
            Write-Host "  OK   $folder (после повтора)"
        }
        continue
    }
    Write-Host "  OK  $folder"
}

# silence для voice-команд
$silence = Join-Path (Get-RepoRoot) 'sound' 'silence.wav'
if (-not (Test-Path -LiteralPath $silence)) {
    Write-Host "  WARN  нет sound/silence.wav — пропуск копирования silence" -ForegroundColor Yellow
} else {
    foreach ($voice in @('jarvis-remake','jarvis-og')) {
        $vdir = Join-Path (Join-Path $dest 'sound') $voice
        if (-not (Test-Path -LiteralPath $vdir)) { New-Item -ItemType Directory -Path $vdir -Force | Out-Null }
        Copy-Item -LiteralPath $silence -Destination (Join-Path $vdir 'silence.wav') -Force -ErrorAction Stop
        Write-Host "  OK  silence.wav → $voice"
    }
}

# перезапуск
if ($wasRunning -and -not $NoRestart) {
    if (Test-Path -LiteralPath $app) {
        Start-Process -FilePath $app -WorkingDirectory $dest -WindowStyle Minimized
        Write-Host '  JARVIS перезапущен'
    } else {
        Write-Host "  WARN  нет $app — запусти приложение вручную" -ForegroundColor Yellow
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("DEPLOY OK но $($failed.Count) папок не скопированы: {0}" -f ($failed -join ', ')) -ForegroundColor Yellow
    exit 1
}
Write-Host 'DEPLOY OK'
exit 0