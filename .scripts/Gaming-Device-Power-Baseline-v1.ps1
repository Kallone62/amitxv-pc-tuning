#requires -Version 5.1
<#
.SYNOPSIS
    Exact gaming-device power baseline for this hardware profile.

.DESCRIPTION
    Applies power-management changes only to the device functions that were
    verified by the read-only audit on this PC:

      Logitech LIGHTSPEED mouse function
        USB\VID_046D&PID_C54D&MI_00\*

      Wooting 80HE keyboard function
        USB\VID_31E3&PID_1402&MI_01\*

    Intel I226-V power state is only verified here. The comprehensive I226
    baseline that runs earlier owns the supported NetAdapter PM lockdown and
    the master AllowComputerToTurnOffDevice state.

    Everything else remains stock:
      - USB Root Hubs
      - xHCI controllers
      - unrelated HID devices
      - Wooting non-keyboard interfaces
      - Logitech receiver non-mouse interfaces
      - Corsair HS80
      - ARP/NS offload
      - Wake-on-Magic-Packet / Wake-on-Pattern
      - interrupt moderation / RSS / queues / affinity

    The script is idempotent and verifies the effective state after writes.

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

$ScriptVersion = '1.4'
$LogRoot = Join-Path $env:ProgramData 'GamingDeviceBaseline\PowerBaseline'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile = Join-Path $LogRoot ("device-power-baseline-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

Start-Transcript -Path $LogFile -Force | Out-Null

# Exact audited USB function allowlist.
$Targets = @(
    [pscustomobject]@{
        Name          = 'Logitech LIGHTSPEED mouse function'
        InstanceRegex = '^USB\\VID_046D&PID_C54D&MI_00\\'
        ExpectedVidPid= 'USB\VID_046D&PID_C54D'
    },
    [pscustomobject]@{
        Name          = 'Wooting 80HE keyboard function'
        InstanceRegex = '^USB\\VID_31E3&PID_1402&MI_01\\'
        ExpectedVidPid= 'USB\VID_31E3&PID_1402'
    }
)

function Normalize-WmiInstanceName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    return (($Name.Trim()) -replace '_\d+$','')
}

function Get-HardwareIds {
    param([Parameter(Mandatory)][string]$InstanceId)

    try {
        return @(
            (Get-PnpDeviceProperty `
                -InstanceId $InstanceId `
                -KeyName 'DEVPKEY_Device_HardwareIds' `
                -ErrorAction Stop).Data
        ) | ForEach-Object { [string]$_ }
    }
    catch {
        return @()
    }
}

function Get-MatchingPowerObject {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][array]$PowerObjects
    )

    return @(
        $PowerObjects |
        Where-Object {
            (Normalize-WmiInstanceName ([string]$_.InstanceName)) -ieq $InstanceId
        }
    )
}

function Set-ExactDevicePowerOff {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][array]$PowerObjects
    )

    $devices = @(
        Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object {
            [string]$_.InstanceId -match $Target.InstanceRegex
        }
    )

    if ($devices.Count -ne 1) {
        throw ("{0}: expected exactly one present target function, found {1}. No change made." -f $Target.Name,$devices.Count)
    }

    $device = $devices[0]
    $instanceId = [string]$device.InstanceId
    $hardwareIds = @(Get-HardwareIds -InstanceId $instanceId)

    $identityOk = @(
        $hardwareIds |
        Where-Object {
            $_ -like ($Target.ExpectedVidPid + '*')
        }
    ).Count -gt 0

    if (-not $identityOk) {
        throw ("{0}: hardware-ID verification failed for {1}. No change made." -f $Target.Name,$instanceId)
    }

    $power = @(Get-MatchingPowerObject -InstanceId $instanceId -PowerObjects $PowerObjects)

    if ($power.Count -ne 1) {
        throw ("{0}: expected exactly one MSPower_DeviceEnable object, found {1}. No change made." -f $Target.Name,$power.Count)
    }

    $before = [bool]$power[0].Enable

    Write-Host ("Target      : {0}" -f $Target.Name)
    Write-Host ("InstanceId  : {0}" -f $instanceId)
    Write-Host ("Power before: {0}" -f $before)

    if ($Mode -eq 'Apply' -and $before) {
        Set-CimInstance `
            -InputObject $power[0] `
            -Property @{ Enable = $false } `
            -ErrorAction Stop | Out-Null

        Write-Host '[APPLIED] Device power management disabled.'
    }
    elseif (-not $before) {
        Write-Host '[UNCHANGED] Device power management already disabled.'
    }
    else {
        Write-Host '[AUDIT] Would disable device power management.'
    }

    $fresh = @(
        Get-CimInstance `
            -Namespace 'root\wmi' `
            -ClassName 'MSPower_DeviceEnable' `
            -ErrorAction Stop |
        Where-Object {
            (Normalize-WmiInstanceName ([string]$_.InstanceName)) -ieq $instanceId
        }
    )

    if ($fresh.Count -ne 1) {
        throw ("{0}: verification object count changed unexpectedly." -f $Target.Name)
    }

    $after = [bool]$fresh[0].Enable
    Write-Host ("Power after : {0}" -f $after)
    Write-Host ''

    if ($Mode -eq 'Apply' -and $after) {
        throw ("{0}: power-management disable did not verify." -f $Target.Name)
    }

    return [pscustomobject]@{
        Name       = $Target.Name
        InstanceId = $instanceId
        Before     = $before
        After      = $after
        Verified   = if ($Mode -eq 'Apply') { -not $after } else { $true }
    }
}

function Configure-I226Power {
    $adapters = @(
        Get-NetAdapter -Physical -ErrorAction Stop |
        Where-Object {
            $_.InterfaceDescription -match '(?i)Intel.*I226-V'
        }
    )

    if ($adapters.Count -ne 1) {
        throw ("Intel I226-V: expected exactly one physical adapter, found {0}. No NIC change made." -f $adapters.Count)
    }

    $nic = $adapters[0]
    $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction Stop
    $master = [string]$pm.AllowComputerToTurnOffDevice

    Write-Host ("NIC         : {0} | {1}" -f $nic.Name,$nic.InterfaceDescription)
    Write-Host ("AllowComputerToTurnOff  : {0} (verification only)" -f $master)
    Write-Host ("SelectiveSuspend        : {0} (report only)" -f $pm.SelectiveSuspend)
    Write-Host ("DeviceSleepOnDisconnect : {0} (report only)" -f $pm.DeviceSleepOnDisconnect)
    Write-Host ("ARP Offload             : {0} (stock/report only)" -f $pm.ArpOffload)
    Write-Host ("NS Offload              : {0} (stock/report only)" -f $pm.NSOffload)
    Write-Host ("Wake on Magic Packet    : {0} (stock/report only)" -f $pm.WakeOnMagicPacket)
    Write-Host ("Wake on Pattern         : {0} (stock/report only)" -f $pm.WakeOnPattern)
    Write-Host ''

    if ($master -ne 'Disabled') {
        Write-Warning ("I226-V master device-power state is {0}. The earlier I226 baseline owns this setting; no duplicate fallback is attempted here." -f $master)
    }

    return [pscustomobject]@{
        Name       = $nic.Name
        MasterOk   = ($master -eq 'Disabled')
        Master     = $master
        Partial    = ($master -ne 'Disabled')
    }
}

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (" GAMING DEVICE POWER BASELINE v{0}" -f $ScriptVersion)
    Write-Host '============================================================'
    Write-Host ("Mode : {0}" -f $Mode)
    Write-Host ("Log  : {0}" -f $LogFile)
    Write-Host ''

    $powerObjects = @(
        Get-CimInstance `
            -Namespace 'root\wmi' `
            -ClassName 'MSPower_DeviceEnable' `
            -ErrorAction Stop
    )

    $results = @()

    foreach ($target in $Targets) {
        $results += Set-ExactDevicePowerOff `
            -Target $target `
            -PowerObjects $powerObjects
    }

    $nicResult = Configure-I226Power

    Write-Host '============================================================'
    Write-Host ' FINAL REPORT'
    Write-Host '============================================================'

    foreach ($r in $results) {
        Write-Host ("{0,-36} : {1}" -f $r.Name,$(
            if ($Mode -eq 'Apply') {
                if ($r.Verified) { 'POWER MANAGEMENT OFF' } else { 'FAILED' }
            }
            else {
                if ($r.Before) { 'WOULD DISABLE' } else { 'ALREADY OFF' }
            }
        ))
    }

    Write-Host ("{0,-36} : {1}" -f 'I226-V allow device power-off',$(
        if ($nicResult.MasterOk) { 'DISABLED' } else { 'CHECK EARLIER I226 STEP' }
    ))

    if ($nicResult.Partial) {
        Write-Warning 'I226-V master device-power state did not match the earlier targeted baseline; this verification layer made no duplicate NIC changes.'
    }

    Write-Host 'USB Root Hub / xHCI / HS80 / unrelated HID: STOCK'
    Write-Host ("Log: {0}" -f $LogFile)
    Write-Host ''

    if ($Mode -eq 'Apply') {
        Write-Host 'A reboot is recommended before benchmarking.'
    }
    else {
        Write-Host 'No configuration changes were made.'
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
