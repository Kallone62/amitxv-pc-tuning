@echo off
if /I "%~1"=="__KEEP_OPEN__" goto :MAIN
"%ComSpec%" /D /K CALL "%~f0" __KEEP_OPEN__
exit /b

:MAIN
@echo off
setlocal EnableExtensions DisableDelayedExpansion
title CS2 Gaming Scripts Launcher - Debug

rem This launcher stays in the package root.
rem All PowerShell scripts stay inside the package-root\.scripts folder.
set "LAUNCHER_REVISION=14.6"
set "LAUNCHER_FILE=%~f0"
for %%I in ("%~dp0.") do set "LAUNCHER_DIR=%%~fI"
set "SCRIPTS_DIR=%LAUNCHER_DIR%\.scripts"
set "LOG_FILE=%LAUNCHER_DIR%\Run_CS2_Gaming_Scripts-debug.log"
set "WIN_SCRIPT=%SCRIPTS_DIR%\CS2-GamingOnly-Pro-v1.0.8.ps1"
set "I226V_SCRIPT=%SCRIPTS_DIR%\I226V_Baseline_v2.ps1"
set "DEVICE_SCRIPT=%SCRIPTS_DIR%\Gaming-Device-Disable-v2.ps1"
set "BACKGROUND_SCRIPT=%SCRIPTS_DIR%\Gaming-Background-Cleanup-v1.ps1"
set "POLICY_SCRIPT=%SCRIPTS_DIR%\PostFormat-Policy-Baseline-v1.ps1"
set "WU_DRIVER_SCAN_SCRIPT=%SCRIPTS_DIR%\WU-Driver-Scan-v1.ps1"
set "LOWRISK_SCRIPT=%SCRIPTS_DIR%\PostFormat-LowRisk-Background-v1.ps1"
set "APPPRIVACY_SCRIPT=%SCRIPTS_DIR%\PostFormat-App-Privacy-Capabilities-v1.ps1"
set "DEVICEPOWER_SCRIPT=%SCRIPTS_DIR%\Gaming-Device-Power-Baseline-v1.ps1"
set "RUN_STARTED=%DATE% %TIME%"
set "PREFLIGHT_STATUS=NOT RUN"
set "WIN_STATUS=NOT RUN"
set "I226V_STATUS=NOT RUN"
set "DEVICE_STATUS=NOT RUN"
set "BACKGROUND_STATUS=NOT RUN"
set "POLICY_STATUS=NOT RUN"
set "LOWRISK_STATUS=NOT RUN"
set "APPPRIVACY_STATUS=NOT RUN"
set "DEVICEPOWER_STATUS=NOT RUN"
set "WIN_EXIT_CODE=N/A"
set "I226V_EXIT_CODE=N/A"
set "DEVICE_EXIT_CODE=N/A"
set "BACKGROUND_EXIT_CODE=N/A"
set "POLICY_EXIT_CODE=N/A"
set "LOWRISK_EXIT_CODE=N/A"
set "APPPRIVACY_EXIT_CODE=N/A"
set "DEVICEPOWER_EXIT_CODE=N/A"
set "FINAL_EXIT_CODE=1"
set "PARTIAL_STATUS=0"

>"%LOG_FILE%" echo CS2 Gaming Scripts Launcher - Revision %LAUNCHER_REVISION%
>>"%LOG_FILE%" echo Started: %RUN_STARTED%
>>"%LOG_FILE%" echo Launcher file: "%LAUNCHER_FILE%"
>>"%LOG_FILE%" echo Scripts folder: "%SCRIPTS_DIR%"

echo ============================================================
echo   CS2 GAMING SCRIPTS LAUNCHER - REVISION %LAUNCHER_REVISION%
echo ============================================================
echo Launcher file  : "%LAUNCHER_FILE%"
echo Scripts folder : "%SCRIPTS_DIR%"
echo Debug log      : "%LOG_FILE%"
echo ============================================================
echo.

if not exist "%WIN_SCRIPT%" (
    echo.
    echo ERROR: CS2-GamingOnly-Pro-v1.0.8.ps1 was not found.
    echo Expected:
    echo "%WIN_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%I226V_SCRIPT%" (
    echo.
    echo ERROR: I226V_Baseline_v2.ps1 was not found.
    echo Put it inside the .scripts folder beside CS2-GamingOnly-Pro-v1.0.8.ps1.
    echo Expected:
    echo "%I226V_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%DEVICE_SCRIPT%" (
    echo.
    echo ERROR: Gaming-Device-Disable-v2.ps1 was not found.
    echo Put it inside the .scripts folder beside the other PowerShell scripts.
    echo Expected:
    echo "%DEVICE_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%BACKGROUND_SCRIPT%" (
    echo.
    echo ERROR: Gaming-Background-Cleanup-v1.ps1 was not found.
    echo Put it inside the .scripts folder beside the other PowerShell scripts.
    echo Expected:
    echo "%BACKGROUND_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%POLICY_SCRIPT%" (
    echo.
    echo ERROR: PostFormat-Policy-Baseline-v1.ps1 was not found.
    echo Expected:
    echo "%POLICY_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%WU_DRIVER_SCAN_SCRIPT%" (
    echo.
    echo ERROR: WU-Driver-Scan-v1.ps1 was not found.
    echo Expected:
    echo "%WU_DRIVER_SCAN_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%LOWRISK_SCRIPT%" (
    echo.
    echo ERROR: PostFormat-LowRisk-Background-v1.ps1 was not found.
    echo Expected:
    echo "%LOWRISK_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%APPPRIVACY_SCRIPT%" (
    echo.
    echo ERROR: PostFormat-App-Privacy-Capabilities-v1.ps1 was not found.
    echo Expected:
    echo "%APPPRIVACY_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

if not exist "%DEVICEPOWER_SCRIPT%" (
    echo.
    echo ERROR: Gaming-Device-Power-Baseline-v1.ps1 was not found.
    echo Expected:
    echo "%DEVICEPOWER_SCRIPT%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=2"
    goto :REPORT
)

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" (
    echo.
    echo ERROR: Windows PowerShell 5.1 was not found.
    echo Expected:
    echo "%POWERSHELL_EXE%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=3"
    goto :REPORT
)

set "PREFLIGHT_STATUS=OK"

pushd "%SCRIPTS_DIR%" >nul
if errorlevel 1 (
    echo.
    echo ERROR: Could not open the .scripts folder:
    echo "%SCRIPTS_DIR%"
    echo.
    set "PREFLIGHT_STATUS=FAILED"
    set "FINAL_EXIT_CODE=4"
    goto :REPORT
)

set "FINAL_EXIT_CODE=0"

echo [1/8] Running CS2 Gaming-Only baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%WIN_SCRIPT%"
set "WIN_EXIT_CODE=%ERRORLEVEL%"

if "%WIN_EXIT_CODE%"=="0" (
    set "WIN_STATUS=OK"
) else (
    set "WIN_STATUS=FAILED"
    set "FINAL_EXIT_CODE=%WIN_EXIT_CODE%"
)

echo.
echo [2/8] Running Intel I226-V baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%I226V_SCRIPT%"
set "I226V_EXIT_CODE=%ERRORLEVEL%"

if "%I226V_EXIT_CODE%"=="0" (
    set "I226V_STATUS=OK"
) else (
    set "I226V_STATUS=FAILED"
    set "FINAL_EXIT_CODE=%I226V_EXIT_CODE%"
)

echo.
echo [3/8] Running gaming device disable layer...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEVICE_SCRIPT%" -Mode Apply
set "DEVICE_EXIT_CODE=%ERRORLEVEL%"

if "%DEVICE_EXIT_CODE%"=="0" (
    set "DEVICE_STATUS=OK"
) else (
    set "DEVICE_STATUS=FAILED"
    set "FINAL_EXIT_CODE=%DEVICE_EXIT_CODE%"
)

echo.
echo [4/8] Running gaming background cleanup...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BACKGROUND_SCRIPT%" -Mode Apply -EdgeUpdateCheckMinutes 1440
set "BACKGROUND_EXIT_CODE=%ERRORLEVEL%"

if "%BACKGROUND_EXIT_CODE%"=="0" (
    set "BACKGROUND_STATUS=OK"
) else (
    set "BACKGROUND_STATUS=FAILED"
    set "FINAL_EXIT_CODE=%BACKGROUND_EXIT_CODE%"
)

echo.
echo [5/8] Running update/security/file-intervention policy baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%POLICY_SCRIPT%" -Mode Apply
set "POLICY_EXIT_CODE=%ERRORLEVEL%"

if "%POLICY_EXIT_CODE%"=="0" (
    set "POLICY_STATUS=OK"
) else (
    if "%POLICY_EXIT_CODE%"=="10" (
        set "POLICY_STATUS=PARTIAL - TAMPER PROTECTION / DEFENDER"
        set "PARTIAL_STATUS=1"
    ) else (
        set "POLICY_STATUS=FAILED"
        set "FINAL_EXIT_CODE=%POLICY_EXIT_CODE%"
    )
)

echo.
echo [6/8] Running low-risk background feature baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOWRISK_SCRIPT%" -Mode Apply
set "LOWRISK_EXIT_CODE=%ERRORLEVEL%"

if "%LOWRISK_EXIT_CODE%"=="0" (
    set "LOWRISK_STATUS=OK"
) else (
    if "%LOWRISK_EXIT_CODE%"=="10" (
        set "LOWRISK_STATUS=PARTIAL - OPTIONAL POLICY NOT RETAINED"
        set "PARTIAL_STATUS=1"
    ) else (
        set "LOWRISK_STATUS=FAILED"
        set "FINAL_EXIT_CODE=%LOWRISK_EXIT_CODE%"
    )
)

echo.
echo [7/8] Running app privacy capability baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APPPRIVACY_SCRIPT%" -Mode Apply
set "APPPRIVACY_EXIT_CODE=%ERRORLEVEL%"

if "%APPPRIVACY_EXIT_CODE%"=="0" (
    set "APPPRIVACY_STATUS=OK"
) else (
    if "%APPPRIVACY_EXIT_CODE%"=="10" (
        set "APPPRIVACY_STATUS=PARTIAL - POLICY NOT RETAINED"
        set "PARTIAL_STATUS=1"
    ) else (
        set "APPPRIVACY_STATUS=FAILED"
        set "FINAL_EXIT_CODE=%APPPRIVACY_EXIT_CODE%"
    )
)

echo.
echo [8/8] Running exact gaming device power baseline...
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEVICEPOWER_SCRIPT%" -Mode Apply
set "DEVICEPOWER_EXIT_CODE=%ERRORLEVEL%"

if "%DEVICEPOWER_EXIT_CODE%"=="0" (
    set "DEVICEPOWER_STATUS=OK"
) else (
    set "DEVICEPOWER_STATUS=FAILED"
    set "FINAL_EXIT_CODE=%DEVICEPOWER_EXIT_CODE%"
)

popd

:REPORT
set "RUN_FINISHED=%DATE% %TIME%"
>>"%LOG_FILE%" echo Finished: %RUN_FINISHED%
>>"%LOG_FILE%" echo Preflight: %PREFLIGHT_STATUS%
>>"%LOG_FILE%" echo CS2 v1.0.8: %WIN_STATUS% - exit code %WIN_EXIT_CODE%
>>"%LOG_FILE%" echo Intel I226-V v2: %I226V_STATUS% - exit code %I226V_EXIT_CODE%
>>"%LOG_FILE%" echo Gaming device disable: %DEVICE_STATUS% - exit code %DEVICE_EXIT_CODE%
>>"%LOG_FILE%" echo Gaming background cleanup: %BACKGROUND_STATUS% - exit code %BACKGROUND_EXIT_CODE%
>>"%LOG_FILE%" echo Policy baseline: %POLICY_STATUS% - exit code %POLICY_EXIT_CODE%
>>"%LOG_FILE%" echo Low-risk background: %LOWRISK_STATUS% - exit code %LOWRISK_EXIT_CODE%
>>"%LOG_FILE%" echo App privacy capabilities: %APPPRIVACY_STATUS% - exit code %APPPRIVACY_EXIT_CODE%
>>"%LOG_FILE%" echo Device power baseline: %DEVICEPOWER_STATUS% - exit code %DEVICEPOWER_EXIT_CODE%
>>"%LOG_FILE%" echo Final exit code: %FINAL_EXIT_CODE%
echo.
echo ============================================================
echo   FINAL EXECUTION REPORT
echo ============================================================
echo Started          : %RUN_STARTED%
echo Finished         : %RUN_FINISHED%
echo Scripts folder   : "%SCRIPTS_DIR%"
echo Preflight        : %PREFLIGHT_STATUS%
echo CS2 v1.0.8       : %WIN_STATUS% ^(exit code: %WIN_EXIT_CODE%^)
echo Intel I226-V v2  : %I226V_STATUS% ^(exit code: %I226V_EXIT_CODE%^)
echo Device disable   : %DEVICE_STATUS% ^(exit code: %DEVICE_EXIT_CODE%^)
echo Background cleanup: %BACKGROUND_STATUS% ^(exit code: %BACKGROUND_EXIT_CODE%^)
echo Policy baseline   : %POLICY_STATUS% ^(exit code: %POLICY_EXIT_CODE%^)
echo Low-risk background: %LOWRISK_STATUS% ^(exit code: %LOWRISK_EXIT_CODE%^)
echo App privacy        : %APPPRIVACY_STATUS% ^(exit code: %APPPRIVACY_EXIT_CODE%^)
echo Device power       : %DEVICEPOWER_STATUS% ^(exit code: %DEVICEPOWER_EXIT_CODE%^)
echo ------------------------------------------------------------

if "%FINAL_EXIT_CODE%"=="0" (
    if "%PARTIAL_STATUS%"=="1" (
        echo OVERALL RESULT    : SUCCESS WITH PARTIAL OPTIONAL/POLICY STATE - review warnings above.
    ) else (
        echo OVERALL RESULT    : SUCCESS - all steps completed.
    )
) else (
    echo OVERALL RESULT    : FAILED - review the error above.
)

echo Final exit code  : %FINAL_EXIT_CODE%
echo Debug log       : "%LOG_FILE%"
echo ============================================================
echo.
echo This debug window will stay open. Type EXIT to close it.
rem END OF FILE - REVISION 14.6
exit /b %FINAL_EXIT_CODE%
