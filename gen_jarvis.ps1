# gen_jarvis.ps1 — совместимая обёртка над scripts/build.ps1 (генерация + компиляция).
& (Join-Path $PSScriptRoot "scripts\build.ps1") @args
exit $LASTEXITCODE