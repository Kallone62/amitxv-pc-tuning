#requires -Version 5.1
<#
.SYNOPSIS
    Low-risk post-format background-feature baseline for the dedicated gaming PC.

.DESCRIPTION
    Applies only the additional Windows features we intentionally accepted after
    review, using documented registry-policy paths:

      1) Offline Files / CSC disabled
      2) Automatic implicit typing/inking learning disabled for the gaming user
      3) Cross-device experiences / Continue experiences disabled
      4) Cross-device clipboard synchronization disabled
      5) Offline Maps automatic data update disabled

    This script intentionally does NOT:
      - disable or delete services
      - remove Windows components
      - disable Search, SysMain, WER, PCA, NCSI or servicing
      - disable local clipboard functionality
      - disable local clipboard history
      - disable device discovery / Win+K / projection
      - disable font providers
      - disable recent-document history
      - apply undocumented registry mirrors

    Some accepted settings such as Online Tips and Cloud/WNS notifications are
    already owned by CS2-GamingOnly-Pro-v1.0.8.ps1 and are therefore not
    duplicated here.

    Offline Files and EnableCDP require a reboot before their effective Windows
    behavior is fully refreshed.

.PARAMETER Mode
    Apply (default) or Audit.
#>

[CmdletBinding()]
param(
    [ValidateSet('Apply','Audit')]
    [string]$Mode = 'Apply'
)

# ---------------------------------------------------------------------------
# Relaunch in elevated 64-bit Windows PowerShell 5.1 and propagate exit code.
# ---------------------------------------------------------------------------

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
$LogRoot = Join-Path $env:ProgramData 'GamingLowRiskBackground\Logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

$LogFile = Join-Path $LogRoot ("low-risk-background-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Assert-InteractiveTargetUser {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = [string]$identity.User.Value
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId

    $explorer = @(
        Get-CimInstance Win32_Process `
            -Filter "Name='explorer.exe'" `
            -ErrorAction SilentlyContinue |
        Where-Object { [int]$_.SessionId -eq $sessionId }
    ) | Select-Object -First 1

    if ($null -eq $explorer) {
        throw 'No Explorer shell was found in this session. Run from the gaming account.'
    }

    $owner = Invoke-CimMethod `
        -InputObject $explorer `
        -MethodName GetOwnerSid `
        -ErrorAction Stop

    $explorerSid = [string]$owner.Sid

    if ([string]::IsNullOrWhiteSpace($explorerSid)) {
        throw 'Could not resolve Explorer owner SID.'
    }

    if (-not [string]::Equals($currentSid,$explorerSid,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'The elevated token belongs to a different user than the interactive desktop.'
    }

    Write-Host ("Interactive user : {0}" -f $identity.Name)
}

function Ensure-Dword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    if ($Mode -ne 'Apply') {
        return
    }

    # Microsoft documents these settings as direct REG_DWORD values. Use
    # reg.exe for the write, then verify through the registry provider.
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
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Expected
    )

    $actual = Get-Dword -Path $Path -Name $Name
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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (" LOW-RISK BACKGROUND FEATURES v{0}" -f $ScriptVersion)
    Write-Host '============================================================'
    Write-Host ("Mode : {0}" -f $Mode)
    Write-Host ("Log  : {0}" -f $LogFile)
    Write-Host ''

    Assert-InteractiveTargetUser

    # 1) Offline Files / CSC
    # Group Policy:
    # Computer Configuration > Network > Offline Files >
    # Allow or Disallow use of the Offline Files feature
    # 0 = disabled
    $OfflineFilesPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache'
    Ensure-Dword -Path $OfflineFilesPath -Name 'Enabled' -Value 0

    # 2) Automatic implicit typing/inking learning
    # Microsoft documents these user-scoped values directly.
    $InputPath = 'HKCU:\Software\Microsoft\InputPersonalization'
    Ensure-Dword -Path $InputPath -Name 'RestrictImplicitTextCollection' -Value 1
    Ensure-Dword -Path $InputPath -Name 'RestrictImplicitInkCollection' -Value 1

    # 3) Cross-device experiences / Continue experiences
    # Computer Configuration > System > Group Policy >
    # Continue experiences on this device
    # 0 = disabled
    $SystemPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Ensure-Dword -Path $SystemPolicyPath -Name 'EnableCdp' -Value 0

    # 4) Cross-device clipboard synchronization
    # This does NOT disable normal local copy/paste or local clipboard history.
    # 0 = cross-device synchronization not allowed
    Ensure-Dword -Path $SystemPolicyPath -Name 'AllowCrossDeviceClipboard' -Value 0

    # 5) Offline Maps automatic download/update
    # Computer Configuration > Windows Components > Maps >
    # Turn off Automatic Download and Update of Map Data
    # CSP/registry value 0 = auto-update forced off.
    $MapsPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps'
    Ensure-Dword -Path $MapsPath -Name 'AutoDownloadAndUpdateMapData' -Value 0

    Write-Host ''
    Write-Host '--- EFFECTIVE STATE ---'

    $checks = @(
        (Verify-Dword `
            -Label 'Offline Files enabled' `
            -Path $OfflineFilesPath `
            -Name 'Enabled' `
            -Expected 0),

        (Verify-Dword `
            -Label 'Implicit text collection restricted' `
            -Path $InputPath `
            -Name 'RestrictImplicitTextCollection' `
            -Expected 1),

        (Verify-Dword `
            -Label 'Implicit ink collection restricted' `
            -Path $InputPath `
            -Name 'RestrictImplicitInkCollection' `
            -Expected 1),

        (Verify-Dword `
            -Label 'Cross-device experiences' `
            -Path $SystemPolicyPath `
            -Name 'EnableCdp' `
            -Expected 0),

        (Verify-Dword `
            -Label 'Cross-device clipboard sync' `
            -Path $SystemPolicyPath `
            -Name 'AllowCrossDeviceClipboard' `
            -Expected 0),

        (Verify-Dword `
            -Label 'Offline Maps automatic update' `
            -Path $MapsPath `
            -Name 'AutoDownloadAndUpdateMapData' `
            -Expected 0)
    )

    $missingCount = @($checks | Where-Object { -not $_ }).Count
    $allOk = ($missingCount -eq 0)

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' FINAL REPORT'
    Write-Host '============================================================'
    Write-Host ("Result             : {0}" -f $(if ($allOk) { 'OK' } else { 'CHECK OUTPUT ABOVE' }))
    Write-Host ("Reboot recommended : {0}" -f $(if ($Mode -eq 'Apply') { 'YES' } else { 'N/A - AUDIT ONLY' }))
    Write-Host ("Log                : {0}" -f $LogFile)

    if ($Mode -eq 'Audit') {
        Write-Host 'No registry values were changed.'
    }
    else {
        Write-Host 'Reboot refreshes Offline Files and cross-device policy behavior.'
    }

    if (-not $allOk) {
        Write-Warning ("{0} optional low-risk policy value(s) were not retained by this Windows build." -f $missingCount)
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
