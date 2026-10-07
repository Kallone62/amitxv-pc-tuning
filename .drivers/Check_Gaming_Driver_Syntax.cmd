@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Gaming Driver Installer v2.3.4 - Syntax Check

set "ROOT=%~dp0"
set "DRIVER_SCRIPT=%ROOT%Install-Gaming-Drivers-v2-LatestOfficial.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%DRIVER_SCRIPT%" (
    echo.
    echo ERROR: Missing:
    echo "%DRIVER_SCRIPT%"
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
echo   GAMING DRIVER INSTALLER v2.3.4 - POWERSHELL SYNTAX CHECK
echo ============================================================
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($env:DRIVER_SCRIPT,[ref]$tokens,[ref]$errors); if($errors.Count -gt 0){ $errors ^| ForEach-Object { Write-Host ('ERROR line {0}, column {1}: {2}' -f $_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message) -ForegroundColor Red }; exit 1 } else { Write-Host 'PowerShell parser: OK' -ForegroundColor Green; exit 0 }"
set "RC=%ERRORLEVEL%"

echo.
pause
exit /b %RC%
