SetTitleMatchMode, 2
IfWinExist, ahk_exe browser.exe
{
    WinActivate, ahk_exe browser.exe
    Sleep, 600
    ; YouTube "like" (thumbs up) button - coordinates depend on window size; adjust if it misses
    ControlClick, x400 y760, ahk_exe browser.exe
}
