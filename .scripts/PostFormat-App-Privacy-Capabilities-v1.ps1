#requires -Version 5.1
<#
.SYNOPSIS
    App-privacy capability baseline for the dedicated gaming PC.

.DESCRIPTION
    Uses the documented Windows App Privacy policy surface only.

    Force-denied for Windows apps:
      - Camera
      - Trusted / other devices
      - Diagnostic information about other apps
      - Programmatic screenshots / graphics capture
      - Graphics capture without the normal border

    Intentionally NOT changed:
      - Microphone
      - Documents / Downloads / Pictures / Videos / Music
      - File system
      - Automatic file downloads
      - Local clipboard / Clipboard History
      - Win32 desktop application ACLs
      - Services, drivers, scheduler, network stack, HID, GPU scheduling

    Policy values:
      0 = User in control
      1 = Force Allow
      2 = Force Deny

    This layer is a capability-policy baseline, not a latency tweak.

.PARAMETER Mode
    Apply (default) or Audit.
#>

[CmdletBinding()]
param(
    [ValidateSet('Apply','Audit')]
    [string]$Mode = 'Apply'
)

function Test-IsAdministratorToken {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$needsDesktopPS = ($PSVersionTable.PSEdition -ne 'Desktop')
$needs64Bit = (-not [Environment]::Is64BitProcess)
$needsElevation = (-not (Test-IsAdministratorToken))

if ($needsDesktopPS -or $needs64Bit -or $needsElevation) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Launch this script from its .ps1 file.'
    }

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $powershellExe = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath,$Mode

    $child = Start-Process `
        -FilePath $powershellExe `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ErrorAction Stop

    exit $child.ExitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.1'
$PolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
$LogRoot = Join-Path $env:ProgramData 'GamingAppPrivacyBaseline\Logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile = Join-Path $LogRoot ("app-privacy-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

Start-Transcript -Path $LogFile -Force | Out-Null

function Ensure-Dword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    if ($Mode -ne 'Apply') {
        return
    }

    $nativePath = $Path -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'

    & reg.exe ADD $nativePath /v $Name /t REG_DWORD /d $Value /f *> $null
    if ($LASTEXITCODE -ne 0) {
        throw ("reg.exe failed writing {0}\\{1} (exit {2})" -f $nativePath,$Name,$LASTEXITCODE)
    }
}
function Get-Dword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return [int]$item.$Name
    }
    catch {
        return $null
    }
}

function Verify-Dword {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Expected
    )

    $actual = Get-Dword -Path $PolicyPath -Name $Name
    $ok = ($null -ne $actual -and $actual -eq $Expected)

    if ($ok) {
        Write-Host ("[OK]   {0} = {1}" -f $Label,$actual) -ForegroundColor Green
    }
    else {
        $shown = if ($null -eq $actual) { '<missing>' } else { [string]$actual }
        Write-Host ("[MISS] {0} = {1} (expected {2})" -f $Label,$shown,$Expected) -ForegroundColor Yellow
    }

    return $ok
}

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (" APP PRIVACY CAPABILITY BASELINE v{0}" -f $ScriptVersion)
    Write-Host '============================================================'
    Write-Host ("Mode : {0}" -f $Mode)
    Write-Host ("Log  : {0}" -f $LogFile)
    Write-Host ''

    # Microsoft AppPrivacy.admx default-policy values.
    # 2 = Force Deny.

    Ensure-Dword -Path $PolicyPath -Name 'LetAppsAccessCamera' -Value 2
    Ensure-Dword -Path $PolicyPath -Name 'LetAppsAccessTrustedDevices' -Value 2
    Ensure-Dword -Path $PolicyPath -Name 'LetAppsGetDiagnosticInfo' -Value 2
    Ensure-Dword -Path $PolicyPath -Name 'LetAppsAccessGraphicsCaptureProgrammatic' -Value 2
    Ensure-Dword -Path $PolicyPath -Name 'LetAppsAccessGraphicsCaptureWithoutBorder' -Value 2

    Write-Host 'Microphone policy is intentionally NOT written; it remains Windows/user controlled.'
    Write-Host 'File/folder capability policies are intentionally NOT written.'
    Write-Host ''

    Write-Host '--- EFFECTIVE POLICY STATE ---'

    $checks = @(
        (Verify-Dword -Label 'Windows apps camera access' `
            -Name 'LetAppsAccessCamera' -Expected 2),

        (Verify-Dword -Label 'Windows apps trusted-device access' `
            -Name 'LetAppsAccessTrustedDevices' -Expected 2),

        (Verify-Dword -Label 'Windows apps app-diagnostics access' `
            -Name 'LetAppsGetDiagnosticInfo' -Expected 2),

        (Verify-Dword -Label 'Windows apps programmatic graphics capture' `
            -Name 'LetAppsAccessGraphicsCaptureProgrammatic' -Expected 2),

        (Verify-Dword -Label 'Windows apps borderless graphics capture' `
            -Name 'LetAppsAccessGraphicsCaptureWithoutBorder' -Expected 2)
    )

    $microphone = Get-Dword -Path $PolicyPath -Name 'LetAppsAccessMicrophone'
    if ($null -eq $microphone) {
        Write-Host '[OK]   Microphone global AppPrivacy policy = NOT CONFIGURED / user control' -ForegroundColor Green
    }
    else {
        Write-Warning ("Microphone global AppPrivacy policy already exists with value {0}. This script did not modify it." -f $microphone)
    }

    $missingCount = @($checks | Where-Object { -not $_ }).Count
    $allOk = ($missingCount -eq 0)

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' FINAL REPORT'
    Write-Host '============================================================'
    Write-Host ("Result : {0}" -f $(if ($allOk) { 'OK' } else { 'CHECK OUTPUT ABOVE' }))
    Write-Host ("Log    : {0}" -f $LogFile)

    if ($Mode -eq 'Audit') {
        Write-Host 'No registry values were changed.'
    }
    else {
        Write-Host 'Restart affected packaged apps (or sign out/reboot) before judging UI behavior.'
    }

    if (-not $allOk) {
        Write-Warning ("{0} App Privacy policy value(s) were not retained by this Windows build." -f $missingCount)
        exit 10
    }

    exit 0
}
catch {
    Write-Host ''
    Write-Host ("FATAL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Log: {0}" -f $LogFile)
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
