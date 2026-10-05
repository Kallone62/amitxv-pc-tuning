@echo off
setlocal EnableExtensions DisableDelayedExpansion
title NVIDIA ve DirectX Shader Cache Temizligi
color 0B

set /a CLEANED=0
set /a PARTIAL=0
set /a MISSING=0

echo ==========================================================
echo NVIDIA VE DIRECTX SHADER CACHE TEMIZLIGI
echo ==========================================================
echo.
echo Acik oyunlari, NVIDIA App'i, Steam'i ve grafik kullanan
echo programlari kapatmaniz onerilir.
echo.
echo Bu arac NVIDIA surucu ve Windows DirectX shader
echo cache klasorlerini temizler.
echo Windows TEMP klasorlerine dokunmaz.
echo.

:: Guncel ve yaygin NVIDIA cache konumlari
call :CleanDirectory "%LOCALAPPDATA%\NVIDIA\DXCache" "NVIDIA DXCache"
call :CleanDirectory "%LOCALAPPDATA%\NVIDIA\GLCache" "NVIDIA GLCache"

:: Surucu surumune bagli yeni/alternatif NVIDIA konumlari
call :CleanDirectory "%LOCALAPPDATA%\NVIDIA\PerDriverVersion\DXCache" "NVIDIA PerDriverVersion DXCache - Local"
call :CleanDirectory "%USERPROFILE%\AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache" "NVIDIA PerDriverVersion DXCache - LocalLow"

:: NVIDIA CUDA / Compute cache
call :CleanDirectory "%APPDATA%\NVIDIA\ComputeCache" "NVIDIA ComputeCache"
call :CleanDirectory "%LOCALAPPDATA%\NVIDIA\ComputeCache" "NVIDIA ComputeCache - Local"

:: Windows DirectX cache
call :CleanDirectory "%LOCALAPPDATA%\D3DSCache" "Windows DirectX D3DSCache"

:: Eski NVIDIA suruculerinde bulunabilecek cache konumlari
call :CleanDirectory "%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache" "NVIDIA NV_Cache - Kullanici"
call :CleanDirectory "%ProgramData%\NVIDIA Corporation\NV_Cache" "NVIDIA NV_Cache - Sistem"

echo.
echo ==========================================================
echo TEMIZLIK SONUCU
echo ==========================================================
echo Tamamen temizlenen klasor : %CLEANED%
echo Kismen temizlenen klasor  : %PARTIAL%
echo Bulunamayan klasor        : %MISSING%
echo ==========================================================
echo.

if %PARTIAL% GTR 0 (
    echo Bazi dosyalar veya klasorler kullanimda oldugu icin
    echo silinemedi.
    echo.
    echo Oyunlari, Steam'i ve NVIDIA uygulamalarini kapatip
    echo dosyayi yonetici olarak yeniden calistirabilirsiniz.
) else (
    echo Bulunan tum NVIDIA ve DirectX cache klasorlerinin
    echo ici tamamen temizlendi.
)

echo.
echo Ana cache klasorleri korundu.
echo Dosyalar ve gizli klasorler dahil tum alt klasorler silindi.
echo.
echo ONEMLI:
echo Shader cache temizlendikten sonra oyunlar shaderlari yeniden
echo derleyecegi icin ilk oyunlarda gecici FPS drop ve takilmalar
echo gorulmesi normaldir.
echo ==========================================================
pause
exit /b 0


:CleanDirectory
set "TARGET=%~1"
set "CACHE_NAME=%~2"

echo ----------------------------------------------------------
echo [%CACHE_NAME%]
echo Konum: "%TARGET%"

if not defined TARGET (
    echo Sonuc: Gecersiz hedef.
    set /a PARTIAL+=1
    exit /b 1
)

if not exist "%TARGET%\" (
    echo Sonuc: Klasor bulunamadi, atlandi.
    set /a MISSING+=1
    exit /b 0
)

:: Salt okunur, gizli ve sistem ozelliklerini kaldir
attrib -r -h -s "%TARGET%\*" /s /d >nul 2>&1

:: Ana klasor icindeki tum dosyalari sil
del /f /s /q /a "%TARGET%\*" >nul 2>&1

:: Gizli ve sistem klasorleri dahil tum alt klasorleri sil
for /f "delims=" %%D in ('dir /a:d /b "%TARGET%" 2^>nul') do (
    rd /s /q "%TARGET%\%%D" >nul 2>&1
)

:: Klasorun gercekten bos olup olmadigini kontrol et
dir /a /b "%TARGET%" 2>nul | findstr /r "." >nul

if errorlevel 1 (
    echo Sonuc: Tamamen temizlendi.
    set /a CLEANED+=1
) else (
    echo Sonuc: Kismen temizlendi.
    echo Bazi kilitli veya kullanimda olan ogeler kaldi.
    set /a PARTIAL+=1
)

exit /b 0