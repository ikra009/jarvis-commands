#NoEnv
SendMode Input
DetectHiddenWindows, On
WinClose, ahk_exe %YANDEX_MUSIC_PROC%
Sleep, 500
Process, Close, %YANDEX_MUSIC_PROC%