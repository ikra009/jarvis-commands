# jarvis-commands

Голосовые команды для [Priler/jarvis](https://github.com/Priler/jarvis) (проверено на `jarvis-app 0.0.2`, ветка `beta`).

Я не автор самого Jarvis — только команд для него.

## Состав

| Путь | Что это |
|---|---|
| `commands.yaml` | **Единственный источник истины** о командах (манифест) |
| `config.example.psd1` | Шаблон конфигурации (пути машин) |
| `commands/generate…` | Папки, собираемые полностью из манифеста |
| `commands/{youtube,yamusic,zapret}` | Ручные команды (свой `command.yaml`), пути через токены |
| `scripts/` | `build.ps1`, `deploy.ps1`, `validate.ps1`, `common.ps1`, `confirm.py` |
| `sound/silence.wav` | Беззвучный звук для «немых» voice-команд (`/silence/`) |

Папки в `commands.yaml → stock:` — оригинальные команды JARVIS/MSI, **не** разворачиваются, нужны как справка.

## Настройка

```powershell
Copy-Item config.example.psd1 config.local.psd1
# и впиши свои пути: Python, teos-bot, Ahk2Exe, zapret, Яндекс-браузер и т.д.
```
`config.local.psd1` в `.gitignore` — пути машины не хранятся в репозитории.

## Типы команд в манифесте

У каждой под-команды в `generate:` есть:

- `exe` — имя exe/ahk (без расширения);
- `action` — действие (например: `set_volume 25`, `reply_time`, `note_dictate`);
- `engine` — как выполняется:
  - `commands` → `pythonw commands.py <action>` (запуск приложений, громкость…),
  - `voice` → `pythonw voice_note.py --once <action>` (тихие голосовые ответы: время, погода…);
- `phrases` — фразы запуска. Мат из списка `swear` и префикс/суффикс добавляются автоматически, **с дедупликацией** (если фраза уже содержит слово из `swear`, варианты не плодятся).

## Сборка и развёртывание

```powershell
scripts/validate.ps1      # проверка целостности (без сборки, запускается в CI)
scripts/build.ps1         # генерация команд из манифеста + компиляция ahk → exe (Ahk2Exe, Path к ошибкам)
scripts/build.ps1 -Check  # сверка, что закоммиченные команды совпадают с манифестом;
                          # вызывает ошибку при расхождении — используется в CI
scripts/deploy.ps1        # копирование папок (список берётся из манифеста!) в JARVIS + silence.wav
scripts/deploy.ps1 -NoRestart
```

`gen_jarvis.ps1` и `copy_jarvis.ps1` — совместимые обёртки над `build.ps1` / `deploy.ps1`.

Ключевые коды робокопии проверяются как ошибки (≥ 8 = сбой копирования), Ahk2Exe — по коду возврата, вместо молчаливого «COPIED_OK».

## Подтверждение опасных команд

В манифесте у под-команды можно указать `confirm: true` и `confirm_says: [фразы…]`.
Тогда команда сначала «спрашивает» (через `scripts/confirm.py --ask`), а выполняется только
команда-подтверждение (`confirm.py --exec`). Сейчас этим никто не пользуется — механизм готов по запросу.

## CI

`.github/workflows/ci.yml` на Windows запускает `scripts/validate.ps1` при каждом push/PR —
проверка манифеста, рассинхрона команд и конфигурации без привязки к конкретной машине.

## Требования

- Windows, PowerShell 5.1+;
- AutoHotkey v1.1 (компилятор `Ahk2Exe.exe` + `Unicode 64-bit.bin`);
- [teos-bot](https://github.com/ikra-dl/teos-bot) — через него работают `commands.py` и `voice_note.py`;
- для голосовых ответов — настроенный в JARVIS голос + `sound/silence.wav` в `sound/jarvis-remake/` и `sound/jarvis-og/`.