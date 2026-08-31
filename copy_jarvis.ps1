# copy_jarvis.ps1 — совместимая обёртка над scripts/deploy.ps1 (копирование в JARVIS).
& (Join-Path $PSScriptRoot "scripts\deploy.ps1") @args
exit $LASTEXITCODE