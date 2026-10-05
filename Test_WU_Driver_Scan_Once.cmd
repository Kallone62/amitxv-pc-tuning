@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Windows Update Driver-Only Scan Test

set "SCRIPT=%~dp0.scripts\WU-Driver-Scan-v1.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Missing "%SCRIPT%"
    pause
    exit /b 2
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"

echo.
echo Exit code: %RC%
echo Report: C:\ProgramData\GamingPolicyBaseline\WU-Driver-Scan\latest.txt
echo.
pause
exit /b %RC%
