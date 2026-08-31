[CmdletBinding()]
param([switch]$Strict)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "common.ps1")

$manifest = Import-JarvisManifest (Get-ManifestPath)
$cmdsRoot = Get-CommandsRoot
$repoRoot = Get-RepoRoot

$errors = [System.Collections.Generic.List[string]]::new()
$warns  = [System.Collections.Generic.List[string]]::new()

# ── структура манифеста ─────────────────────────────────────────
foreach ($g in $manifest.Generate) {
    if (-not $g.Subs -or $g.Subs.Count -eq 0) { [void]$errors.Add("generate/$($g.Folder): нет команд (sub:)"); continue }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $g.Subs) {
        if (-not $s.Exe)    { [void]$errors.Add("generate/$($g.Folder): sub без exe"); continue }
        if (-not $seen.Add($s.Exe)) { [void]$errors.Add("generate/$($g.Folder): дубль exe '$($s.Exe)'") }
        if (-not $s.Action) { [void]$errors.Add("generate/$($g.Folder)/$($s.Exe): нет action") }
        if ($s.Engine -notin @('voice','commands')) { [void]$errors.Add("generate/$($g.Folder)/$($s.Exe): engine '$($s.Engine)' (voice|commands)") }
        if (-not $s.Phrases -or $s.Phrases.Count -eq 0) { [void]$errors.Add("generate/$($g.Folder)/$($s.Exe): нет phrases") }
        if ($s.Confirm -and (-not $s.ConfirmSays -or $s.ConfirmSays.Count -eq 0)) { [void]$errors.Add("generate/$($g.Folder)/$($s.Exe): confirm:true требует confirm_says") }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $cmdsRoot $g.Folder))) {
        [void]$errors.Add("generate/$($g.Folder): нет папки commands/$($g.Folder)")
    }
}

# ── рассинхрон commands.yaml ↔ закоммиченные command.yaml ─────
foreach ($g in $manifest.Generate) {
    $expected = @(foreach ($s in $g.Subs) { Expand-Phrases -Phrases $s.Phrases -Swear $manifest.Swear })
    $actual   = @(Get-CommandYamlPhrases -Path (Join-Path (Join-Path $cmdsRoot $g.Folder) 'command.yaml'))
    $diff = @(Compare-Object ($expected | Sort-Object) ($actual | Sort-Object) -SyncWindow 0)
    if ($diff.Count) {
        [void]$errors.Add("generate/$($g.Folder): command.yaml рассинхронизирован с манифестом ($($diff.Count) фраз). Запусти build.ps1")
    }
    foreach ($s in $g.Subs) {
        $exe = Join-Path (Join-Path (Join-Path $cmdsRoot $g.Folder) 'ahk') "$($s.Exe).exe"
        if (-not (Test-Path -LiteralPath $exe)) {
            [void]$warns.Add("generate/$($g.Folder): нет собранного $($s.Exe).exe — запусти build.ps1")
        }
    }
}

# ── manual: command.yaml ←→ исходники ────────────────────────────
foreach ($mf in $manifest.Manual) {
    $yaml = Join-Path (Join-Path $cmdsRoot $mf) 'command.yaml'
    if (-not (Test-Path -LiteralPath $yaml)) { [void]$errors.Add("manual/$mf — нет command.yaml"); continue }
    foreach ($l in [IO.File]::ReadAllLines($yaml)) {
        $m2 = [regex]::Match($l.Trim(), '^exe_path:\s*ahk/(.+?\.exe)$')
        if ($m2.Success) {
            $srcStem = $m2.Groups[1].Value -replace '\.exe$', '.ahk'
            $srcAhk  = Join-Path (Join-Path (Join-Path $cmdsRoot $mf) 'ahk') $srcStem
            if (-not (Test-Path -LiteralPath $srcAhk)) {
                [void]$errors.Add("manual/$mf — exe_path '$($m2.Groups[1].Value)' но нет исходника $srcStem в ahk/")
            }
        }
    }
}

# ── дубликаты exe / конфликт фраз между папками ────────────────
$exeMap = @{}
foreach ($g in $manifest.Generate) {
    foreach ($s in $g.Subs) {
        $key = $s.Exe.Trim().ToLowerInvariant() + '|' + $s.Action.Trim().ToLowerInvariant()
        if ($exeMap.ContainsKey($key)) { [void]$warns.Add("одинаковый exe+action: '$($s.Exe)' (+action $($s.Action)) в $($g.Folder) и $($exeMap[$key])") }
        else { $exeMap[$key] = $g.Folder }
    }
}

$phraseOwner = @{}
foreach ($g in $manifest.Generate) {
    foreach ($s in $g.Subs) {
        foreach ($p in @(Expand-Phrases -Phrases $s.Phrases -Swear $manifest.Swear)) {
            $key = $p.Trim().ToLowerInvariant()
            $tag = "$($g.Folder)/$($s.Exe)"
            if ($phraseOwner.ContainsKey($key) -and $phraseOwner[$key] -ne $tag) {
                [void]$warns.Add("фраза «$p» уже доступна через $($phraseOwner[$key])")
            } elseif (-not $phraseOwner.ContainsKey($key)) { $phraseOwner[$key] = $tag }
        }
    }
}

# ── дубликаты фраз в пределах одной команды (должны исчезнуть из-за дедупа) ──
foreach ($g in $manifest.Generate) {
    foreach ($s in $g.Subs) {
        $list = @(Expand-Phrases -Phrases $s.Phrases -Swear $manifest.Swear)
        $uniq = @($list | Select-Object -Unique)
        if ($list.Count -ne $uniq.Count) {
            [void]$errors.Add("generate/$($g.Folder)/$($s.Exe): после расширения остались дубликаты фраз (SWEAR-баг?)")
        }
    }
}

# ── конфиг (только предупреждение — в CI его может не быть) ─────
$cfgPath = Get-LocalConfigPath
if (Test-Path -LiteralPath $cfgPath) {
    $cfg = Import-PowerShellDataFile -Path $cfgPath
    foreach ($k in @('ZapretBat','YandexBrowser','YandexMusicLnk')) {
        if ($cfg[$k] -and -not (Test-Path -LiteralPath $cfg[$k])) {
            [void]$warns.Add("config $k → нет пути: $($cfg[$k])")
        }
    }
} else {
    [void]$warns.Add('нет config.local.psd1 — build/deploy недоступны, но манифест проверен')
}

Write-Host "`nVALIDATE: ошибок=$($errors.Count) предупреждений=$($warns.Count)"
foreach ($e in $errors) { Write-Host "  ERROR  $e" -ForegroundColor Red }
foreach ($w in $warns)  { Write-Host "  WARN   $w" -ForegroundColor Yellow }

if ($errors.Count -gt 0) { exit 1 }
exit 0