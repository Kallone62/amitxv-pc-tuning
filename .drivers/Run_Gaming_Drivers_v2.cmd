@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Gaming Driver Installer v2.3.6 - Review Build

set "ROOT=%~dp0"
set "SCRIPT=%ROOT%Install-Gaming-Drivers-v2-LatestOfficial.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo ERROR: Missing:
    echo "%SCRIPT%"
    echo.
    pause
    exit /b 2
)

echo ============================================================
echo   GAMING DRIVER INSTALLER v2.3.6 - REVIEW BUILD
echo ============================================================
echo.
echo Downloads CURRENT official drivers directly from AMD, ASUS
echo and NVIDIA. No pinned driver version is stored in this pack.
echo.
echo Exact provider/version checks happen BEFORE each installer.
echo Exact current matches are skipped.
echo All six steps are prechecked before any driver is changed.
echo Temporary WU/PnP driver guard is enforced during install and removed only after 6/6 verification.
echo Precheck may download several gigabytes of official packages.
echo Elevated PowerShell is waited for; its real exit code is returned.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Install
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Driver installer completed.
) else (
    echo Driver installer FAILED with exit code %RC%.
)
echo.
pause
exit /b %RC%
