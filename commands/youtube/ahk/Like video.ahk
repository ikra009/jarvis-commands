SetTitleMatchMode, 2
IfWinExist, ahk_exe browser.exe
{
    WinActivate, ahk_exe browser.exe
    Sleep, 600
    ControlClick, x400 y760, ahk_exe browser.exe
}