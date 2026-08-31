[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "common.ps1")

$repo     = Get-RepoRoot
$cmdsRoot = Get-CommandsRoot
$cfg      = Get-JarvisConfig
$manifest = Import-JarvisManifest (Get-ManifestPath)

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-AhkLine($Sub, $Config) {
    if ($Sub.Engine -eq 'voice') {
        $py  = $Config['VenvPython']
        $pyd = Join-Path $Config['TeosBotDir'] 'voice_note.py'
        return ('Run, "{0}" "{1}" --once {2}' -f $py, $pyd, $Sub.Action)
    }
    $py  = $Config['SystemPython']
    $pyd = Join-Path $Config['TeosBotDir'] 'commands.py'
    $tokens = @(($Sub.Action -split ' ') | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } })
    return ('Run, "{0}" "{1}" {2}' -f $py, $pyd, ($tokens -join ' '))
}

function Generate-Folder($Folder, [string[]]$Swear, $Config, [string]$TargetRoot) {
    $fdir  = Join-Path $TargetRoot $Folder.Folder
    $ahkDir = Join-Path $fdir 'ahk'
    New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('list:')
    $nameLines = [System.Collections.Generic.List[string]]::new()

    foreach ($sub in $Folder.Subs) {
        $phrases = Expand-Phrases -Phrases $sub.Phrases -Swear $Swear
        $line = New-AhkLine -Sub $sub -Config $Config
        Write-Utf8NoBom -Path (Join-Path $ahkDir "$($sub.Exe).ahk") -Content "$line`r`n"
        [void]$lines.Add('  - command:')
        [void]$lines.Add('      action: ahk')
        [void]$lines.Add("      exe_path: ahk/$($sub.Exe).exe")
        [void]$lines.Add('      exe_args:')
        [void]$lines.Add('    voice:')
        [void]$lines.Add('      sounds:')
        $sounds = if ($sub.Engine -eq 'voice') { @('silence') } else { @('ok1','ok2','ok3') }
        foreach ($s in $sounds) { [void]$lines.Add("        - $s") }
        [void]$lines.Add('    phrases:')
        foreach ($p in $phrases) { [void]$lines.Add("      - $(ConvertTo-YamlScalar $p)") }
        [void]$nameLines.Add("$($sub.Exe):$($sub.Exe)")
    }
    Write-Utf8NoBom -Path (Join-Path $fdir 'command.yaml') -Content ($lines -join "`n")
    Write-Utf8NoBom -Path (Join-Path $fdir 'names.txt')    -Content ($nameLines -join "`n")
}

function Invoke-AhkCompile([string]$AhkPath, [string]$ExePath, $Config) {
    if (-not (Test-Path -LiteralPath $AhkPath)) { throw "[build] нет AHK: $AhkPath" }
    $p = Start-Process -FilePath $Config['Ahk2Exe'] `
        -ArgumentList "/in `"$AhkPath`" /out `"$ExePath`" /bin `"$($Config['Ahk2ExeBin'])`"" `
        -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "[build] Ahk2Exe код $($p.ExitCode) для $([IO.Path]::GetFileName($ExePath))" }
    if (-not (Test-Path -LiteralPath $ExePath)) { throw "[build] нет exe после компиляции: $ExePath" }
}

# ── -Check ───────────────────────────────────────────────────────
if ($Check) {
    $tmp = Join-Path $env:TEMP ("jarvis-check-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        foreach ($g in $manifest.Generate) {
            Generate-Folder -Folder $g -Swear $manifest.Swear -Config $cfg -TargetRoot $tmp
        }
        $diffs = [System.Collections.Generic.List[string]]::new()
        foreach ($g in $manifest.Generate) {
            foreach ($rel in @('command.yaml','names.txt')) {
                $a = Join-Path (Join-Path $cmdsRoot $g.Folder) $rel
                $b = Join-Path (Join-Path $tmp      $g.Folder) $rel
                if (-not (Test-Path -LiteralPath $a)) { [void]$diffs.Add("$($g.Folder)/${rel}: нет в репо"); continue }
                if (-not (Test-Path -LiteralPath $b)) { [void]$diffs.Add("$($g.Folder)/${rel}: не сгенерирован"); continue }
                if ((Get-FileHash -LiteralPath $a -Algorithm MD5).Hash -ne
                    (Get-FileHash -LiteralPath $b -Algorithm MD5).Hash) {
                    [void]$diffs.Add("$($g.Folder)/${rel}: отличается от сгенерированного")
                }
            }
            foreach ($src in (Get-ChildItem -LiteralPath (Join-Path (Join-Path $tmp $g.Folder) 'ahk') -Filter *.ahk -ErrorAction SilentlyContinue)) {
                $ra = Join-Path (Join-Path (Join-Path $cmdsRoot $g.Folder) 'ahk') $src.Name
                if (-not (Test-Path -LiteralPath $ra)) { [void]$diffs.Add("$($g.Folder)/ahk/$($src.Name): нет в репо"); continue }
                if ((Get-FileHash -LiteralPath $ra -Algorithm MD5).Hash -ne
                    (Get-FileHash -LiteralPath $src.FullName -Algorithm MD5).Hash) {
                    [void]$diffs.Add("$($g.Folder)/ahk/$($src.Name): изменится после сборки")
                }
            }
        }
        if ($diffs.Count -gt 0) {
            $diffs | ForEach-Object { Write-Host "  DIFF  $_" }
            throw "build -Check: команды рассинхронизированы с commands.yaml"
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force
        Write-Host 'CHECK OK: команды актуальны'
        exit 0
    } catch {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

# ── основной build ──────────────────────────────────────────────
Assert-Tools $cfg
foreach ($g in $manifest.Generate) {
    Generate-Folder -Folder $g -Swear $manifest.Swear -Config $cfg -TargetRoot $cmdsRoot
    foreach ($sub in $g.Subs) {
        $ahk = Join-Path (Join-Path (Join-Path $cmdsRoot $g.Folder) 'ahk') "$($sub.Exe).ahk"
        $exe = Join-Path (Join-Path (Join-Path $cmdsRoot $g.Folder) 'ahk') "$($sub.Exe).exe"
        Invoke-AhkCompile -AhkPath $ahk -ExePath $exe -Config $cfg
    }
    Write-Host "BUILT $($g.Folder) ($($g.Subs.Count) команд)"
}
foreach ($mf in $manifest.Manual) {
    $mAhk = Join-Path (Join-Path $cmdsRoot $mf) 'ahk'
    if (-not (Test-Path -LiteralPath $mAhk)) { Write-Host "SKIP ${mf}: нет ahk/" -ForegroundColor Yellow; continue }
    foreach ($src in (Get-ChildItem -LiteralPath $mAhk -Filter *.ahk)) {
        $resolved = Resolve-ManualAhkTokens -Text ([IO.File]::ReadAllText($src.FullName, [Text.Encoding]::UTF8)) -Config $cfg
        $tmpAhk = Join-Path $env:TEMP ("jarvis-m-" + [guid]::NewGuid().ToString('N') + '.ahk')
        [IO.File]::WriteAllText($tmpAhk, $resolved, (New-Object System.Text.UTF8Encoding($true)))
        try {
            Invoke-AhkCompile -AhkPath $tmpAhk -ExePath (Join-Path $mAhk "$($src.BaseName).exe") -Config $cfg
        } finally { Remove-Item -LiteralPath $tmpAhk -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "BUILT $mf (manual)"
}
Write-Host 'BUILD OK'
exit 0