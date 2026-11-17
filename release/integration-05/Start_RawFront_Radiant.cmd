@echo off
setlocal
cd /d "%~dp0" || exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Start_RawFront_Radiant.ps1"
if errorlevel 1 (
    echo RawFront Radiant could not start. See README-PL.txt.
    pause
    exit /b 1
)
