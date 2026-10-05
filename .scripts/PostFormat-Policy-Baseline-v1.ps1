#requires -Version 5.1
<#
.SYNOPSIS
    Post-format update/security/file-intervention policy baseline.

.DESCRIPTION
    Dedicated gaming-PC policy layer.

    UPDATE MODEL
      - Automatic Windows OS/security/feature updating is disabled.
      - Windows Update scan/download/install UX is disabled for the user.
      - Windows Update services / BITS / UsoSvc / WaaSMedic / CBS / TrustedInstaller
        are NOT disabled or deleted.
      - Windows Update driver exclusion is REMOVED intentionally.
      - A separate read-only Windows Update Agent task searches ONLY Type='Driver'
        once every other week while the PC is idle.
      - The driver-only task never downloads or installs a driver.
      - Store automatic app updates are disabled.
      - Delivery Optimization peer-to-peer is disabled; normal Microsoft HTTP/CDN
        plumbing remains intact.

    SECURITY / FILE-INTERVENTION MODEL
      - Defender/Security Center services are NOT disabled or deleted.
      - Real-time monitoring, behavior monitoring, downloaded-file scanning,
        script scanning, Block at First Sight, PUA, Network Protection and
        Controlled Folder Access are requested OFF through supported policy/
        Defender preference surfaces.
      - Routine automatic threat remediation is disabled so detected items are not
        automatically acted upon.
      - SmartScreen in the Windows shell is disabled.
      - Defender automatic scheduled scans are disabled through preference, not by
        deleting Defender scheduled tasks.
      - Cloud MAPS reporting and automatic sample submission are disabled.
      - Quarantine automatic purge is set to never.
      - Storage Sense is blocked so Windows does not automatically purge Downloads,
        Recycle Bin or temporary files through Storage Sense.

    TAMPER PROTECTION
      This script deliberately does NOT attempt to bypass or forcibly disable
      Tamper Protection. If Tamper Protection prevents the requested Defender
      state, the script reports PARTIAL and exits with code 10.

.PARAMETER Mode
    Apply (default) or Audit.

.EXIT CODES
    0  = desired baseline verified
    10 = Defender portion blocked/partial because Tamper Protection is active
    11 = Defender effective state differs for another reason
    20 = scheduled driver-scan task could not be configured/verified
    1  = other fatal error
#>

[CmdletBinding()]
param(
    [ValidateSet('Apply','Audit')]
    [string]$Mode = 'Apply'
)

# ---------------------------------------------------------------------------
# Self-elevate safely and propagate the real exit code.
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

    $argumentLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath,$Mode

    $child = Start-Process `
        -FilePath $powershellExe `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ErrorAction Stop

    exit $child.ExitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.2'
$ScriptRoot = Split-Path -Parent $PSCommandPath

$Root = Join-Path $env:ProgramData 'GamingPolicyBaseline'
$LogRoot = Join-Path $Root 'Logs'
$StableScanScript = Join-Path $Root 'WU-Driver-Scan-v1.ps1'
$SourceScanScript = Join-Path $ScriptRoot 'WU-Driver-Scan-v1.ps1'
$LogFile = Join-Path $LogRoot ("policy-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

$TaskPath = '\GamingBaseline\'
$TaskName = 'DriverUpdateScan'
$TaskDescription = 'Gaming baseline read-only Windows Update driver scan every 2 weeks - v1'

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Start-Transcript -Path $LogFile -Force | Out-Null

$script:Failures = 0
$script:Warnings = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)

    Write-Host ''
    Write-Host '============================================================'
    Write-Host (" {0}" -f $Text) -ForegroundColor Cyan
    Write-Host '============================================================'
}

function Write-Result {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$State,
        [string]$Detail = ''
    )

    $line = '{0,-34} : {1}' -f $Name,$State
    if ($Detail) {
        $line += (' | {0}' -f $Detail)
    }

    if ($State -match '^(OK|OFF|ON|ABSENT|READY|STOCK/PRESENT)$') {
        Write-Host $line -ForegroundColor Green
    }
    elseif ($State -match 'WARN|PARTIAL|MISMATCH|BLOCKED') {
        Write-Host $line -ForegroundColor Yellow
    }
    else {
        Write-Host $line
    }
}

function Ensure-RegistryDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    if ($Mode -eq 'Audit') {
        return
    }

    # Use the native 64-bit registry tool for machine policy DWORD writes.
    # REV14.5 showed this Windows build retaining the same documented values
    # reliably when written through reg.exe in the low-risk/AppPrivacy layers,
    # while two PowerShell-provider writes disappeared before verification.
    $nativePath = $Path -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'

    & reg.exe ADD $nativePath /v $Name /t REG_DWORD /d $Value /f *> $null

    if ($LASTEXITCODE -ne 0) {
        throw ("reg.exe failed writing {0}\\{1} (exit {2})" -f $nativePath,$Name,$LASTEXITCODE)
    }
}

function Remove-RegistryValueIfPresent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Mode -eq 'Audit') {
        return
    }

    if (Test-Path -LiteralPath $Path) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Get-RegistryDwordState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }

    try {
        $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return [pscustomobject]@{
            Exists = $true
            Value  = [int]$p.$Name
        }
    }
    catch {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }
}

function Test-RegistryDword {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Expected
    )

    $s = Get-RegistryDwordState -Path $Path -Name $Name
    $ok = ($s.Exists -and $s.Value -eq $Expected)

    Write-Result `
        -Name $Label `
        -State $(if ($ok) { 'OK' } else { 'MISMATCH' }) `
        -Detail $(if ($s.Exists) { "current=$($s.Value), expected=$Expected" } else { "missing, expected=$Expected" })

    return $ok
}

function Ensure-TaskFolder {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $rootFolder = $service.GetFolder('\')

    try {
        $null = $rootFolder.GetFolder($TaskPath)
    }
    catch {
        $null = $rootFolder.CreateFolder($TaskPath.Trim('\'))
    }
}

function Get-DriverScanTask {
    return Get-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -ErrorAction SilentlyContinue
}

function Install-DriverScanTask {
    if (-not (Test-Path -LiteralPath $SourceScanScript)) {
        throw "Driver-only scan script is missing beside this policy script: $SourceScanScript"
    }

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    Copy-Item -LiteralPath $SourceScanScript -Destination $StableScanScript -Force

    $existing = Get-DriverScanTask

    $actionExpected = (
        '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $StableScanScript
    )

    $existingGood = $false

    if ($null -ne $existing) {
        $action = @($existing.Actions) | Select-Object -First 1

        $existingGood = (
            [string]$existing.Description -eq $TaskDescription -and
            [string]$action.Execute -eq "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -and
            [string]$action.Arguments -eq $actionExpected
        )

        if ($existingGood) {
            if ([string]$existing.State -eq 'Disabled') {
                Enable-ScheduledTask -InputObject $existing -ErrorAction Stop | Out-Null
            }

            Write-Host '[UNCHANGED] Existing 2-week driver-only scan task kept; schedule was not reset.'
            return
        }
    }

    Ensure-TaskFolder

    $firstRun = (Get-Date).Date.AddDays(14).AddHours(15)
    $day = [DayOfWeek]$firstRun.DayOfWeek

    $action = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument $actionExpected

    $trigger = New-ScheduledTaskTrigger `
        -Weekly `
        -WeeksInterval 2 `
        -DaysOfWeek $day `
        -At $firstRun `
        -RandomDelay (New-TimeSpan -Minutes 30)

    $settings = New-ScheduledTaskSettingsSet `
        -RunOnlyIfIdle `
        -IdleDuration (New-TimeSpan -Minutes 5) `
        -IdleWaitTimeout (New-TimeSpan -Hours 12) `
        -RunOnlyIfNetworkAvailable `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
        -MultipleInstances IgnoreNew

    $principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $task = New-ScheduledTask `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $TaskDescription

    Register-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -InputObject $task `
        -Force | Out-Null

    Write-Host ("[APPLIED] Driver-only Windows Update scan task registered. First run no earlier than: {0}" -f $firstRun)
}

function Test-DriverScanTask {
    $task = Get-DriverScanTask

    if ($null -eq $task) {
        Write-Result -Name 'Biweekly WU driver scan task' -State 'MISMATCH' -Detail 'task missing'
        return $false
    }

    $action = @($task.Actions) | Select-Object -First 1
    $actionOk = (
        [string]$action.Execute -eq "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -and
        [string]$action.Arguments -like "*$StableScanScript*"
    )

    $info = Get-ScheduledTaskInfo `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -ErrorAction SilentlyContinue

    $ok = (
        [string]$task.State -ne 'Disabled' -and
        [string]$task.Description -eq $TaskDescription -and
        $actionOk -and
        (Test-Path -LiteralPath $StableScanScript)
    )

    $next = if ($null -ne $info -and $info.NextRunTime -gt [datetime]'2000-01-01') {
        $info.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    else {
        'not resolved yet'
    }

    Write-Result `
        -Name 'Biweekly WU driver scan task' `
        -State $(if ($ok) { 'READY' } else { 'MISMATCH' }) `
        -Detail ("state={0}; next={1}" -f $task.State,$next)

    return $ok
}

function Set-DefenderMinimalIntervention {
    $cmd = Get-Command Set-MpPreference -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw 'Set-MpPreference is unavailable.'
    }

    # Direct preferences: supported Defender surface.
    # Tamper Protection may block these; effective state is verified afterward.
    Set-MpPreference `
        -DisableRealtimeMonitoring $true `
        -DisableBehaviorMonitoring $true `
        -DisableIOAVProtection $true `
        -DisableScriptScanning $true `
        -DisableBlockAtFirstSeen $true `
        -DisableCatchupQuickScan $true `
        -DisableCatchupFullScan $true `
        -PUAProtection Disabled `
        -EnableControlledFolderAccess Disabled `
        -EnableNetworkProtection Disabled `
        -MAPSReporting 0 `
        -SubmitSamplesConsent 2 `
        -ScanScheduleDay Never `
        -QuarantinePurgeItemsAfterDelay 0 `
        -SevereThreatDefaultAction UserDefined `
        -HighThreatDefaultAction UserDefined `
        -ModerateThreatDefaultAction UserDefined `
        -LowThreatDefaultAction UserDefined `
        -UnknownThreatDefaultAction UserDefined `
        -ErrorAction Stop
}

function Get-DefenderEffectiveState {
    $pref = Get-MpPreference -ErrorAction Stop
    $status = Get-MpComputerStatus -ErrorAction Stop

    $tamper = $false
    try { $tamper = [bool]$status.IsTamperProtected } catch {}

    function Read-BoolProperty {
        param($Object,[string]$Name,[bool]$Expected)
        try {
            return ([bool]$Object.$Name -eq $Expected)
        }
        catch {
            return $false
        }
    }

    function Read-IntProperty {
        param($Object,[string]$Name,[int64]$Expected)
        try {
            return ([int64]$Object.$Name -eq $Expected)
        }
        catch {
            return $false
        }
    }

    $checks = [ordered]@{
        DisableRealtimeMonitoring = (Read-BoolProperty $pref 'DisableRealtimeMonitoring' $true)
        DisableBehaviorMonitoring = (Read-BoolProperty $pref 'DisableBehaviorMonitoring' $true)
        DisableIOAVProtection     = (Read-BoolProperty $pref 'DisableIOAVProtection' $true)
        DisableScriptScanning     = (Read-BoolProperty $pref 'DisableScriptScanning' $true)
        DisableBlockAtFirstSeen   = (Read-BoolProperty $pref 'DisableBlockAtFirstSeen' $true)
        PUAProtectionOff          = (Read-IntProperty  $pref 'PUAProtection' 0)
        ControlledFolderAccessOff = (Read-IntProperty  $pref 'EnableControlledFolderAccess' 0)
        NetworkProtectionOff      = (Read-IntProperty  $pref 'EnableNetworkProtection' 0)
        MAPSOff                   = (Read-IntProperty  $pref 'MAPSReporting' 0)
        SampleSubmissionNever     = (Read-IntProperty  $pref 'SubmitSamplesConsent' 2)
        ScheduledScanNever        = (Read-IntProperty  $pref 'ScanScheduleDay' 8)
        QuarantineNeverPurged     = (Read-IntProperty  $pref 'QuarantinePurgeItemsAfterDelay' 0)
        SevereThreatUserDefined   = (Read-IntProperty  $pref 'SevereThreatDefaultAction' 8)
        HighThreatUserDefined     = (Read-IntProperty  $pref 'HighThreatDefaultAction' 8)
        ModerateThreatUserDefined = (Read-IntProperty  $pref 'ModerateThreatDefaultAction' 8)
        LowThreatUserDefined      = (Read-IntProperty  $pref 'LowThreatDefaultAction' 8)
        RealtimeEffectiveOff      = (Read-BoolProperty $status 'RealTimeProtectionEnabled' $false)
        BehaviorEffectiveOff      = (Read-BoolProperty $status 'BehaviorMonitorEnabled' $false)
        IOAVEffectiveOff          = (Read-BoolProperty $status 'IoavProtectionEnabled' $false)
    }

    $allOk = $true
    foreach ($entry in $checks.GetEnumerator()) {
        if (-not [bool]$entry.Value) {
            $allOk = $false
        }
    }

    return [pscustomobject]@{
        TamperProtected = $tamper
        AllOk           = $allOk
        Checks          = $checks
        Status          = $status
        Preference      = $pref
    }
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (" POST-FORMAT POLICY BASELINE v{0}" -f $ScriptVersion)
    Write-Host '============================================================'
    Write-Host ("Mode : {0}" -f $Mode)
    Write-Host ("Log  : {0}" -f $LogFile)

    $WUPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $WUAUPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

    if ($Mode -eq 'Apply') {
        Write-Section '1/4 UPDATE / SERVICING POLICY'

        # Freeze automatic OS/security/feature updating while preserving all
        # Windows Update / servicing services and components.
        Ensure-RegistryDword -Path $WUAUPath -Name 'NoAutoUpdate' -Value 1

        # Remove user-facing scan/download/install access. Microsoft documents
        # that background update activity continues according to configured
        # policy; our dedicated WUA scan below explicitly requests Driver only.
        Ensure-RegistryDword -Path $WUPath -Name 'SetDisableUXWUAccess' -Value 1

        # Intentional: driver updates remain eligible in the Windows Update
        # catalog. Old baseline revisions set this to 1; remove that policy.
        Remove-RegistryValueIfPresent `
            -Path $WUPath `
            -Name 'ExcludeWUDriversInQualityUpdate'

        # Keep Delivery Optimization service/topology stock, but no peer-to-peer.
        Ensure-RegistryDword `
            -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' `
            -Name 'DODownloadMode' `
            -Value 0

        # No automatic Microsoft Store application updates.
        Ensure-RegistryDword `
            -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' `
            -Name 'AutoDownload' `
            -Value 2

        Write-Host '[APPLIED] Windows Update OS/security/feature auto-update frozen; WU services untouched.'
        Write-Host '[APPLIED] Windows Update driver exclusion removed intentionally.'

        Write-Section '2/4 SECURITY / FILE-INTERVENTION POLICY'

        # SmartScreen is a normal Windows policy and is kept separate from
        # Defender's tamper-protected preference surface.
        Ensure-RegistryDword `
            -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
            -Name 'EnableSmartScreen' `
            -Value 0

        $tamperBeforeApply = $false
        try {
            $defenderStatusBefore = Get-MpComputerStatus -ErrorAction Stop
            $tamperBeforeApply = [bool]$defenderStatusBefore.IsTamperProtected
        }
        catch {
            $script:Warnings++
            Write-Warning ("Could not read Tamper Protection before Defender apply: {0}" -f $_.Exception.Message)
        }

        if ($tamperBeforeApply) {
            $script:Warnings++
            Write-Warning 'Tamper Protection is ON. Defender preference writes are skipped; no bypass is attempted.'
        }
        else {
            try {
                Set-DefenderMinimalIntervention
                Write-Host '[APPLIED] Defender minimal-intervention preferences requested.'
            }
            catch {
                $script:Warnings++
                Write-Warning ("Defender preference write returned: {0}" -f $_.Exception.Message)
            }
        }

        Write-Section '3/4 AUTOMATIC FILE CLEANUP'

        # Storage Sense blocked globally. Extra subordinate values are also set
        # defensively so Downloads/Recycle Bin/temp cleanup remains off even if
        # global policy is later relaxed.
        $StoragePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
        Ensure-RegistryDword -Path $StoragePath -Name 'AllowStorageSenseGlobal' -Value 0
        Ensure-RegistryDword -Path $StoragePath -Name 'AllowStorageSenseTemporaryFilesCleanup' -Value 0
        Ensure-RegistryDword -Path $StoragePath -Name 'ConfigStorageSenseDownloadsCleanupThreshold' -Value 0
        Ensure-RegistryDword -Path $StoragePath -Name 'ConfigStorageSenseRecycleBinCleanupThreshold' -Value 0

        Write-Host '[APPLIED] Storage Sense automatic cleanup blocked.'

        Write-Section '4/4 BIWEEKLY DRIVER-ONLY WINDOWS UPDATE SCAN'
        Install-DriverScanTask
    }

    # -----------------------------------------------------------------------
    # Verification / audit
    # -----------------------------------------------------------------------
    Write-Section 'FINAL EFFECTIVE STATE'

    $verificationOk = $true

    $verificationOk = (Test-RegistryDword `
        -Label 'Windows automatic updates' `
        -Path $WUAUPath `
        -Name 'NoAutoUpdate' `
        -Expected 1) -and $verificationOk

    $verificationOk = (Test-RegistryDword `
        -Label 'Windows Update user UX' `
        -Path $WUPath `
        -Name 'SetDisableUXWUAccess' `
        -Expected 1) -and $verificationOk

    $driverExclusion = Get-RegistryDwordState `
        -Path $WUPath `
        -Name 'ExcludeWUDriversInQualityUpdate'

    $driverChannelOk = (-not $driverExclusion.Exists)
    Write-Result `
        -Name 'WU driver exclusion policy' `
        -State $(if ($driverChannelOk) { 'ABSENT' } else { 'MISMATCH' }) `
        -Detail $(if ($driverChannelOk) { 'driver catalog remains eligible' } else { "current=$($driverExclusion.Value); must be absent" })

    $verificationOk = $driverChannelOk -and $verificationOk

    $verificationOk = (Test-RegistryDword `
        -Label 'Delivery Optimization P2P' `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' `
        -Name 'DODownloadMode' `
        -Expected 0) -and $verificationOk

    $verificationOk = (Test-RegistryDword `
        -Label 'Store automatic app updates' `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' `
        -Name 'AutoDownload' `
        -Expected 2) -and $verificationOk

    $verificationOk = (Test-RegistryDword `
        -Label 'Windows SmartScreen shell' `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Name 'EnableSmartScreen' `
        -Expected 0) -and $verificationOk

    $verificationOk = (Test-RegistryDword `
        -Label 'Storage Sense' `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' `
        -Name 'AllowStorageSenseGlobal' `
        -Expected 0) -and $verificationOk

    $taskOk = Test-DriverScanTask
    $verificationOk = $taskOk -and $verificationOk

    $defender = $null
    $defenderStateKnown = $true

    try {
        $defender = Get-DefenderEffectiveState

        Write-Result `
            -Name 'Tamper Protection' `
            -State $(if ($defender.TamperProtected) { 'ON' } else { 'OFF' })

        foreach ($entry in $defender.Checks.GetEnumerator()) {
            Write-Result `
                -Name ("Defender {0}" -f $entry.Key) `
                -State $(if ([bool]$entry.Value) { 'OK' } else { 'MISMATCH' })
        }

        if (-not $defender.AllOk) {
            $verificationOk = $false
        }
    }
    catch {
        $defenderStateKnown = $false
        $verificationOk = $false
        Write-Warning ("Could not query Defender effective state: {0}" -f $_.Exception.Message)
    }

    Write-Host ''
    Write-Host 'Service topology report (REPORT ONLY; not modified):'

    foreach ($name in @(
        'wuauserv',
        'BITS',
        'UsoSvc',
        'WaaSMedicSvc',
        'TrustedInstaller',
        'WinDefend',
        'WdNisSvc',
        'SecurityHealthService'
    )) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue

        if ($null -eq $svc) {
            Write-Host ("  {0,-24} : not present" -f $name)
            continue
        }

        $startMode = ''
        try {
            $cim = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction Stop
            $startMode = [string]$cim.StartMode
        }
        catch {
            $startMode = 'unknown'
        }

        Write-Host ("  {0,-24} : State={1}; StartMode={2}" -f $name,$svc.Status,$startMode)
    }

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' POLICY BASELINE REPORT'
    Write-Host '============================================================'
    Write-Host ("Mode               : {0}" -f $Mode)
    Write-Host ("Registry/task state: {0}" -f $(if ($verificationOk) { 'OK' } else { 'CHECK OUTPUT ABOVE' }))
    Write-Host ("Warnings           : {0}" -f $script:Warnings)
    Write-Host ("Log                : {0}" -f $LogFile)
    Write-Host ("Driver scan reports: {0}" -f (Join-Path $env:ProgramData 'GamingPolicyBaseline\WU-Driver-Scan'))

    if ($null -ne $defender -and -not $defender.AllOk -and $defender.TamperProtected) {
        Write-Host ''
        Write-Warning 'PARTIAL: Tamper Protection is ON and the requested Defender state is not fully effective.'
        Write-Warning 'This script does not bypass Tamper Protection. Turn it off manually if you want this security profile, then rerun.'
        exit 10
    }

    if (-not $defenderStateKnown -or ($null -ne $defender -and -not $defender.AllOk)) {
        exit 11
    }

    if (-not $taskOk) {
        exit 20
    }

    if (-not $verificationOk) {
        exit 1
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
