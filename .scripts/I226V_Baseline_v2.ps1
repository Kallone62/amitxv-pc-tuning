# Intel I226-V competitive baseline v2.2 - NIC power-save lockdown
# Delta-only outside the NIC power-management stack.
#
# Changes:
#   - Energy Efficient Ethernet       -> Disabled
#   - DMA Coalescing                  -> Disabled, if exposed
#   - Flow Control                    -> Tx & Rx Disabled
#   - Reduce Speed On Power Down      -> Disabled, if exposed
#   - Ultra Low Power Mode            -> Disabled, if exposed
#   - Idle power down restriction     -> Only idle when user isn't present, if exposed
#   - Windows/NDIS adapter PM         -> Disabled as a whole
#       * Selective Suspend
#       * D0 Packet Coalescing
#       * Device Sleep on Disconnect
#       * ARP/NS low-power offloads
#       * Wake-on-packet PM features
#       * Allow computer to turn off this device
#   - NetBIOS over TCP/IP             -> Disabled on this I226-V only
#
# DOES NOT touch Interrupt Moderation / Interrupt Moderation Rate (ITR), RSS,
# checksum/segmentation offloads, Speed & Duplex, or system-wide PCIe ASPM.

$ErrorActionPreference = "Stop"

$admin = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent()
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    throw "Run this script as Administrator."
}

$nic = @(
    Get-NetAdapter -Physical |
    Where-Object { $_.InterfaceDescription -match '(?i)\bI226-V\b' }
)

if ($nic.Count -eq 0) { throw "Intel I226-V not found." }
if ($nic.Count -gt 1) { throw "Multiple I226-V adapters found; refusing to guess." }

$nic = $nic[0]
$changed = $false
$rebootRequired = $false

Write-Host "I226-V: $($nic.Name) / $($nic.InterfaceDescription)" -ForegroundColor Cyan

function Get-AdvancedProperty {
    param(
        [string[]]$RegistryKeywords,
        [string[]]$DisplayNames = @()
    )

    $props = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -AllProperties -ErrorAction SilentlyContinue)

    foreach ($key in $RegistryKeywords) {
        $p = $props | Where-Object { $_.RegistryKeyword -eq $key } | Select-Object -First 1
        if ($p) { return $p }
    }

    foreach ($name in $DisplayNames) {
        $p = $props | Where-Object { $_.DisplayName -eq $name } | Select-Object -First 1
        if ($p) { return $p }
    }

    return $null
}

function Set-AdvancedRegistryValueSafely {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$RegistryKeywords,
        [Parameter(Mandatory)][string]$RegistryValue,
        [string[]]$DisplayNames = @()
    )

    $p = Get-AdvancedProperty -RegistryKeywords $RegistryKeywords -DisplayNames $DisplayNames

    if (-not $p) {
        Write-Host "[SKIP] $Label - not exposed by current driver" -ForegroundColor DarkGray
        return $false
    }

    $valid = @($p.ValidRegistryValues | ForEach-Object { [string]$_ })
    if ($valid.Count -gt 0 -and $RegistryValue -notin $valid) {
        Write-Host "[SKIP] $Label - driver does not advertise value $RegistryValue" -ForegroundColor Yellow
        return $false
    }

    $current = @($p.RegistryValue | ForEach-Object { [string]$_ })

    if ($current.Count -eq 1 -and $current[0] -eq $RegistryValue) {
        Write-Host "[OK]   $Label (already set)" -ForegroundColor Green
        return $true
    }

    Set-NetAdapterAdvancedProperty `
        -Name $nic.Name `
        -RegistryKeyword $p.RegistryKeyword `
        -RegistryValue $RegistryValue `
        -NoRestart

    $script:changed = $true
    Write-Host "[SET]  $Label" -ForegroundColor Green
    return $true
}

function Set-I226NetbiosDisabled {
    # Map the already-validated physical I226-V adapter to its TCP/IP
    # Win32_NetworkAdapterConfiguration instance. Do not touch other adapters.
    $configs = @(
        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
        Where-Object {
            $_.IPEnabled -and
            [int]$_.InterfaceIndex -eq [int]$nic.ifIndex
        }
    )

    if ($configs.Count -eq 0) {
        throw "I226-V TCP/IP configuration object was not found."
    }

    if ($configs.Count -gt 1) {
        throw "Multiple TCP/IP configuration objects matched I226-V; refusing to guess."
    }

    $cfg = $configs[0]
    $current = [int]$cfg.TcpipNetbiosOptions

    if ($current -eq 2) {
        Write-Host "[OK]   NetBIOS over TCP/IP -> Disabled (already set)" -ForegroundColor Green
        return
    }

    $result = Invoke-CimMethod `
        -InputObject $cfg `
        -MethodName SetTcpipNetbios `
        -Arguments @{ TcpipNetbiosOptions = [uint32]2 } `
        -ErrorAction Stop

    $returnValue = [int]$result.ReturnValue

    if ($returnValue -notin @(0, 1)) {
        throw "SetTcpipNetbios failed with return value $returnValue."
    }

    $verify = @(
        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
        Where-Object {
            $_.IPEnabled -and
            [int]$_.InterfaceIndex -eq [int]$nic.ifIndex
        }
    )

    if ($verify.Count -ne 1 -or [int]$verify[0].TcpipNetbiosOptions -ne 2) {
        throw "NetBIOS over TCP/IP disable did not verify on I226-V."
    }

    $script:changed = $true

    if ($returnValue -eq 1) {
        $script:rebootRequired = $true
        Write-Host "[SET]  NetBIOS over TCP/IP -> Disabled (Windows reports reboot required)" -ForegroundColor Green
    }
    else {
        Write-Host "[SET]  NetBIOS over TCP/IP -> Disabled" -ForegroundColor Green
    }
}

function Disable-I226PowerManagement {
    $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction Stop

    # Microsoft documents parameterless Disable-NetAdapterPowerManagement as
    # disabling all power-management features on the selected adapter. This is
    # intentional here: the target is a no-power-save I226-V while Windows is up.
    if ([string]$pm.AllowComputerToTurnOffDevice -eq "Disabled") {
        Write-Host "[OK]   Windows/NDIS adapter power management -> Disabled (already set)" -ForegroundColor Green
    }
    else {
        Disable-NetAdapterPowerManagement `
            -Name $nic.Name `
            -NoRestart `
            -Confirm:$false

        $script:changed = $true
        Write-Host "[SET]  Windows/NDIS adapter power management -> Disabled" -ForegroundColor Green
    }

    $verify = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction Stop

    if ([string]$verify.AllowComputerToTurnOffDevice -eq "Enabled") {
        throw "Power-management lockdown failed: AllowComputerToTurnOffDevice is still Enabled."
    }

    # If the master device-power control is Disabled, Microsoft documents the
    # remaining property values as undefined. If it is not Disabled, fail if any
    # supported low-power feature still explicitly reports Enabled.
    if ([string]$verify.AllowComputerToTurnOffDevice -ne "Disabled") {
        $enabledPm = @(
            "SelectiveSuspend",
            "D0PacketCoalescing",
            "DeviceSleepOnDisconnect",
            "ArpOffload",
            "NSOffload",
            "WakeOnMagicPacket",
            "WakeOnPattern"
        ) | Where-Object { [string]$verify.$_ -eq "Enabled" }

        if ($enabledPm.Count -gt 0) {
            throw ("Power-management lockdown did not verify. Still enabled: " + ($enabledPm -join ", "))
        }
    }
}

$null = Set-AdvancedRegistryValueSafely `
    -Label "Energy Efficient Ethernet -> Disabled" `
    -RegistryKeywords @("*EEE", "EEELinkAdvertisement") `
    -RegistryValue "0" `
    -DisplayNames @("Energy Efficient Ethernet")

$null = Set-AdvancedRegistryValueSafely `
    -Label "DMA Coalescing -> Disabled" `
    -RegistryKeywords @("DMACoalescing") `
    -RegistryValue "0" `
    -DisplayNames @("DMA Coalescing")

$null = Set-AdvancedRegistryValueSafely `
    -Label "Flow Control -> Tx & Rx Disabled" `
    -RegistryKeywords @("*FlowControl") `
    -RegistryValue "0" `
    -DisplayNames @("Flow Control")

$null = Set-AdvancedRegistryValueSafely `
    -Label "Reduce Speed On Power Down -> Disabled" `
    -RegistryKeywords @("ReduceSpeedOnPowerDown") `
    -RegistryValue "0" `
    -DisplayNames @("Reduce Speed On Power Down", "Reduce Speed on Power Down")

$null = Set-AdvancedRegistryValueSafely `
    -Label "Ultra Low Power Mode -> Disabled" `
    -RegistryKeywords @("ULPMode") `
    -RegistryValue "0" `
    -DisplayNames @("Ultra Low Power Mode")

$null = Set-AdvancedRegistryValueSafely `
    -Label "Idle power down restriction -> Only idle when user isn't present" `
    -RegistryKeywords @("*IdleRestriction") `
    -RegistryValue "1" `
    -DisplayNames @("Idle power down restriction")

# Disable the Windows/NDIS power-management layer independently of IdleRestriction.
# This removes the old v2.1 behavior where Selective Suspend was only a fallback.
Disable-I226PowerManagement

Set-I226NetbiosDisabled

if ($changed) {
    Write-Host "`nRestarting adapter once to apply changes..." -ForegroundColor Cyan
    Restart-NetAdapter -Name $nic.Name -Confirm:$false
    Start-Sleep -Seconds 2
}
else {
    Write-Host "`nNo changes required." -ForegroundColor Cyan
}

Write-Host "`n=== CURRENT I226-V STATE ===" -ForegroundColor Cyan

Get-NetAdapterAdvancedProperty -Name $nic.Name -AllProperties |
    Where-Object {
        $_.RegistryKeyword -in @(
            "*EEE",
            "EEELinkAdvertisement",
            "DMACoalescing",
            "*FlowControl",
            "ReduceSpeedOnPowerDown",
            "ULPMode",
            "*IdleRestriction",
            "*InterruptModeration",
            "ITR"
        ) -or $_.DisplayName -in @(
            "Energy Efficient Ethernet",
            "DMA Coalescing",
            "Flow Control",
            "Reduce Speed On Power Down",
            "Reduce Speed on Power Down",
            "Ultra Low Power Mode",
            "Idle power down restriction",
            "Interrupt Moderation",
            "Interrupt Moderation Rate"
        )
    } |
    Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue |
    Sort-Object DisplayName |
    Format-Table -AutoSize

$pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
if ($pm) {
    $pm |
        Select-Object `
            Name,
            AllowComputerToTurnOffDevice,
            SelectiveSuspend,
            D0PacketCoalescing,
            DeviceSleepOnDisconnect,
            ArpOffload,
            NSOffload,
            WakeOnMagicPacket,
            WakeOnPattern |
        Format-List
}

$netbiosCfg = @(
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPEnabled -and
        [int]$_.InterfaceIndex -eq [int]$nic.ifIndex
    }
)

if ($netbiosCfg.Count -eq 1) {
    $netbiosValue = [int]$netbiosCfg[0].TcpipNetbiosOptions
    $netbiosState = switch ($netbiosValue) {
        0 { "DHCP controlled" }
        1 { "Enabled" }
        2 { "Disabled" }
        default { "Unknown ($netbiosValue)" }
    }

    Write-Host ("NetBIOS over TCP/IP : {0}" -f $netbiosState)
}

Write-Host "Interrupt Moderation / ITR were NOT modified." -ForegroundColor Yellow
Write-Host "RSS / checksum offloads / LSO / Speed & Duplex were NOT modified." -ForegroundColor Yellow
Write-Host "System-wide PCIe ASPM was NOT modified." -ForegroundColor Yellow

if ($rebootRequired) {
    Write-Host ""
    Write-Host "Windows reports a reboot is required for the NetBIOS change to become fully effective." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== OPTIONAL A/B TEST REMINDERS ===" -ForegroundColor Cyan
Write-Host "These are NOT applied automatically." -ForegroundColor Yellow
Write-Host "1. Interrupt Moderation Rate: Low / Medium / High"
Write-Host "2. RSS receive queues: Driver default / 2 queues"
Write-Host "3. PCIe Link State Power Management / ASPM: system-wide; test separately only"
Write-Host "Test one variable at a time and keep the rest unchanged."
