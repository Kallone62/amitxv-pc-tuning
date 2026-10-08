@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Gaming Driver Installer v2.3.6 - Audit

set "ROOT=%~dp0"
set "SCRIPT=%ROOT%Install-Gaming-Drivers-v2-LatestOfficial.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
    echo.
    echo ERROR: Missing:
    echo "%SCRIPT%"
    echo.
    pause
    exit /b 2
)

if not exist "%POWERSHELL_EXE%" (
    echo.
    echo ERROR: Windows PowerShell 5.1 was not found:
    echo "%POWERSHELL_EXE%"
    echo.
    pause
    exit /b 3
)

echo ============================================================
echo   GAMING DRIVER INSTALLER v2.3.6 - AUDIT
echo ============================================================
echo.
echo No installer or PnP binding command will be executed.
echo Audit may download and extract several GB of official packages.
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Audit
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Driver audit completed successfully.
) else (
    echo Driver audit FAILED with exit code %RC%.
)
echo.
pause
exit /b %RC%
