# Пример конфигурации jarvis-commands.
#
# Скопируй этот файл в config.local.psd1 (он в .gitignore) и укажи СВОИ пути.
# Это единственное место, где лежат машинозависимые пути: скрипты сборки/деплоя
# читают только отсюда. Токены %ZAPRET_BAT%, %YANDEX_BROWSER%, %YANDEX_MUSIC_LNK%
# в ручных .ahk заменяются на значения из этого файла при сборке.

@{
    # Куда разворачиваются команды JARVIS (обязательно)
    JarvisInstallDir = "C:\Program Files\jarvis-app"

    # Ассемблер AHK -> EXE (обязательно для build.ps1)
    Ahk2Exe    = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
    Ahk2ExeBin = "C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin"

    # pythonw для команд (commands.py) и для голосовых команд (voice_note.py)
    SystemPython = "C:\Program Files\Python314\pythonw.exe"
    VenvPython   = "C:\Users\ikra\Documents\Projects\teos-bot\venv\Scripts\pythonw.exe"

    # Папка teos-bot, где лежат commands.py и voice_note.py
    TeosBotDir = "C:\Users\ikra\Documents\Projects\teos-bot"

    # Токены для РУЧНЫХ команд (заменяются в .ahk при сборке)
    ZapretBat      = "C:\Users\ikra\Desktop\zapret-discord-youtube-1.10.2\general (ALT2).bat"
    YandexBrowser  = "C:\Program Files\Yandex\YandexBrowser\Application\browser.exe"
    YandexMusicLnk = "C:\Users\ikra\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Яндекс Музыка.lnk"

    # Город/локаль (используется подсказками; при желании можно передать и координаты)
    Location = "Барнаул"
}