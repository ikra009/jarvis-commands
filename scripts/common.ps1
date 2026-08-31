# common.ps1 — общая библиотека jarvis-commands.
#
# Единственный источник истины о командах — commands.yaml в корне репозитория.
# Единственное место с машинозависимыми путями — config.local.psd1.
# Все .ahk генерируемых папок и пути вручную-хран. Команды:
#   build.ps1    — генерация commands/ из commands.yaml + компиляция AHK
#   deploy.ps1   — копирование в JARVIS (папки берутся из манифеста)
#   validate.ps1 — проверки целостности / рассинхрона с commands.yaml


# --- пути репозитория ---
function Get-RepoRoot { return Split-Path -Parent $PSScriptRoot }
function Get-ManifestPath { return (Join-Path (Get-RepoRoot) 'commands.yaml') }
function Get-CommandsRoot { return (Join-Path (Get-RepoRoot) 'commands') }
function Get-LocalConfigPath { return (Join-Path (Get-RepoRoot) 'config.local.psd1') }


# --- конфигурация ---
# Import-PowerShellDataFile в PS 5.1 читает UTF-8 без BOM как ANSI (ломает кириллицу).
# Поэтому psd1 обязан иметь BOM; функция сама дописывает BOM, если его нет.
function Ensure-Utf8Bom {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "[config] добавлен UTF-8 BOM в $(Split-Path -Leaf $Path)"
    }
}

function Get-JarvisConfig {
    $path = Get-LocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "[config] не найден $path. Скопируй config.example.psd1 в config.local.psd1 и укажи свои пути."
    }
    Ensure-Utf8Bom $path
    return Import-PowerShellDataFile -Path $path
}

# Проверка что все ключи конфига не пустые и указанные файлы существуют.
function Assert-Tools {
    param($Config)
    foreach ($k in @('JarvisInstallDir','SystemPython','VenvPython','TeosBotDir','Ahk2Exe','Ahk2ExeBin')) {
        if (-not $Config[$k]) { throw "[config] пустой ключ $k — заполни config.local.psd1" }
        if (-not (Test-Path -LiteralPath $Config[$k])) { throw "[config] НЕТ пути по ключу $k : $($Config[$k])" }
    }
    foreach ($f in @('commands.py','voice_note.py')) {
        $pp = Join-Path $Config['TeosBotDir'] $f
        if (-not (Test-Path -LiteralPath $pp)) { throw "[config] в TeosBotDir нет $f : $pp" }
    }
    foreach ($k in @('ZapretBat','YandexBrowser','YandexMusicLnk')) {
        if ($Config[$k] -and -not (Test-Path -LiteralPath $Config[$k])) {
            Write-Host "[config] ПРЕДУПРЕЖДЕНИЕ: НЕТ пути по ключу $k : $($Config[$k])" -ForegroundColor Yellow
        }
    }
}


# --- YAML: строгий парсер подмножества, используемого в командах и манифесте ---
function ConvertFrom-YamlScalar {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v.Length -ge 2 -and $v[0] -eq "'" -and $v[$v.Length - 1] -eq "'") { $v = $v.Substring(1, $v.Length - 2).Replace("''", "'") }
    elseif ($v.Length -ge 2 -and $v[0] -eq '"' -and $v[$v.Length - 1] -eq '"') { $v = $v.Substring(1, $v.Length - 2) }
    return $v
}

function ConvertTo-YamlScalar {
    param([string]$Value)
    if ($null -eq $Value) { return "''" }
    return ("'{0}'" -f ($Value -replace "'", "''"))
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}


# --- манифест commands.yaml ---
function Import-JarvisManifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "[manifest] не найден: $Path" }

    $swearList = [System.Collections.Generic.List[string]]::new()
    $manualList = [System.Collections.Generic.List[string]]::new()
    $stockList = [System.Collections.Generic.List[string]]::new()
    $generated = [System.Collections.Generic.List[object]]::new()
    $meta = [ordered]@{}
    $section = $null
    $folder = $null
    $sub = $null
    $phrases = $null

    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $t = $raw.TrimEnd()
        $body = $t.TrimStart()
        if ($body -eq '' -or $body.StartsWith('#')) { continue }
        $indent = $t.Length - $body.Length

        $isItem = $body.StartsWith('- ')
        if ($isItem) { $body = $body.Substring(2) }

        $m = [regex]::Match($body, '^([\w_]+):\s*(.*)$')
        $isKey = $m.Success
        $key = if ($isKey) { $m.Groups[1].Value } else { $null }
        $val = if ($isKey) { $m.Groups[2].Value.Trim() } else { $body.Trim() }

        if ($indent -eq 0) {
            if ($isItem) {
                $mf = [regex]::Match($body, '^([\w_]+):\s*(.*)$')
                if ($section -eq 'generate' -and $mf.Success -and $mf.Groups[1].Value -eq 'folder') {
                    $folder = [ordered]@{ Folder = (ConvertFrom-YamlScalar $mf.Groups[2].Value.Trim()); Subs = [System.Collections.Generic.List[object]]::new() }
                    [void]$generated.Add($folder)
                    $sub = $null; $phrases = $null
                    continue
                }
                if ($section -in @('swear','manual','stock')) { [void](Get-Variable ('{0}List' -f $section) -ValueOnly).Add((ConvertFrom-YamlScalar $val)); continue }
                throw "[manifest] список вне ожидаемого места: $raw"
            }
            if ($isKey) {
                $section = $key
                $folder = $null; $sub = $null; $phrases = $null
                if ($section -in @('swear','manual','stock') -and $val -ne '') {
                    if ($val.StartsWith('[') -and $val.EndsWith(']')) {
                        foreach ($x in ($val.Substring(1, $val.Length - 2) -split ',')) {
                            $x = $x.Trim()
                            if ($x -ne '') { [void](Get-Variable ('{0}List' -f $section) -ValueOnly).Add((ConvertFrom-YamlScalar $x)) }
                        }
                    } else { [void](Get-Variable ('{0}List' -f $section) -ValueOnly).Add((ConvertFrom-YamlScalar $val)) }
                }
                continue
            }
            throw "[manifest] неожиданная строка: $raw"
        }

        if ($section -eq 'meta') {
            if ($isKey) { $meta[$key] = if ($val -eq '') { $null } else { ConvertFrom-YamlScalar $val } }
            continue
        }

        if ($section -eq 'generate') {
            if ($null -eq $folder) { throw "[manifest] generate без folder: $raw" }
            if ($isItem -and $key -eq 'sub') { throw "[manifest] sub должна быть ключом (без '-'): $raw" }
            if ($isKey -and $key -eq 'sub') { continue }
            if ($indent -le 2 -and $isItem -and $key -eq 'exe') {
                $sub = [ordered]@{ Exe = (ConvertFrom-YamlScalar $val); Action = $null; Engine = $null; Confirm = $false; ConfirmSays = $null; Phrases = $null }
                [void]$folder.Subs.Add($sub)
                $phrases = $null
                continue
            }
            if ($null -eq $sub) { throw "[manifest] поля вне sub: $raw" }
            if ($isKey -and $key -eq 'phrases') {
                $phrases = [System.Collections.Generic.List[string]]::new()
                $sub['Phrases'] = $phrases
                continue
            }
            if ($isItem -and $null -ne $phrases) { [void]$phrases.Add((ConvertFrom-YamlScalar $val)); continue }
            if ($isKey -and $key -in @('action','engine')) { $sub[$key] = $val; continue }
            if ($isKey -and $key -eq 'confirm') { $sub[$key] = ($val -eq 'true'); continue }
            if ($isKey -and $key -eq 'confirm_says') {
                $cs = [System.Collections.Generic.List[string]]::new()
                $sub['ConfirmSays'] = $cs
                $inner = $val
                if ($inner -ne '') {
                    if ($inner.StartsWith('[') -and $inner.EndsWith(']')) {
                        foreach ($x in ($inner.Substring(1, $inner.Length - 2) -split ',')) { $x = $x.Trim(); if ($x) { [void]$cs.Add((ConvertFrom-YamlScalar $x)) } }
                    } else { [void]$cs.Add((ConvertFrom-YamlScalar $inner)) }
                }
                continue
            }
            throw "[manifest] неразобранная строка в generate: $raw"
        }

        if ($section -in @('swear','manual','stock')) {
            if ($isItem) { [void](Get-Variable ('{0}List' -f $section) -ValueOnly).Add((ConvertFrom-YamlScalar $val)); continue }
            throw "[manifest] строка в списке $section : $raw"
        }
        throw "[manifest] неизвестная секция: $section"
    }

    return [ordered]@{
        Meta     = $meta
        Swear    = @($swearList)
        Manual   = @($manualList)
        Stock    = @($stockList)
        Generate = @(
            foreach ($f in $generated) {
                [pscustomobject]@{
                    Folder = $f.Folder
                    Subs   = @(
                        foreach ($s in $f.Subs) {
                            [pscustomobject]@{
                                Exe         = $s.Exe
                                Action      = [string]$s.Action
                                Engine      = [string]$s.Engine
                                Confirm     = [bool]$s.Confirm
                                ConfirmSays = @($s.ConfirmSays)
                                Phrases     = @($s.Phrases)
                            }
                        }
                    )
                }
            }
        )
    }
}


# --- расширение фраз (аналог SWEAR из jarvis_data.txt), с антидубликатами ---
function Expand-Phrases {
    param([string[]]$Phrases, [string[]]$Swear)
    $out = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($base in $Phrases) {
        $b = $base.Trim()
        if ($b -eq '') { continue }

        $containsSwear = $false
        foreach ($sw in $Swear) {
            if ($sw -ne '' -and $b.IndexOf($sw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $containsSwear = $true; break }
        }
        [void]$out.Add($b)
        if ($containsSwear) { continue }   # база уже содержит ругательное — варианты не нужны

        foreach ($sw in $Swear) {
            if ($sw -eq '') { continue }
            [void]$out.Add(("{0} {1}" -f $sw, $b))
            [void]$out.Add(("{0} {1}" -f $b, $sw))
        }
    }
    return [string[]]$out
}


# --- чтение фраз из закоммиченного command.yaml (для drift-проверки) ---
function Get-CommandYamlPhrases {
    param([string]$Path)
    $out = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return ,@() }
    $in = $false
    foreach ($l in [System.IO.File]::ReadAllLines($Path)) {
        $t = $l.Trim()
        if ($in) {
            # элемент списка на уровне ≤4 = уже не фраза (следующий - command/voice/phrases)
            $indent = $l.Length - $l.TrimStart().Length
            if ($indent -le 4) { $in = $false }
            elseif ($t.StartsWith('-')) { [void]$out.Add((ConvertFrom-YamlScalar ($t.Substring(1).Trim()))) }
            continue
        }
        if ($t -eq 'phrases:') { $in = $true }
    }
    return [string[]]$out
}


# --- сборка строк для .ahk ---
function New-AhkLine {
    param($Sub, $Config)
    if ($Sub.Engine -eq 'voice') {
        $vn = Join-Path $Config['TeosBotDir'] 'voice_note.py'
        return ('Run, "{0}" "{1}" --once {2}' -f $Config['VenvPython'], $vn, $Sub.Action)
    }
    $cmd = Join-Path $Config['TeosBotDir'] 'commands.py'
    $tokens = @(($Sub.Action -split ' ') | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } })
    return ('Run, "{0}" "{1}" {2}' -f $Config['SystemPython'], $cmd, ($tokens -join ' '))
}

function Invoke-AhkCompile {
    param($Config, [string]$AhkPath, [string]$ExePath)
    if (-not (Test-Path -LiteralPath $AhkPath)) { throw "[build] нет исходника AHK: $AhkPath" }
    $exeDir = Split-Path -Parent $ExePath
    if (-not (Test-Path -LiteralPath $exeDir)) { New-Item -ItemType Directory -Path $exeDir -Force | Out-Null }
$p = Start-Process -FilePath $Config['Ahk2Exe'] `
        -ArgumentList "/in `"$AhkPath`" /out `"$ExePath`" /bin `"$($Config['Ahk2ExeBin'])`"" `
        -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "[build] Ahk2Exe вернул код $($p.ExitCode) для $(Split-Path -Leaf $ExePath)"
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "[build] после компиляции нет файла: $ExePath"
    }
}

# Замена токенов %ZAPRET_BAT%, %YANDEX_BROWSER%, %YANDEX_MUSIC_LNK% в ручных .ahk.
# Неизвестные токены — ошибка: так мы не пропустим захардкоженные пути.
function Resolve-ManualAhkTokens {
    param([string]$Text, $Config)
    $map = [ordered]@{
        '%ZAPRET_BAT%'       = $Config['ZapretBat']
        '%YANDEX_BROWSER%'   = $Config['YandexBrowser']
        '%YANDEX_MUSIC_LNK%' = $Config['YandexMusicLnk']
        '%YANDEX_MUSIC_PROC%' = [IO.Path]::GetFileNameWithoutExtension($Config['YandexMusicLnk']) + '.exe'
    }
    $out = $Text
    foreach ($k in $map.Keys) {
        if (-not $map[$k]) { throw "[build] токен $k требует ключ конфига, но он пуст" }
        $out = $out.Replace($k, $map[$k])
    }
    $tmp = [regex]::Replace($out, '%A_ScriptDir%', '')
    if ($tmp -match '%[A-Z_]+%') { throw "[build] в ручном .ahk остался неизвестный токен: $([regex]::Match($tmp, '%[A-Z_]+%').Value)" }
    return $out
}