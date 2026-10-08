@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Fresh Install - Windows 11 Pro - HARD-CODED

rem ============================================================
rem FIXED CONFIGURATION - NO AUTO DISCOVERY
rem ============================================================
set "TARGET_DRIVE=D:"
set "WIM_PATH=C:\Users\k52\Downloads\Windows11_Client_x64_tr-tr_26300_9457\sources\install.wim"
set "IMAGE_INDEX=4"
set "NEW_LABEL=Windows"
for %%I in ("%~dp0.") do set "SETUP_SOURCE=%%~fI"
set "SETUP_DEST=D:\SSD Setup"

rem ============================================================
rem SELF-ELEVATE
rem ============================================================
fltmc >nul 2>&1
if errorlevel 1 (
    echo [INFO] Administrator rights required. Requesting UAC...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process -FilePath 'cmd.exe' -Verb RunAs -ArgumentList '/c','\"\"%~f0\" %*\"'"
    exit /b
)

echo ============================================================
echo  FRESH INSTALL - WINDOWS 11 PRO
echo ============================================================
echo.
echo  SOURCE WIM : "%WIM_PATH%"
echo  IMAGE INDEX: %IMAGE_INDEX%  ^(Windows 11 Pro^)
echo  TARGET     : %TARGET_DRIVE%
echo  NEW LABEL  : %NEW_LABEL%
echo  SSD SETUP  : "%SETUP_SOURCE%"  --^>  "%SETUP_DEST%"
echo.
echo  EFI / BCD / OTHER WINDOWS INSTALLATIONS ARE NOT TOUCHED.
echo.
echo  WARNING: %TARGET_DRIVE% WILL BE QUICK-FORMATTED.
echo  Press Ctrl+C within 8 seconds to cancel.
timeout /t 8 /nobreak >nul

rem ============================================================
rem PRE-DESTRUCTIVE FIXED-PATH CHECKS
rem ============================================================
if /I "%SystemDrive%"=="%TARGET_DRIVE%" (
    echo.
    echo [ABORT] TARGET_DRIVE is the currently running Windows system drive.
    goto :fail
)

if /I "%~d0"=="%TARGET_DRIVE%" (
    echo.
    echo [ABORT] This script is running from %TARGET_DRIVE%.
    echo Move SSD Setup to the current Windows drive before running it.
    goto :fail
)

if not exist "%WIM_PATH%" (
    echo.
    echo [ABORT] Hard-coded WIM does not exist:
    echo "%WIM_PATH%"
    goto :fail
)

if not exist "%TARGET_DRIVE%\" (
    echo.
    echo [ABORT] Hard-coded target drive does not exist: %TARGET_DRIVE%
    goto :fail
)

echo.
echo [1/6] Validating hard-coded WIM and Index %IMAGE_INDEX% BEFORE formatting...
dism.exe /English /Get-WimInfo /WimFile:"%WIM_PATH%" /Index:%IMAGE_INDEX% >nul
if errorlevel 1 (
    echo [FAILED] WIM path/index validation failed. Target was NOT formatted.
    goto :fail
)
echo [OK] WIM/index validation passed.

rem ============================================================
rem FORMAT TARGET
rem ============================================================
echo.
echo [2/6] Quick-formatting %TARGET_DRIVE% as NTFS...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Format-Volume -DriveLetter 'D' -FileSystem NTFS -NewFileSystemLabel '%NEW_LABEL%' -Force -Confirm:$false | Out-Null"
if errorlevel 1 (
    echo [FAILED] Format-Volume failed.
    goto :fail
)
echo [OK] %TARGET_DRIVE% formatted.

rem ============================================================
rem APPLY WINDOWS IMAGE
rem ============================================================
echo.
echo [3/6] Applying Windows 11 Pro image...
dism.exe /Apply-Image /ImageFile:"%WIM_PATH%" /Index:%IMAGE_INDEX% /ApplyDir:%TARGET_DRIVE%\
if errorlevel 1 (
    echo [FAILED] DISM /Apply-Image failed.
    goto :fail
)
echo [OK] Windows image applied.

rem ============================================================
rem OFFLINE BOOTSTRAP GUARD + OOBE BYPASS
rem ============================================================
echo.
echo [4/6] Applying offline bootstrap policies...

rem Clear a stale mount name if a previous interrupted run left one.
reg.exe unload HKLM\OFFSOFT >nul 2>&1

reg.exe load HKLM\OFFSOFT "%TARGET_DRIVE%\Windows\System32\Config\SOFTWARE" >nul
if errorlevel 1 (
    echo [FAILED] Could not load offline SOFTWARE hive.
    goto :fail
)

reg.exe add "HKLM\OFFSOFT\Policies\Microsoft\Windows\WindowsUpdate\AU" ^
 /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul
if errorlevel 1 goto :regfail

reg.exe add "HKLM\OFFSOFT\Policies\Microsoft\Windows\WindowsUpdate" ^
 /v ExcludeWUDriversInQualityUpdate /t REG_DWORD /d 1 /f >nul
if errorlevel 1 goto :regfail

rem Modern PnP Windows Update source-search block.
reg.exe add "HKLM\OFFSOFT\Policies\Microsoft\Windows\DriverSearching" ^
 /v SearchOrderConfig /t REG_DWORD /d 0 /f >nul
if errorlevel 1 goto :regfail

rem Compatibility guard for older policy plumbing. Driver installer v2.3.6
rem removes this temporary value after all selected drivers verify successfully.
reg.exe add "HKLM\OFFSOFT\Policies\Microsoft\Windows\DriverSearching" ^
 /v DontSearchWindowsUpdate /t REG_DWORD /d 1 /f >nul
if errorlevel 1 goto :regfail

rem Allow offline/local-account OOBE path on the builds where this flag is honored.
reg.exe add "HKLM\OFFSOFT\Microsoft\Windows\CurrentVersion\OOBE" ^
 /v BypassNRO /t REG_DWORD /d 1 /f >nul
if errorlevel 1 goto :regfail

reg.exe unload HKLM\OFFSOFT >nul
if errorlevel 1 (
    echo [FAILED] Could not unload offline SOFTWARE hive.
    goto :fail
)

echo [OK] Offline policies applied:
echo      NoAutoUpdate=1
echo      ExcludeWUDriversInQualityUpdate=1
echo      SearchOrderConfig=0
echo      DontSearchWindowsUpdate=1
echo      BypassNRO=1

rem ============================================================
rem COPY THIS SSD SETUP TO NEW WINDOWS
rem ============================================================
echo.
echo [5/6] Copying SSD Setup into the new Windows partition...
robocopy "%SETUP_SOURCE%" "%SETUP_DEST%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NP
set "ROBO_RC=%ERRORLEVEL%"
if %ROBO_RC% GEQ 8 (
    echo [FAILED] ROBOCOPY returned exit code %ROBO_RC%.
    goto :fail
)
echo [OK] SSD Setup copied to "%SETUP_DEST%".

rem ============================================================
rem FINAL CHECK
rem ============================================================
echo.
echo [6/6] Final offline verification...
if not exist "%TARGET_DRIVE%\Windows\System32\Config\SOFTWARE" (
    echo [FAILED] Offline Windows SOFTWARE hive missing after apply.
    goto :fail
)
if not exist "%SETUP_DEST%\.drivers\Run_Gaming_Drivers_v2.cmd" (
    echo [WARNING] Expected driver launcher not found at:
    echo "%SETUP_DEST%\.drivers\Run_Gaming_Drivers_v2.cmd"
    echo The image itself is valid, but check SSD Setup contents before reboot.
)

echo.
echo ============================================================
echo  FRESH INSTALL PREPARATION COMPLETE
echo ============================================================
echo.
echo  Windows 11 Pro was applied to %TARGET_DRIVE%.
echo  Existing EFI/BCD was NOT modified.
echo  Temporary Windows Update / driver guards are active.
echo  OOBE BypassNRO flag is staged.
echo  SSD Setup is already copied into the new Windows root.
echo.
echo  After booting the new Windows:
echo    1. Complete OOBE offline.
echo    2. If Ethernet has no inbox driver, install the local I226-V INF once.
echo    3. Run C:\SSD Setup\.drivers\Run_Gaming_Drivers_v2.cmd
echo    4. Reboot after driver completion.
echo    5. Run C:\SSD Setup\Run_CS2_Gaming_Scripts.cmd
echo    6. Run C:\SSD Setup\Run_PostFormat_Apps.cmd
echo.
echo  Rebooting in 15 seconds. Press Ctrl+C to stay in this Windows.
shutdown.exe /r /t 15 /c "Fresh Windows image applied. Choose the newly formatted Windows entry in the existing boot menu."
exit /b 0

:regfail
echo [FAILED] Offline registry policy write failed.
reg.exe unload HKLM\OFFSOFT >nul 2>&1
goto :fail

:fail
echo.
echo ============================================================
echo  FRESH INSTALL FAILED / ABORTED
echo ============================================================
echo No BCD or EFI changes were attempted.
echo.
pause
exit /b 1
