#requires -RunAsAdministrator
<#
.SYNOPSIS
  Conservative gaming-only device disable layer.

.DESCRIPTION
  Default mode is Apply. The script is intended to be called automatically
  by the gaming launcher. Audit and Restore remain available explicitly.

  Apply targets only the explicitly approved unused endpoints:
    - Bluetooth radio adapter(s)
    - Wi-Fi/WLAN adapter(s), including the user-confirmed generic "Network Controller"
    - NVIDIA High Definition Audio / Audio Controller
    - Realtek USB2.0 Audio
    - AURA LED Controller
    - Standard SATA AHCI Controller, ONLY after conservative safety checks

  Intentionally NOT touched:
    - Intel I226-V / Ethernet
    - Corsair / HS80
    - AMD iGPU
    - PCIe Root/Upstream/Downstream ports
    - USB host controllers/root hubs
    - ACPI/System devices
    - AMD 3D V-Cache / PPM / provisioning components
    - NVMe controller
    - HPET
    - WAN Miniports
    - Generic USB Input / USB Composite devices
    - Unknown devices
    - ASUS/Aura services (reported only; not auto-disabled)

  Apply is idempotent:
    - devices already disabled by this script are not disabled again
    - devices already disabled outside this script are left alone and are not
      claimed by the restore state
    - the restore state is merged instead of overwritten on reruns

  Restore re-enables only devices successfully disabled by this script.

.EXAMPLE
  .\Gaming-Device-Disable-v2.ps1
  # Apply automatically

.EXAMPLE
  .\Gaming-Device-Disable-v2.ps1 -Mode Audit

.EXAMPLE
  .\Gaming-Device-Disable-Final.ps1 -Mode Restore
#>

[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Restore')]
    [string]$Mode = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateDir  = Join-Path $env:ProgramData 'GamingDeviceBaseline'
$StateFile = Join-Path $StateDir 'disabled-devices-v2.json'
$LogFile   = Join-Path $StateDir 'device-disable-v2.log'

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line
}

function Get-DeviceProblemCode {
    param([Parameter(Mandatory)][string]$InstanceId)

    try {
        $p = Get-PnpDeviceProperty `
            -InstanceId $InstanceId `
            -KeyName 'DEVPKEY_Device_ProblemCode' `
            -ErrorAction Stop

        if ($null -eq $p.Data) {
            return $null
        }

        return [int]$p.Data
    }
    catch {
        return $null
    }
}

function Get-ManagedStateItems {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return @()
    }

    try {
        $state = Get-Content -LiteralPath $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return @($state.Disabled)
    }
    catch {
        Write-Log ("WARNING: Could not read existing state file; preserving it as backup before continuing. {0}" -f $_.Exception.Message)

        try {
            $backup = '{0}.corrupt-{1}.bak' -f $StateFile, (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $StateFile -Destination $backup -Force
            Write-Log ("Corrupt/unreadable state backup: {0}" -f $backup)
        }
        catch {
            Write-Log ("WARNING: Could not back up unreadable state file: {0}" -f $_.Exception.Message)
        }

        return @()
    }
}

function Save-ManagedState {
    param([Parameter(Mandatory)][object[]]$Items)

    $deduped = @(
        $Items |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.InstanceId) } |
        Group-Object { ([string]$_.InstanceId).ToUpperInvariant() } |
        ForEach-Object { $_.Group[0] }
    )

    $state = [pscustomobject]@{
        Version   = 3
        UpdatedAt = (Get-Date).ToString('o')
        Computer  = $env:COMPUTERNAME
        Disabled  = $deduped
    }

    $tmp = "$StateFile.tmp"

    $state |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $tmp -Encoding utf8

    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Get-DeviceChildren {
    param([Parameter(Mandatory)][string]$InstanceId)

    try {
        $p = Get-PnpDeviceProperty `
            -InstanceId $InstanceId `
            -KeyName 'DEVPKEY_Device_Children' `
            -ErrorAction Stop

        return @($p.Data | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    catch {
        return @()
    }
}

function Test-SataControllerSafeToDisable {
    param([Parameter(Mandatory)]$Device)

    $reasons = New-Object System.Collections.Generic.List[string]

    # Any disk Windows explicitly identifies as SATA => do not disable.
    try {
        $sataDisks = @(
            Get-Disk -ErrorAction Stop |
            Where-Object { [string]$_.BusType -eq 'SATA' }
        )

        if ($sataDisks.Count -gt 0) {
            $reasons.Add("Windows reports $($sataDisks.Count) SATA disk(s).")
        }
    }
    catch {
        $reasons.Add('Could not verify disk bus types.')
    }

    # Conservative check: if the AHCI controller has PnP children, assume it may be in use.
    $children = @(Get-DeviceChildren -InstanceId $Device.InstanceId)
    if ($children.Count -gt 0) {
        $reasons.Add("AHCI controller has $($children.Count) PnP child device(s).")
    }

    # If a physical/optical ATA/SATA-looking device is present, skip.
    try {
        $diskDrives = @(
            Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
            Where-Object {
                ([string]$_.InterfaceType -match '(?i)IDE|ATA') -or
                ([string]$_.PNPDeviceID -match '(?i)^IDE\\|^SCSI\\.*ATA')
            }
        )

        if ($diskDrives.Count -gt 0) {
            $reasons.Add("Detected $($diskDrives.Count) ATA/IDE-looking disk device(s).")
        }
    }
    catch {
        $reasons.Add('Could not complete ATA/IDE disk cross-check.')
    }

    if ($reasons.Count -gt 0) {
        return [pscustomobject]@{
            Safe    = $false
            Reasons = @($reasons)
        }
    }

    return [pscustomobject]@{
        Safe    = $true
        Reasons = @()
    }
}

function Test-HardExcluded {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$InstanceId
    )

    if ($Name -match '(?i)I226|Ethernet Controller|Corsair|HS80|USB Input Device|USB Composite Device|Root Hub|Host Controller|Root Port|Upstream Switch|Downstream Switch|NVM Express|NVMe|SMBUS|GPIO|I2C|PSP|3D V-Cache|Application Compatibility|Provisioning|ACPI|Hyper-V|TPM|High precision event timer|WAN Miniport') {
        return $true
    }

    if ($InstanceId -match '(?i)VID_1B1C') {
        return $true
    }

    return $false
}

function Get-SafeTargets {
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)

    foreach ($d in $devices) {
        $name = [string]$d.FriendlyName
        $cls  = [string]$d.Class
        $id   = [string]$d.InstanceId

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        if (Test-HardExcluded -Name $name -InstanceId $id) {
            continue
        }

        # Bluetooth radio only.
        if (
            $cls -eq 'Bluetooth' -and
            $name -match '(?i)^(Generic Bluetooth Adapter|Intel\(R\) Wireless Bluetooth\(R\)|Realtek Bluetooth Adapter|MediaTek Bluetooth Adapter|.*Bluetooth.*Adapter)$'
        ) {
            [pscustomobject]@{
                Category   = 'Bluetooth radio'
                Name       = $name
                Class      = $cls
                InstanceId = $id
                Reason     = 'Bluetooth is unused; radio endpoint only.'
            }
            continue
        }

        # Wi-Fi/WLAN. Includes the machine's already user-verified generic Network Controller.
        if (
            (
                ($cls -eq 'Net' -and $name -match '(?i)(Wi-?Fi|Wireless|WLAN|802\.11)') -or
                ($name -match '(?i)^Network Controller$')
            ) -and
            $name -notmatch '(?i)(Bluetooth|Virtual|VPN|Hyper-V|I226|Ethernet)'
        ) {
            [pscustomobject]@{
                Category   = 'Wi-Fi adapter'
                Name       = $name
                Class      = $cls
                InstanceId = $id
                Reason     = 'Wi-Fi is unused.'
            }
            continue
        }

        # NVIDIA HDMI / DisplayPort audio function only.
        if (
            $name -match '(?i)^NVIDIA High Definition Audio( Controller)?$'
        ) {
            [pscustomobject]@{
                Category   = 'NVIDIA display audio'
                Name       = $name
                Class      = $cls
                InstanceId = $id
                Reason     = 'HDMI/DP audio is unused.'
            }
            continue
        }

        # Realtek USB audio. Corsair/HS80 is hard-excluded above.
        if (
            $name -match '(?i)^Realtek USB2\.0 Audio$'
        ) {
            [pscustomobject]@{
                Category   = 'Realtek USB audio'
                Name       = $name
                Class      = $cls
                InstanceId = $id
                Reason     = 'Onboard/unused Realtek USB audio endpoint.'
            }
            continue
        }

        # ASUS AURA USB LED controller only. No generic USB/RGB matching.
        if (
            $name -match '(?i)^AURA LED Controller$'
        ) {
            [pscustomobject]@{
                Category   = 'AURA RGB controller'
                Name       = $name
                Class      = $cls
                InstanceId = $id
                Reason     = 'RGB is unused; exact AURA LED Controller match.'
            }
            continue
        }

        # SATA controller only if conservative safety checks pass.
        if (
            $name -match '(?i)^Standard SATA AHCI Controller$'
        ) {
            $safety = Test-SataControllerSafeToDisable -Device $d

            if ($safety.Safe) {
                [pscustomobject]@{
                    Category   = 'Unused SATA AHCI'
                    Name       = $name
                    Class      = $cls
                    InstanceId = $id
                    Reason     = 'No SATA disk or PnP child detected; controller appears unused.'
                }
            }
            else {
                Write-Host ''
                Write-Host 'SATA AHCI controller NOT targeted:' -ForegroundColor Yellow
                Write-Host ('  {0}' -f $name) -ForegroundColor Yellow
                foreach ($r in $safety.Reasons) {
                    Write-Host ('  - {0}' -f $r) -ForegroundColor Yellow
                }
            }

            continue
        }
    }
}

function Show-AsusRgbSoftware {
    $svcPatterns = '(?i)Aura|LightingService|Armoury|ROG Live|ASUS'

    $services = @(
        Get-Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match $svcPatterns -or $_.DisplayName -match $svcPatterns
        }
    )

    if ($services.Count -gt 0) {
        Write-Host ''
        Write-Host 'ASUS/Aura-related services found (REPORT ONLY; not changed):' -ForegroundColor Yellow
        $services |
            Select-Object Status, Name, DisplayName |
            Sort-Object Name |
            Format-Table -AutoSize
    }
}

function Disable-Target {
    param([Parameter(Mandatory)]$Target)

    Write-Log ("DISABLE request: {0} | {1}" -f $Target.Name, $Target.InstanceId)

    & "$env:windir\System32\pnputil.exe" /disable-device "$($Target.InstanceId)"
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        Write-Log ("DISABLED: {0}" -f $Target.Name)
        return $true
    }

    Write-Log ("FAILED ({0}): {1}" -f $code, $Target.Name)
    return $false
}

function Enable-Instance {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [string]$Name = $InstanceId
    )

    Write-Log ("ENABLE request: {0} | {1}" -f $Name, $InstanceId)

    & "$env:windir\System32\pnputil.exe" /enable-device "$InstanceId"
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        Write-Log ("ENABLED: {0}" -f $Name)
        return $true
    }

    Write-Log ("FAILED ({0}): {1}" -f $code, $Name)
    return $false
}

Write-Host ''
Write-Host '=== Gaming Device Disable - v2 (Idempotent) ===' -ForegroundColor Cyan
Write-Host ('Mode: {0}' -f $Mode) -ForegroundColor Cyan
Write-Host ''

if ($Mode -eq 'Restore') {
    $items = @(Get-ManagedStateItems)

    if ($items.Count -eq 0) {
        Write-Host 'No devices are currently recorded as managed-disabled.' -ForegroundColor Yellow
        exit 0
    }

    $remaining = @()
    $restoreFailures = 0

    foreach ($item in $items) {
        $id = [string]$item.InstanceId
        $name = [string]$item.Name
        $problemCode = Get-DeviceProblemCode -InstanceId $id

        if ($problemCode -ne 22) {
            Write-Log ("ALREADY ENABLED / NOT CODE 22: {0} | {1}" -f $name, $id)
            continue
        }

        if (-not (Enable-Instance -InstanceId $id -Name $name)) {
            $remaining += $item
            $restoreFailures++
        }
    }

    Save-ManagedState -Items $remaining

    Write-Host ''
    if ($restoreFailures -eq 0) {
        Write-Host 'Restore completed. Managed state is now clean.' -ForegroundColor Green
        exit 0
    }

    Write-Host ("Restore completed with {0} failure(s). Failed entries remain in the state file." -f $restoreFailures) -ForegroundColor Red
    exit 1
}

$targets = @(Get-SafeTargets)

if ($targets.Count -eq 0) {
    Write-Host 'No approved targets matched on this install.' -ForegroundColor Yellow
}
else {
    Write-Host 'Approved targets:' -ForegroundColor Green
    $targets |
        Select-Object Category, Name, Class, InstanceId |
        Format-Table -AutoSize
}

Show-AsusRgbSoftware

if ($Mode -eq 'Audit') {
    Write-Host ''
    Write-Host 'AUDIT ONLY: nothing was changed.' -ForegroundColor Cyan
    Write-Host 'Apply with:'
    Write-Host '  .\Gaming-Device-Disable-v2.ps1'
    exit 0
}

if ($Mode -eq 'Apply') {
    if ($targets.Count -eq 0) {
        Write-Host ''
        Write-Host 'No approved targets are currently visible. Existing managed state is preserved.' -ForegroundColor Yellow
        exit 0
    }

    $snapshotFile = Join-Path $StateDir ('pnp-before-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    try {
        & "$env:windir\System32\pnputil.exe" /enum-devices /connected /relations /drivers /stack |
            Out-File -LiteralPath $snapshotFile -Encoding utf8

        Write-Log ("PnP snapshot: {0}" -f $snapshotFile)
    }
    catch {
        Write-Log ("WARNING: PnP snapshot failed: {0}" -f $_.Exception.Message)
    }

    $managed = @(Get-ManagedStateItems)

    $managedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $managed) {
        [void]$managedIds.Add([string]$item.InstanceId)
    }

    $newlyDisabled = @()
    $alreadyManaged = 0
    $alreadyExternal = 0
    $failures = 0

    foreach ($t in $targets) {
        $problemCode = Get-DeviceProblemCode -InstanceId $t.InstanceId

        # CM_PROB_DISABLED = 22. Do not issue the disable command again.
        if ($problemCode -eq 22) {
            if ($managedIds.Contains([string]$t.InstanceId)) {
                $alreadyManaged++
                Write-Log ("ALREADY DISABLED (managed): {0} | {1}" -f $t.Name, $t.InstanceId)
            }
            else {
                $alreadyExternal++
                Write-Log ("ALREADY DISABLED (external/manual; not added to restore state): {0} | {1}" -f $t.Name, $t.InstanceId)
            }
            continue
        }

        if (Disable-Target -Target $t) {
            $entry = [pscustomobject]@{
                Category   = $t.Category
                Name       = $t.Name
                Class      = $t.Class
                InstanceId = $t.InstanceId
                DisabledAt = (Get-Date).ToString('o')
            }

            $newlyDisabled += $entry
            $managed += $entry
            [void]$managedIds.Add([string]$t.InstanceId)
        }
        else {
            $failures++
        }
    }

    # IMPORTANT: merge with previous state. Never erase restore ownership merely
    # because a device was already disabled or temporarily not enumerated.
    Save-ManagedState -Items $managed

    Write-Host ''
    Write-Host ('Newly disabled            : {0}' -f $newlyDisabled.Count) -ForegroundColor Green
    Write-Host ('Already disabled (managed): {0}' -f $alreadyManaged)
    Write-Host ('Already disabled (external): {0}' -f $alreadyExternal)
    Write-Host ('Failures                  : {0}' -f $failures)
    Write-Host ('State file                : {0}' -f $StateFile)
    Write-Host ('Log file                  : {0}' -f $LogFile)

    if ($failures -gt 0) {
        Write-Host ''
        Write-Host 'One or more approved devices could not be disabled.' -ForegroundColor Red
        exit 1
    }

    Write-Host ''
    Write-Host 'Device layer is in the requested state. Re-running is safe and does not re-disable managed devices.' -ForegroundColor Green
    exit 0
}

