@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Post-Format Application Installer - Revision 12

for %%I in ("%~dp0.") do set "PACK_ROOT=%%~fI"
set "APP_SCRIPT=%PACK_ROOT%\.scripts\Install-PostFormat-Apps.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "REPORT=%PACK_ROOT%\Run_PostFormat_Apps-debug.log"
set "STARTED=%DATE% %TIME%"
set "PREFLIGHT=FAILED"
set "APP_STATUS=NOT RUN"
set "APP_EXIT=N/A"
set "RESULT=2"
set "RUN_MODE=INSTALL"
set "APP_SWITCH="

echo ============================================================
echo   POST-FORMAT APPLICATION INSTALLER - REVISION 12
echo ============================================================
echo Launcher     : "%~f0"
echo Script       : "%APP_SCRIPT%"
echo.

if /I "%~1"=="-Preview" (
    set "RUN_MODE=PREVIEW"
    set "APP_SWITCH=-Preview"
) else if not "%~1"=="" (
    echo ERROR: Unsupported option. Use -Preview or run without options.
    goto :REPORT
)
if not "%~2"=="" (
    echo ERROR: Only one option is supported: -Preview.
    goto :REPORT
)

if not exist "%APP_SCRIPT%" (
    echo ERROR: Application PowerShell script was not found.
    echo Expected: "%APP_SCRIPT%"
    goto :REPORT
)
if not exist "%POWERSHELL_EXE%" (
    echo ERROR: Windows PowerShell 5.1 was not found.
    echo Expected: "%POWERSHELL_EXE%"
    goto :REPORT
)

set "PREFLIGHT=OK"
echo Mode: %RUN_MODE%
echo [1/1] Checking and installing selected applications and Microsoft runtimes...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP_SCRIPT%" %APP_SWITCH%
set "APP_EXIT=%ERRORLEVEL%"
if "%APP_EXIT%"=="2" set "PREFLIGHT=FAILED"
if not "%APP_EXIT%"=="0" (
    set "APP_STATUS=FAILED"
    set "RESULT=%APP_EXIT%"
    goto :REPORT
)
if "%RUN_MODE%"=="PREVIEW" (
    set "APP_STATUS=PREVIEW OK"
) else (
    set "APP_STATUS=OK"
)
set "RESULT=0"

:REPORT
set "FINISHED=%DATE% %TIME%"
>"%REPORT%" echo Post-Format Application Installer - Revision 12
>>"%REPORT%" echo Started: %STARTED%
>>"%REPORT%" echo Finished: %FINISHED%
>>"%REPORT%" echo Script: "%APP_SCRIPT%"
>>"%REPORT%" echo Mode: %RUN_MODE%
>>"%REPORT%" echo Preflight: %PREFLIGHT%
>>"%REPORT%" echo Applications: %APP_STATUS% - exit code %APP_EXIT%
>>"%REPORT%" echo Final exit code: %RESULT%
echo.
echo ============================================================
echo   FINAL EXECUTION REPORT
echo ============================================================
echo Started         : %STARTED%
echo Finished        : %FINISHED%
echo Mode            : %RUN_MODE%
echo Preflight       : %PREFLIGHT%
echo Applications    : %APP_STATUS% ^(exit code: %APP_EXIT%^)
echo Final exit code : %RESULT%
echo Launcher log    : "%REPORT%"
echo Detail logs     : "%PACK_ROOT%\PostFormat-Logs"
echo ============================================================
echo.
pause
exit /b %RESULT%
