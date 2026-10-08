#requires -Version 5.1

<#
.SYNOPSIS
    Counter-Strike 2 / Steam / FACEIT Windows 11 Pro gaming baseline.
.DESCRIPTION
    Purpose: this machine exists to run Steam and Counter-Strike 2. Reduce
    background work and state changes that are unnecessary for that workload,
    while preserving stock Windows kernel, scheduler, power-management, PnP,
    driver, memory, networking and servicing behavior unless a narrower change
    has a strong mechanism and low dependency risk.

    This script intentionally does NOT apply timer/BCD tweaks, blanket service
    disabling, MSI/IRQ affinity changes, C-state/core-parking changes, memory
    manager hacks, ResourcePolicyStore changes, or component-store surgery.

    Chipset, GPU and LAN/Wi-Fi/audio drivers should be installed from the
    appropriate hardware vendors where applicable. Standard mouse/keyboard
    devices may remain on Windows inbox HID/class drivers. Run this baseline
    after the final drivers are installed and after the intended default playback
    device is selected; hardware-dependent steps such as EEE/audio only act when
    the installed adapter/endpoint exposes the required supported path.

    Steam, Counter-Strike 2 and FACEIT Anti-Cheat are intentionally preserved.

    The baseline also standardizes the interactive gaming account after each
    clean Windows installation: dark UI, a locked solid-black desktop,
    deterministic Explorer visibility options, and removal of only the Edge
    and Microsoft Store taskbar pins. These are UX/state controls, not
    performance claims. Windows 11's stock Open in Terminal integration is left
    untouched.

    Launching the .ps1 normally is supported: when required, the script relaunches
    itself in elevated 64-bit Windows PowerShell 5.1 and requests UAC once.

    FACEIT UEFI/security compatibility is a hard constraint. Secure Boot and
    TPM 2.0 are required; VBS/IOMMU/HVCI are never force-disabled by this script.
#>

# ---------------------------------------------------------------------------
# LAUNCH BOOTSTRAP
# ---------------------------------------------------------------------------
# The baseline itself must run from elevated 64-bit Windows PowerShell 5.1
# because AppX/DISM, NetAdapter and Windows-specific modules are part of the
# supported execution path. If launched normally, from 32-bit PowerShell, or
# from PowerShell 7, relaunch this same file in the required host and request
# UAC elevation automatically. The new process keeps the same user identity,
# which is important because HKCU/AppX work must target the gaming account.
function Test-IsAdministratorToken {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $Identity
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$NeedsWindowsPowerShell = ($PSVersionTable.PSEdition -ne 'Desktop')
$Needs64Bit             = (-not [Environment]::Is64BitProcess)
$NeedsElevation         = (-not (Test-IsAdministratorToken))

if ($NeedsWindowsPowerShell -or $Needs64Bit -or $NeedsElevation) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'This baseline must be launched from its .ps1 file so it can relaunch itself in elevated 64-bit Windows PowerShell 5.1.'
    }

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $WindowsPowerShellExe = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $WindowsPowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    if (-not (Test-Path -LiteralPath $WindowsPowerShellExe)) {
        throw "64-bit Windows PowerShell 5.1 was not found at: $WindowsPowerShellExe"
    }

    $WorkingDirectory = Split-Path -Parent $PSCommandPath
    $ArgumentLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath

    try {
        Start-Process `
            -FilePath $WindowsPowerShellExe `
            -ArgumentList $ArgumentLine `
            -WorkingDirectory $WorkingDirectory `
            -Verb RunAs `
            -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Could not relaunch the baseline with administrator rights: $($_.Exception.Message)"
    }

    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.9'
$TargetWorkload = 'Steam / Counter-Strike 2 / FACEIT Anti-Cheat'


# ============================================================================
# 00 - SAFETY / PRECONDITIONS
# ============================================================================

function Get-CurrentWindowsInfo {
    $CurrentVersion = Get-ItemProperty `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -ErrorAction Stop

    [pscustomobject]@{
        ProductName    = [string]$CurrentVersion.ProductName
        EditionID      = [string]$CurrentVersion.EditionID
        DisplayVersion = [string]$CurrentVersion.DisplayVersion
        CurrentBuild   = [string]$CurrentVersion.CurrentBuild
        UBR            = [int]$CurrentVersion.UBR
    }
}

function Assert-FaceitBaseline {
    [CmdletBinding()]
    param ()

    # FACEIT UEFI / SECURITY BASELINE
    # Hardware-model agnostic: verify the firmware/security state FACEIT depends on.
    # FACEIT requires Secure Boot and TPM 2.0 for Windows 11 players.
    try {
        $SecureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop
    }
    catch {
        throw "FACEIT preflight could not verify Secure Boot: $($_.Exception.Message)"
    }

    if (-not $SecureBootEnabled) {
        throw 'FACEIT preflight failed: Secure Boot is not enabled.'
    }

    $Tpm = Get-Tpm -ErrorAction Stop
    if (-not $Tpm.TpmPresent -or -not $Tpm.TpmReady) {
        throw 'FACEIT preflight failed: TPM is not present and ready.'
    }

    try {
        $TpmInfo = Get-CimInstance `
            -Namespace 'root\CIMV2\Security\MicrosoftTpm' `
            -ClassName Win32_Tpm `
            -ErrorAction Stop
    }
    catch {
        throw "FACEIT preflight could not verify TPM 2.0 through Win32_Tpm: $($_.Exception.Message)"
    }

    if ($null -eq $TpmInfo -or [string]$TpmInfo.SpecVersion -notmatch '(^|,\s*)2\.0(,|$)') {
        throw "FACEIT preflight failed: TPM 2.0 was not detected. SpecVersion: $($TpmInfo.SpecVersion)"
    }

    Write-Host '[FACEIT] Secure Boot: enabled'
    Write-Host '[FACEIT] TPM: present and ready'

    # SapphireOS itself has to undo its default NX/DEP disable for FACEIT.
    # Keep the Windows DEP policy at a normal enabled mode (OptIn/OptOut/AlwaysOn).
    $OperatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $DepPolicy = [int]$OperatingSystem.DataExecutionPrevention_SupportPolicy
    if ($DepPolicy -eq 0) {
        throw 'FACEIT preflight failed: DEP/NX is configured AlwaysOff. Restore the normal Windows DEP policy before continuing.'
    }
    Write-Host "[FACEIT] DEP/NX policy: $DepPolicy (enabled mode)"

    # FACEIT is progressively enforcing IOMMU/DMA protection and VBS on
    # compatible systems. Report their state, but do not mutate the security
    # virtualization chain here. HVCI is only required when FACEIT asks for it.
    try {
        $DeviceGuard = Get-CimInstance `
            -Namespace 'root\Microsoft\Windows\DeviceGuard' `
            -ClassName Win32_DeviceGuard `
            -ErrorAction Stop
    }
    catch {
        $DeviceGuard = $null
        Write-Warning "Unable to query Win32_DeviceGuard: $($_.Exception.Message). Verify VBS/IOMMU/HVCI state before FACEIT."
    }

    if ($null -ne $DeviceGuard) {
        $VbsRunning = ([int]$DeviceGuard.VirtualizationBasedSecurityStatus -eq 2)
        $DmaProtectionAvailable = (@($DeviceGuard.AvailableSecurityProperties) -contains 3)
        $HvciRunning = (@($DeviceGuard.SecurityServicesRunning) -contains 2)

        Write-Host ("[FACEIT] VBS: {0}" -f $(if ($VbsRunning) { 'running' } else { 'not running' }))
        Write-Host ("[FACEIT] DMA protection capability: {0}" -f $(if ($DmaProtectionAvailable) { 'reported' } else { 'not reported' }))
        Write-Host ("[FACEIT] Memory Integrity / HVCI: {0}" -f $(if ($HvciRunning) { 'running' } else { 'not running' }))

        if (-not $VbsRunning) {
            Write-Warning 'FACEIT may require VBS on this hardware/account. This script will not disable or bypass that requirement.'
        }
        if (-not $DmaProtectionAvailable) {
            Write-Warning 'FACEIT UEFI check: DMA protection capability was not reported. Verify virtualization/IOMMU/DMA Protection in UEFI before FACEIT.'
        }
    }
    else {
        Write-Warning 'Win32_DeviceGuard state is unavailable. FACEIT security virtualization requirements were not modified by this script.'
    }

    # FACEIT lists these proprietary storage drivers as incompatible with DMA
    # remapping in some configurations and recommends the Microsoft inbox
    # storage driver instead. A currently running match is a hard stop.
    $BlockedStorageDriverNames = @(
        'secnvme',
        'solidnvm',
        'mtinvme',
        'asstahci64',
        'mvs91xx',
        'amd_sata'
    )

    $StorageConflicts = @(
        Get-CimInstance Win32_SystemDriver -ErrorAction Stop |
            Where-Object { $BlockedStorageDriverNames -contains $_.Name }
    )

    $RunningConflicts = @($StorageConflicts | Where-Object { $_.State -eq 'Running' })
    if ($RunningConflicts.Count -gt 0) {
        $Names = ($RunningConflicts.Name | Sort-Object -Unique) -join ', '
        throw "FACEIT preflight failed: incompatible storage driver(s) currently running: $Names. Replace with the compatible Microsoft inbox driver before using this baseline."
    }

    foreach ($Driver in $StorageConflicts) {
        Write-Warning "FACEIT-listed storage driver is installed but not running: $($Driver.Name). Verify it is not bound to an active controller."
    }
}

function Assert-TargetUserContext {
    [CmdletBinding()]
    param ()

    # This baseline writes HKCU settings and removes current-user AppX packages.
    # UAC elevation with the same user is fine, but "Run as different user" would
    # silently target the administrator account instead of the interactive gaming
    # account. Compare the current token SID with Explorer in this same session.
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $CurrentSid = [string]$CurrentIdentity.User.Value
    $CurrentSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId

    $Explorer = @(
        Get-CimInstance Win32_Process `
            -Filter "Name='explorer.exe'" `
            -ErrorAction Stop |
            Where-Object { [int]$_.SessionId -eq $CurrentSessionId }
    ) | Select-Object -First 1

    if ($null -eq $Explorer) {
        throw 'No Explorer shell was found in the current session. Run this script interactively from the target gaming account, then elevate that same PowerShell session.'
    }

    $OwnerResult = Invoke-CimMethod `
        -InputObject $Explorer `
        -MethodName GetOwnerSid `
        -ErrorAction Stop

    $ExplorerOwnerSid = [string]$OwnerResult.Sid
    if ([string]::IsNullOrWhiteSpace($ExplorerOwnerSid)) {
        throw 'Could not resolve the interactive Explorer owner SID. Aborting to avoid writing HKCU settings to the wrong user profile.'
    }

    if (-not [string]::Equals($CurrentSid, $ExplorerOwnerSid, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The elevated PowerShell token belongs to a different user than the interactive gaming session. Current SID: $CurrentSid; Explorer SID: $ExplorerOwnerSid. Elevate PowerShell from the target gaming account instead of using different administrator credentials."
    }

    Write-Host "[CONTEXT] Interactive target user: $($CurrentIdentity.Name)"
}

function Assert-TargetEnvironment {
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Execution-host bootstrap failed: this baseline requires 64-bit Windows PowerShell 5.1 (powershell.exe).'
    }

    if (-not [Environment]::Is64BitProcess) {
        throw 'Execution-host bootstrap failed: this baseline requires a 64-bit PowerShell process.'
    }

    $Windows = Get-CurrentWindowsInfo

    if ([int]$Windows.CurrentBuild -lt 22000) {
        throw "This script targets Windows 11. Detected build: $($Windows.CurrentBuild)."
    }

    if ($Windows.EditionID -ne 'Professional') {
        throw "This script targets Windows 11 Pro. Detected EditionID: $($Windows.EditionID)."
    }

    Write-Host "Windows : $($Windows.ProductName) $($Windows.DisplayVersion) build $($Windows.CurrentBuild).$($Windows.UBR)"
    Write-Host "Target  : $TargetWorkload (script v$ScriptVersion)"
}

$LogRoot = Join-Path $env:ProgramData 'GamingOnlyBaseline\Logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogFile = Join-Path $LogRoot ("apply-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null

# ============================================================================
# HELPERS
# ============================================================================

function Get-RegistryValueState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Exists = $false
            Kind   = $null
            Value  = $null
        }
    }

    $Key = Get-Item -LiteralPath $Path -ErrorAction Stop
    $Exists = @($Key.GetValueNames()) -ccontains $Name
    if (-not $Exists) {
        return [pscustomobject]@{
            Exists = $false
            Kind   = $null
            Value  = $null
        }
    }

    [pscustomobject]@{
        Exists = $true
        Kind   = $Key.GetValueKind($Name)
        Value  = $Key.GetValue(
            $Name,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
    }
}

function Set-RegistryDword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [uint32]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    $State = Get-RegistryValueState -Path $Path -Name $Name
    if ($State.Exists -and
        $State.Kind -eq [Microsoft.Win32.RegistryValueKind]::DWord -and
        [uint32]$State.Value -eq $Value) {
        return
    }

    New-ItemProperty `
        -LiteralPath $Path `
        -Name $Name `
        -PropertyType DWord `
        -Value $Value `
        -Force `
        -ErrorAction Stop | Out-Null

    Write-Host "[APPLIED] $Path :: $Name = $Value"
}

function Set-RegistryString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    $State = Get-RegistryValueState -Path $Path -Name $Name
    if ($State.Exists -and
        $State.Kind -eq [Microsoft.Win32.RegistryValueKind]::String -and
        [string]$State.Value -ceq $Value) {
        return
    }

    New-ItemProperty `
        -LiteralPath $Path `
        -Name $Name `
        -PropertyType String `
        -Value $Value `
        -Force `
        -ErrorAction Stop | Out-Null

    Write-Host "[APPLIED] $Path :: $Name = $Value"
}

function Set-DesktopWallpaperBlack {
    [CmdletBinding()]
    param ()

    # Use a real 1x1 black BMP because the supported wallpaper policy requires
    # an image path. Lock only wallpaper changes; leave all other UI state alone.
    $AssetRoot = Join-Path $env:ProgramData 'GamingOnlyBaseline\Assets'
    New-Item -ItemType Directory -Path $AssetRoot -Force -ErrorAction Stop | Out-Null
    $WallpaperPath = Join-Path $AssetRoot 'Desktop-Black.bmp'
    $BitmapBytes = [Convert]::FromBase64String(
        'Qk06AAAAAAAAADYAAAAoAAAAAQAAAAEAAAABABgAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
    )

    if (-not (Test-Path -LiteralPath $WallpaperPath -PathType Leaf) -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($WallpaperPath)) -cne
        [Convert]::ToBase64String($BitmapBytes)) {
        [IO.File]::WriteAllBytes($WallpaperPath, $BitmapBytes)
        Write-Host "[APPLIED] Created fixed black desktop asset: $WallpaperPath"
    }

    Set-RegistryString -Path 'HKCU:\Control Panel\Colors' -Name 'Background' -Value '0 0 0'
    Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value $WallpaperPath
    Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '2'
    Set-RegistryString -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0'

    if (-not ('Cs2GamingBaselineV106.DesktopParameters' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Cs2GamingBaselineV106
{
    public static class DesktopParameters
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SystemParametersInfo(
            uint uiAction,
            uint uiParam,
            string pvParam,
            uint fWinIni
        );
    }
}
'@
    }

    $SPI_SETDESKWALLPAPER = [uint32]0x0014
    $SPIF_UPDATEINIFILE   = [uint32]0x0001
    $SPIF_SENDCHANGE      = [uint32]0x0002

    $WallpaperPolicyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $BackgroundLockPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'

    # Release only our wallpaper controls while refreshing a repeated run.
    Set-RegistryDword -Path $BackgroundLockPath -Name 'NoChangingWallPaper' -Value 0
    foreach ($Name in @('Wallpaper', 'WallpaperStyle')) {
        Remove-ItemProperty -LiteralPath $WallpaperPolicyPath -Name $Name -ErrorAction SilentlyContinue
    }

    $Result = [Cs2GamingBaselineV106.DesktopParameters]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER,
        0,
        $WallpaperPath,
        ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)
    )

    if (-not $Result) {
        $Win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Warning "Windows did not accept the live wallpaper refresh. Win32 error: $Win32Error. Sign out and back in to load the enforced policy."
    }

    Set-RegistryString -Path $WallpaperPolicyPath -Name 'Wallpaper' -Value $WallpaperPath
    Set-RegistryString -Path $WallpaperPolicyPath -Name 'WallpaperStyle' -Value '2'
    Set-RegistryDword -Path $BackgroundLockPath -Name 'NoChangingWallPaper' -Value 1
    Write-Host '[APPLIED] Solid-black desktop background enforced and wallpaper changes locked.'
}

function Remove-EdgeAndStoreShellShortcuts {
    [CmdletBinding()]
    param ()

    # Keep Edge installed; prevent/re-remove its desktop shortcuts.
    $EdgeUpdatePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    Set-RegistryDword -Path $EdgeUpdatePolicyPath -Name 'CreateDesktopShortcutDefault' -Value 0
    Set-RegistryDword -Path $EdgeUpdatePolicyPath -Name 'RemoveDesktopShortcutDefault' -Value 2

    # Remove only .lnk files whose resolved executable is msedge.exe.
    $WshShell = New-Object -ComObject WScript.Shell
    $DesktopPaths = @(
        [Environment]::GetFolderPath('DesktopDirectory'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($DesktopPath in $DesktopPaths) {
        foreach ($Link in @(Get-ChildItem -LiteralPath $DesktopPath -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue)) {
            $Shortcut = $WshShell.CreateShortcut($Link.FullName)
            $TargetPath = [Environment]::ExpandEnvironmentVariables([string]$Shortcut.TargetPath)
            if ([IO.Path]::GetFileName($TargetPath) -ieq 'msedge.exe') {
                Remove-Item -LiteralPath $Link.FullName -Force -ErrorAction Stop
                Write-Host "[REMOVED] Edge desktop shortcut: $($Link.FullName)"
            }
        }
    }

    # Supported policy removes an existing Store pin at the next sign-in.
    Set-RegistryDword `
        -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' `
        -Name 'NoPinningStoreToTaskbar' `
        -Value 1

    # Edge has no equivalent pin policy. Target only its exact AppsFolder item.
    $ShellApplication = New-Object -ComObject Shell.Application
    $AppsFolder = $ShellApplication.Namespace('shell:AppsFolder')
    if ($null -eq $AppsFolder) {
        Write-Warning 'Windows AppsFolder could not be opened; the Edge taskbar pin was not changed.'
        return
    }

    $EdgeItem = $AppsFolder.ParseName('MSEdge')
    if ($null -eq $EdgeItem) {
        Write-Warning 'Microsoft Edge could not be resolved in AppsFolder; its taskbar pin was not changed.'
        return
    }

    try {
        $EdgeItem.InvokeVerb('taskbarunpin')
        Write-Host '[APPLIED] Requested removal of the Microsoft Edge taskbar pin.'
    }
    catch {
        Write-Warning "Windows did not accept the Edge taskbar unpin request: $($_.Exception.Message)"
    }
}

function Remove-LegacyOpenPowerShellHereContextMenu {
    [CmdletBinding()]
    param ()

    # v1.0.1 briefly added custom classic-shell PowerShell verbs. Windows 11's
    # stock Open in Terminal already covers this workflow, so remove those
    # per-user entries and the helper script if upgrading from that version.
    $LegacyKeys = @(
        'HKCU:\Software\Classes\Directory\Background\shell\OpenPowerShellHere',
        'HKCU:\Software\Classes\Directory\shell\OpenPowerShellHere',
        'HKCU:\Software\Classes\Drive\shell\OpenPowerShellHere'
    )

    foreach ($Key in $LegacyKeys) {
        if (Test-Path -LiteralPath $Key) {
            Remove-Item -LiteralPath $Key -Recurse -Force -ErrorAction Stop
            Write-Host "[APPLIED] Removed legacy PowerShell context-menu entry: $Key"
        }
    }

    $LegacyHelper = Join-Path $env:ProgramData 'GamingOnlyBaseline\OpenPowerShellHere.ps1'
    if (Test-Path -LiteralPath $LegacyHelper) {
        Remove-Item -LiteralPath $LegacyHelper -Force -ErrorAction Stop
        Write-Host "[APPLIED] Removed legacy PowerShell context-menu helper: $LegacyHelper"
    }
}

function Disable-EnergyEfficientEthernet {
    [CmdletBinding()]
    param ()

    # *EEE is the standardized NDIS/NetAdapterCx keyword for IEEE 802.3az
    # Energy Efficient Ethernet. Apply only when the installed NIC driver
    # explicitly exposes this property; never manufacture hidden driver values.
    $RequiredCommands = @(
        'Get-NetAdapter',
        'Get-NetAdapterAdvancedProperty',
        'Set-NetAdapterAdvancedProperty'
    )

    foreach ($CommandName in $RequiredCommands) {
        if (-not (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)) {
            Write-Warning "NetAdapter cmdlet '$CommandName' is unavailable; skipped Energy Efficient Ethernet configuration."
            return
        }
    }

    $PhysicalAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
    $MatchedAdapters = 0

    foreach ($Adapter in $PhysicalAdapters) {
        try {
            $EeeProperty = @(
                Get-NetAdapterAdvancedProperty `
                    -Name $Adapter.Name `
                    -AllProperties `
                    -IncludeHidden `
                    -ErrorAction Stop |
                    Where-Object { $_.RegistryKeyword -eq '*EEE' }
            ) | Select-Object -First 1
        }
        catch {
            Write-Warning "Could not query advanced properties for '$($Adapter.Name)': $($_.Exception.Message)"
            continue
        }

        if ($null -eq $EeeProperty) {
            continue
        }

        $MatchedAdapters++
        $CurrentValue = @($EeeProperty.RegistryValue) | Select-Object -First 1

        if ([string]$CurrentValue -eq '0') {
            Write-Host "[UNCHANGED] $($Adapter.Name) :: Energy Efficient Ethernet already disabled"
            continue
        }

        try {
            Set-NetAdapterAdvancedProperty `
                -InputObject $EeeProperty `
                -RegistryValue '0' `
                -NoRestart `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Host "[APPLIED] $($Adapter.Name) :: *EEE = 0 (Energy Efficient Ethernet disabled)"
        }
        catch {
            Write-Warning "Failed to disable Energy Efficient Ethernet on '$($Adapter.Name)': $($_.Exception.Message)"
        }
    }

    if ($MatchedAdapters -eq 0) {
        Write-Warning 'No physical network adapter exposed the standardized *EEE property; nothing was changed.'
    }
}

function Clear-AccessibilityHotkeyFlag {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path
    )

    # StickyKeys/FilterKeys both use bit 0x4 for HOTKEYACTIVE.
    # Clear only that bit and preserve every other current accessibility flag.
    $State = Get-RegistryValueState -Path $Path -Name 'Flags'
    if (-not $State.Exists) {
        Write-Warning "Accessibility Flags value not found; skipped: $Path"
        return
    }

    $CurrentRaw = $State.Value

    $CurrentFlags = 0
    if (-not [int]::TryParse([string]$CurrentRaw, [ref]$CurrentFlags)) {
        Write-Warning "Unrecognized accessibility Flags value '$CurrentRaw'; skipped: $Path"
        return
    }

    $NewFlags = $CurrentFlags -band (-bnot 0x4)
    if ($NewFlags -eq $CurrentFlags) {
        return
    }

    Set-RegistryString -Path $Path -Name 'Flags' -Value ([string]$NewFlags)
}

function Disable-DefaultRenderAudioEnhancements {
    [CmdletBinding()]
    param ()

    # PKEY_AudioEndpoint_Disable_SysFx is the documented master switch for
    # endpoint system effects/APOs in shared mode. Use Core Audio's endpoint
    # property store instead of editing MMDevices registry implementation data.
    if (-not ('Cs2GamingBaselineV100.AudioEndpointEffects' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Cs2GamingBaselineV100
{
    internal enum EDataFlow
    {
        eRender = 0,
        eCapture = 1,
        eAll = 2
    }

    internal enum ERole
    {
        eConsole = 0,
        eMultimedia = 1,
        eCommunications = 2
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;

        public PROPERTYKEY(Guid formatId, uint propertyId)
        {
            fmtid = formatId;
            pid = propertyId;
        }
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    internal struct PROPVARIANT
    {
        [FieldOffset(0)]
        public ushort vt;

        [FieldOffset(8)]
        public uint uintValue;

        public static PROPVARIANT FromUInt32(uint value)
        {
            PROPVARIANT result = new PROPVARIANT();
            result.vt = 19; // VT_UI4
            result.uintValue = value;
            return result;
        }
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-C0A9E7B6A5AF")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
    }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig]
        int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IMMDeviceCollection devices);

        [PreserveSig]
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice device);

        [PreserveSig]
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);

        [PreserveSig]
        int RegisterEndpointNotificationCallback(IntPtr client);

        [PreserveSig]
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, uint classContext, IntPtr activationParams, out IntPtr interfacePointer);

        [PreserveSig]
        int OpenPropertyStore(uint accessMode, out IPropertyStore properties);

        [PreserveSig]
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);

        [PreserveSig]
        int GetState(out uint state);
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig]
        int GetCount(out uint propertyCount);

        [PreserveSig]
        int GetAt(uint index, out PROPERTYKEY key);

        [PreserveSig]
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);

        [PreserveSig]
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);

        [PreserveSig]
        int Commit();
    }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject
    {
    }

    public sealed class AudioEndpointResult
    {
        public string EndpointId { get; set; }
        public bool Changed { get; set; }
    }

    public static class AudioEndpointEffects
    {
        private const uint STGM_READWRITE = 0x00000002;
        private const uint ENDPOINT_SYSFX_DISABLED = 1;
        private const ushort VT_UI4 = 19;

        public static AudioEndpointResult EnsureDefaultRenderEndpointDisabled(int roleValue)
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IPropertyStore store = null;

            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());

                int hr = enumerator.GetDefaultAudioEndpoint(
                    EDataFlow.eRender,
                    (ERole)roleValue,
                    out device);
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                string endpointId;
                hr = device.GetId(out endpointId);
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                hr = device.OpenPropertyStore(STGM_READWRITE, out store);
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                PROPERTYKEY disableSysFx = new PROPERTYKEY(
                    new Guid("1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E"),
                    5);

                PROPVARIANT current;
                hr = store.GetValue(ref disableSysFx, out current);
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                if (current.vt == VT_UI4 && current.uintValue == ENDPOINT_SYSFX_DISABLED)
                {
                    return new AudioEndpointResult
                    {
                        EndpointId = endpointId,
                        Changed = false
                    };
                }

                PROPVARIANT disabled = PROPVARIANT.FromUInt32(ENDPOINT_SYSFX_DISABLED);
                hr = store.SetValue(ref disableSysFx, ref disabled);
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                hr = store.Commit();
                if (hr != 0)
                    Marshal.ThrowExceptionForHR(hr);

                return new AudioEndpointResult
                {
                    EndpointId = endpointId,
                    Changed = true
                };
            }
            finally
            {
                if (store != null && Marshal.IsComObject(store))
                    Marshal.FinalReleaseComObject(store);
                if (device != null && Marshal.IsComObject(device))
                    Marshal.FinalReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator))
                    Marshal.FinalReleaseComObject(enumerator);
            }
        }
    }
}
'@
    }

    $ConfiguredEndpoints = New-Object 'System.Collections.Generic.HashSet[string]'

    # Apply to the default render endpoint for Console, Multimedia and
    # Communications roles. These commonly resolve to the same device; the set
    # only suppresses duplicate log output. Capture/microphone APOs are untouched.
    foreach ($Role in @(0, 1, 2)) {
        try {
            $Result = [Cs2GamingBaselineV100.AudioEndpointEffects]::EnsureDefaultRenderEndpointDisabled($Role)
            if ($ConfiguredEndpoints.Add($Result.EndpointId)) {
                if ($Result.Changed) {
                    Write-Host "[APPLIED] Audio enhancements disabled: $($Result.EndpointId)"
                }
                else {
                    Write-Host "[UNCHANGED] Audio enhancements already disabled: $($Result.EndpointId)"
                }
            }
        }
        catch {
            Write-Warning "Could not disable audio enhancements for render role ${Role}: $($_.Exception.Message)"
        }
    }
}

function Remove-ProvisionedAppxPackageIfPresent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Name
    )

    try {
        $Packages = @(
            Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                Where-Object { $_.DisplayName -eq $Name }
        )
    }
    catch {
        Write-Warning "Could not enumerate provisioned AppX packages while checking '$Name': $($_.Exception.Message)"
        return
    }

    foreach ($Package in $Packages) {
        try {
            Remove-AppxProvisionedPackage `
                -Online `
                -AllUsers `
                -PackageName $Package.PackageName `
                -ErrorAction Stop | Out-Null
            Write-Host "[DEPROVISIONED] AppX: $Name"
        }
        catch {
            Write-Warning "Failed to deprovision AppX '$Name': $($_.Exception.Message)"
        }
    }
}

function Uninstall-OneDriveIfPresent {
    [CmdletBinding()]
    param ()

    $Setup = @(
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($null -ne $Setup) {
        try {
            $Process = Start-Process `
                -FilePath $Setup `
                -ArgumentList '/uninstall' `
                -Wait `
                -PassThru `
                -ErrorAction Stop

            if ($Process.ExitCode -eq 0) {
                Write-Host '[REMOVED] OneDrive'
                return
            }

            Write-Warning "OneDriveSetup.exe returned exit code $($Process.ExitCode); trying WinGet fallback."
        }
        catch {
            Write-Warning "OneDrive native uninstall failed: $($_.Exception.Message); trying WinGet fallback."
        }
    }

    Remove-WinGetPackageIfPresent -Id 'Microsoft.OneDrive'
}

function Remove-CurrentUserAppxPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Name
    )

    try {
        $Packages = @(
            Get-AppxPackage -Name $Name -ErrorAction Stop |
                Where-Object { $_.Name -eq $Name }
        )
    }
    catch {
        Write-Warning "Could not enumerate current-user AppX package '$Name': $($_.Exception.Message)"
        return
    }

    foreach ($Package in $Packages) {
        if ($Package.NonRemovable) {
            Write-Host "[SKIPPED] Non-removable AppX: $Name"
            continue
        }

        try {
            Remove-AppxPackage `
                -Package $Package.PackageFullName `
                -Confirm:$false `
                -ErrorAction Stop
            Write-Host "[REMOVED] AppX: $Name"
        }
        catch {
            Write-Warning "Failed to remove AppX '$Name': $($_.Exception.Message)"
        }
    }
}

function Remove-WinGetPackageIfPresent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Id
    )

    $WinGet = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $WinGet) {
        Write-Warning "WinGet is unavailable; skipped package: $Id"
        return
    }

    & $WinGet.Source list `
        --id $Id `
        --exact `
        --accept-source-agreements `
        --disable-interactivity *> $null

    if ($LASTEXITCODE -ne 0) {
        return
    }

    & $WinGet.Source uninstall `
        --id $Id `
        --exact `
        --silent `
        --accept-source-agreements `
        --disable-interactivity

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[REMOVED] WinGet package: $Id"
    }
    else {
        Write-Warning "WinGet failed to remove package: $Id"
    }
}

try {
    Assert-TargetUserContext
    Assert-TargetEnvironment
    Assert-FaceitBaseline

    # ========================================================================
    # 01 - WINDOWS UI / EXPLORER STANDARDIZATION
    # ========================================================================

    # Format-to-format UX baseline. These values standardize presentation and
    # Explorer behavior only; they do not alter DWM scheduling, visual-effects
    # performance policy, the Themes service, or shell/service topology.
    $PersonalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $ExplorerAdvancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    # Dark Windows shell and dark mode for applications that honor the Windows
    # personalization preference.
    Set-RegistryDword -Path $PersonalizePath -Name 'SystemUsesLightTheme' -Value 0
    Set-RegistryDword -Path $PersonalizePath -Name 'AppsUseLightTheme' -Value 0

    # Use an opaque, consistent shell appearance. This is a visual baseline, not
    # an FPS optimization claim.
    Set-RegistryDword -Path $PersonalizePath -Name 'EnableTransparency' -Value 0
    Set-RegistryDword `
        -Path 'HKCU:\Control Panel\Desktop' `
        -Name 'AutoColorization' `
        -Value 0

    # Keep a deterministic black desktop and block wallpaper replacement while
    # leaving themes and desktop system-icon controls otherwise untouched.
    Set-DesktopWallpaperBlack

    # Preserve centered alignment, Search, Task View and every other taskbar pin.
    # Remove only Edge/Store pins plus the Edge desktop shortcut.
    Remove-EdgeAndStoreShellShortcuts

    # Technical Explorer baseline: show ordinary hidden files and always show
    # extensions, but keep protected operating-system objects hidden to avoid
    # shell/junction/desktop.ini noise. Keep item-selection checkboxes off.
    Set-RegistryDword -Path $ExplorerAdvancedPath -Name 'Hidden' -Value 1
    Set-RegistryDword -Path $ExplorerAdvancedPath -Name 'HideFileExt' -Value 0
    Set-RegistryDword -Path $ExplorerAdvancedPath -Name 'ShowSuperHidden' -Value 0
    Set-RegistryDword -Path $ExplorerAdvancedPath -Name 'AutoCheckSelect' -Value 0

    # Windows 11 already provides Open in Terminal. Remove the custom v1.0.1
    # PowerShell shell verb if this script is being run as an upgrade.
    Remove-LegacyOpenPowerShellHereContextMenu

    # Reduce Start recommendation content without replacing/pinning the Start
    # layout or mutating Explorer's internal binary state.
    Set-RegistryDword `
        -Path $ExplorerAdvancedPath `
        -Name 'Start_IrisRecommendations' `
        -Value 0

    # ========================================================================
    # 02 - CONSUMER BACKGROUND FEATURES
    # ========================================================================

    # Disable Widgets via supported policy; keep runtime/packages installed.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' `
        -Name 'AllowNewsAndInterests' `
        -Value 0

    # Disable dynamic Search Highlights content.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Name 'EnableDynamicContentInWSB' `
        -Value 0

    # Prevent Settings from contacting Microsoft content services for online
    # tips/help. Supported on Windows 11 Pro; this does not alter servicing.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Name 'AllowOnlineTips' `
        -Value 0

    # Disable application toast notifications.
    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' `
        -Name 'NoToastApplicationNotification' `
        -Value 1

    # Dedicated CS2/FACEIT appliance: disable cloud-delivered app notifications.
    # This avoids WNS cloud notification activity while leaving the notification
    # service topology itself intact.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' `
        -Name 'NoCloudApplicationNotification' `
        -Value 1

    # Disable Activity Feed. This single supported policy already prevents apps
    # and Windows from publishing user activities and disables cross-device sync;
    # avoid redundant PublishUserActivities/UploadUserActivities writes.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Name 'EnableActivityFeed' `
        -Value 0

    # Dedicated appliance: prevent Microsoft-account Windows settings from
    # roaming to or from this PC. This blocks cloud state from silently changing
    # the CS2 baseline while preserving local settings and Microsoft-account sign-in.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' `
        -Name 'DisableSettingSync' `
        -Value 2

    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' `
        -Name 'DisableSettingSyncUserOverride' `
        -Value 1

    # Reduce promotional/suggestion content using only Windows 11 Pro-supported
    # Cloud Content policies. Do not use Enterprise-only blanket Spotlight policy.
    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Name 'DisableThirdPartySuggestions' `
        -Value 1

    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Name 'DisableTailoredExperiencesWithDiagnosticData' `
        -Value 1

    # Gaming desktop does not use location or Find My Device.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Name 'DisableLocation' `
        -Value 1

    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' `
        -Name 'AllowFindMyDevice' `
        -Value 0

    # ========================================================================
    # 03 - BACKGROUND APPLICATIONS
    # ========================================================================

    # Prevent Edge preloading at sign-in.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' `
        -Name 'StartupBoostEnabled' `
        -Value 0

    # Prevent Edge background mode after the last browser window closes.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' `
        -Name 'BackgroundModeEnabled' `
        -Value 0

    # This dedicated system does not use Windows Dynamic Lighting. Disable only
    # the current user's orchestration switch; do not disable LampArray HID
    # devices or any other RGB/peripheral controller.
    Set-RegistryDword `
        -Path 'HKCU:\Software\Microsoft\Lighting' `
        -Name 'AmbientLightingEnabled' `
        -Value 0

    # ========================================================================
    # 04 - DIAGNOSTICS / SERVICE TOPOLOGY
    # ========================================================================

    # Keep Windows Search in its stock service configuration. The indexer has
    # built-in activity backoff and is paused by Game Mode; disabling WSearch
    # would change service/search dependency behavior for little gameplay gain.
    # Do not copy Atlas's custom minimal-index crawl-scope rewrite either.

    # Preserve Windows diagnostics/service topology. Force Required diagnostic
    # data only; do not disable DiagTrack, Windows Error Reporting, Compatibility
    # Appraiser or diagnostic scheduled tasks. At Required data level, separate
    # optional dump/log-limiting policies add no useful baseline behavior.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Name 'AllowTelemetry' `
        -Value 1

    # If Logitech's optional Dynamic Lighting integration is installed, stop
    # and disable only its exact LampArray service. Logitech HID/LIGHTSPEED and
    # every other peripheral service/controller remain untouched.
    $LogitechLampArrayService = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name='logi_lamparray_service'" `
        -ErrorAction SilentlyContinue

    if ($null -ne $LogitechLampArrayService) {
        if ([string]$LogitechLampArrayService.State -ne 'Stopped') {
            Stop-Service `
                -Name 'logi_lamparray_service' `
                -ErrorAction Stop
            Write-Host '[APPLIED] Stopped service: logi_lamparray_service'
        }

        if ([string]$LogitechLampArrayService.StartMode -ne 'Disabled') {
            Set-Service `
                -Name 'logi_lamparray_service' `
                -StartupType Disabled `
                -ErrorAction Stop
            Write-Host '[APPLIED] Disabled service: logi_lamparray_service'
        }
    }

    # Game DVR/capture is disabled through user gaming state below. Keep the
    # BcastDVRUserService per-user service template at its stock Manual/triggered
    # configuration rather than hard-disabling service topology.

    # ========================================================================
    # 05 - GAMING
    # ========================================================================

    # Disable Windows Game DVR / app capture. Keep Game Bar/Xbox protocol
    # packages installed but dormant; do not alter URI handlers or servicing.
    Set-RegistryDword `
        -Path 'HKCU:\System\GameConfigStore' `
        -Name 'GameDVR_Enabled' `
        -Value 0

    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' `
        -Name 'AppCaptureEnabled' `
        -Value 0

    # Disable Game Bar activation and controller trigger.
    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' `
        -Name 'VKMToggleGameBar' `
        -Value 0

    Set-RegistryDword `
        -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' `
        -Name 'UseNexusForGameBarEnabled' `
        -Value 0

    # Intentionally leave Game Mode at Windows default / user-selected state.

    # ========================================================================
    # 06 - POWER / BOOT BEHAVIOR
    # ========================================================================

    # Leave Fullscreen Optimizations on Windows stock behavior. Do not write a
    # global GameDVR_FSEBehaviorMode override; regressions should be handled
    # per executable only if CS2 ever demonstrates one.

    # Disable Fast Startup (hybrid shutdown) while preserving hibernation itself.
    Set-RegistryDword `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
        -Name 'HiberbootEnabled' `
        -Value 0

    # ========================================================================
    # 07 - INPUT
    # ========================================================================

    # 1600-DPI desktop baseline:
    # MouseSensitivity=4 corresponds to the classic 3/11 pointer-speed step,
    # giving roughly 0.25x desktop scaling versus the neutral/default 6/11 step.
    # This preserves the intended 400-DPI @ neutral Windows desktop feel while
    # the physical mouse runs at 1600 DPI. CS2 sensitivity remains game-side.
    Set-RegistryString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '4'

    # Disable Windows pointer acceleration / Enhance Pointer Precision.
    Set-RegistryString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'       -Value '0'
    Set-RegistryString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1'  -Value '0'
    Set-RegistryString -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2'  -Value '0'

    # Disable only the activation hotkeys; preserve the rest of the user's
    # accessibility configuration.
    Clear-AccessibilityHotkeyFlag -Path 'HKCU:\Control Panel\Accessibility\StickyKeys'
    Clear-AccessibilityHotkeyFlag -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response'

    # ========================================================================
    # 08 - AUDIO
    # ========================================================================

    # Disable local/global system-effect APOs on the current default playback
    # endpoints. Keep capture/microphone effects untouched for FACEIT voice use.
    Disable-DefaultRenderAudioEnhancements

    # ========================================================================
    # 09 - NETWORK
    # ========================================================================

    # Disable IEEE 802.3az Energy Efficient Ethernet on physical NICs whose
    # installed driver explicitly exposes the standardized *EEE property. This
    # removes PHY low-power-idle transitions at the cost of slightly higher idle
    # power. Keep interrupt moderation, RSS topology, queue counts, affinity,
    # buffers and unrelated NIC properties at vendor/Windows defaults.
    Disable-EnergyEfficientEthernet

    # ========================================================================
    # 10 - UPDATE / DRIVER DELIVERY
    # ========================================================================

    # Windows Update / Store / Delivery Optimization policy is centralized in:
    #   PostFormat-Policy-Baseline-v1.ps1
    #
    # This core CS2 baseline intentionally does NOT exclude Windows Update driver
    # delivery. The policy layer freezes normal OS/security/feature updating while
    # keeping a read-only Windows Update driver-catalog scan every other week.
    # Windows Update, BITS, Update Orchestrator, WaaSMedic and servicing topology
    # remain stock.

    # Prevent device metadata from pulling companion applications automatically.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' `
        -Name 'PreventDeviceMetadataFromNetwork' `
        -Value 1

    # Dedicated appliance: prevent Microsoft Store installs from being pushed to
    # this PC from another device or the Store website.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' `
        -Name 'DisablePushToInstall' `
        -Value 1

    # Do not let Windows automatically archive infrequently used Store apps.
    # This preserves package state without deleting Store/AppX servicing.
    Set-RegistryDword `
        -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx' `
        -Name 'AllowAutomaticAppArchiving' `
        -Value 0

    # ========================================================================
    # 11 - APP CLEANUP
    # ========================================================================

    # Exact-name AppX removal is current-user-only by default. The sole
    # provisioning exception is New Outlook below, using Microsoft's supported
    # deprovisioning path. No WindowsApps ACL or component-store surgery.
    $GamingDebloatAppx = @(
        # Communication / consumer / productivity
        'Clipchamp.Clipchamp',
        'Microsoft.OutlookForWindows',
        'MicrosoftTeams',
        'MSTeams',
        'Microsoft.YourPhone',
        'Microsoft.PowerAutomateDesktop',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.Office.OneNote',
        'Microsoft.Office.Sway',
        'Microsoft.Todos',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.News',
        'Microsoft.BingNews',
        'Microsoft.BingWeather',
        'Microsoft.Windows.DevHome',
        'Microsoft.Copilot',
        'Microsoft.Windows.AIHub',
        'Microsoft.PCManager',
        'Microsoft.M365Companions',

        # Retired / legacy
        'Microsoft.549981C3F5F10',
        'Microsoft.SkypeApp',
        'Microsoft.XboxApp',

        'Microsoft.3DBuilder',
        'Microsoft.Microsoft3DViewer',
        'Microsoft.Print3D',
        'Microsoft.MixedReality.Portal',
        'Microsoft.BingFinance',
        'Microsoft.BingSports',
        'Microsoft.BingTravel',
        'Microsoft.BingFoodAndDrink',
        'Microsoft.BingHealthAndFitness',
        'Microsoft.WindowsMaps',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsSoundRecorder',
        'Microsoft.ZuneVideo',
        'MicrosoftCorporationII.MicrosoftFamily',
        'MicrosoftCorporationII.QuickAssist',

        # Common promotional / third-party provisioned user apps, if present
        'king.com.CandyCrushSaga',
        'king.com.CandyCrushSodaSaga',
        'king.com.BubbleWitch3Saga',
        'BytedancePte.Ltd.TikTok',
        'Facebook.Instagram',
        'FACEBOOK.FACEBOOK',
        'LinkedInforWindows',
        'Amazon.com.Amazon',
        'AmazonVideo.PrimeVideo',
        'Disney.37853FC22B2CE',
        '4DF9E0F8.Netflix'
    )

    foreach ($App in $GamingDebloatAppx) {
        Remove-CurrentUserAppxPackage -Name $App
    }

    # New Outlook is provisioned by current Windows 11 builds. Microsoft
    # explicitly supports deprovisioning it, and current servicing respects this
    # state instead of reinstalling the package after normal Windows updates.
    Remove-ProvisionedAppxPackageIfPresent -Name 'Microsoft.OutlookForWindows'

    # OneDrive is a standalone sync client. Prefer its own Windows-shipped
    # uninstaller and use WinGet only as a fallback; do not delete WinSxS/CBS or
    # residual registry/component-store state by hand.
    Uninstall-OneDriveIfPresent

    # Copilot Store package fallback (the AppX package is also handled above).
    Remove-WinGetPackageIfPresent -Id 'XP9CXNGPPJ97XX'

    # ========================================================================
    # 12 - MEASUREMENT-ONLY CANDIDATES (NOT APPLIED BY DEFAULT)
    # ========================================================================
    # Energy Efficient Ethernet (*EEE) is now part of the production baseline.
    # It is applied above only through the supported NetAdapter advanced-property
    # interface and only when the installed physical NIC explicitly exposes *EEE.
    # Raw class-registry NIC bundles remain intentionally rejected.

    # High Performance versus stock Balanced remains measurement-only. Do not
    # delete Balanced or bundle the test with core-parking, C-state
    # or processor-power-management overrides.

    # RSS processor placement/queue count remain measurement-only. Keep the
    # adapter's entire RSS profile/topology at the fresh vendor-driver default
    # unless ETW shows NIC DPC/ISR work colliding with CS2-critical CPU time; if
    # tested, use Set-NetAdapterRss rather than direct driver-class registry writes.

    # Policy-based DSCP/QoS is also intentionally absent unless the local router
    # is configured to honor the selected DSCP class under actual congestion.

    # WPBT registry overrides are intentionally absent. If a motherboard vendor
    # exposes an explicit UEFI option for automatic utility injection/installation,
    # in UEFI instead of relying on an undocumented Windows registry override.

    # GPU-driver profile notes:
    # - Keep the vendor shader cache enabled. Current driver settings already
    #   default the shader disk cache to ON; do not force Alchemy's Unlimited
    #   cache size just to create a tweak. For this single-game CS2 machine, the
    #   driver default is the baseline unless measurements show cache eviction.
    #   A driver update can invalidate/delete the cache, so first-run stutter after
    #   a driver change is not evidence that Windows scheduling should be tweaked.
    # - Prefer maximum performance remains per-CS2 A/B only, never a global profile
    #   override. Use the game's supported latency-reduction path when later
    #   defining the final CS2 profile instead of stacking broad driver overrides.
    # - Preferred refresh rate = Highest Available is conditional only: useful if
    #   a fixed-refresh CS2 configuration actually selects the wrong rate. It is
    #   redundant/disabled when VRR/G-SYNC controls the refresh policy.
    # - Private GPU-vendor telemetry registry keys and
    #   nvlddmkm\Global\Startup\SendTelemetryData) are intentionally absent.
    #   Their exact driver semantics are not a supported public tuning contract.
    #
    # Alchemy Verified-Tweaks MMCSS notes:
    # - SystemResponsiveness=10 is a real MMCSS setting and is the lowest valid
    #   non-clamped value. It changes the percentage of CPU capacity guaranteed
    #   to low-priority work while MMCSS is scheduling multimedia tasks. Keep the
    #   Windows value STOCK in the thoughtless-run baseline. Only compare 20 vs
    #   10 as a controlled CS2 A/B if CPU saturation/ETW evidence justifies it;
    #   reducing the reserve can delay background dependency work and worsen tails.
    # - Do not use SystemResponsiveness=0: values below 10 are clamped to 20.
    # - MMCSS AlwaysOn/LazyMode/LazyModeTimeout overrides are undocumented for our
    #   supported tuning purposes and are intentionally absent.
    #
    # Other Verified-Tweaks families intentionally NOT carried into production:
    # - D3D11/D3D12 private runtime flags, including unsafe command-buffer reuse
    # - Kernel/DPC queue/watchdog/private scheduler overrides
    # - InterruptSteeringDisabled / Max Pending Interrupt blanket registry blocks
    # - StorNVMe queue/depth/flush registry overrides
    # - NetworkThrottlingIndex overrides
    # - Imported/custom power plans whose full behavior is not source-auditable

    # imribiy/useful-regs-bats notes:
    # - Do not copy GrandmaServices.bat service-disable blocks. Besides being far
    #   broader than this baseline, its sc.exe syntax omits the required space
    #   between an option and value (for example: start= disabled).
    # - Steam Run-key autostart removal is clean but intentionally not enforced by
    #   this baseline: Steam is the required launcher for the only game workload,
    #   and choosing whether it starts at logon or manually is workflow policy,
    #   not an in-match performance requirement.
    # - Global LetAppsRunInBackground=2 remains rejected; unwanted AppX packages
    #   are removed selectively instead of globally denying packaged-app activity.

    # BoringBoredom/PC-Optimization-Hub notes:
    # - Do NOT implement a generic third-party startup/service/driver disable list.
    #   The preferred baseline is prevention: install only the required vendor drivers
    #   and avoid optional control suites/updaters/telemetry/RGB/peripheral packages.
    #   If an optional vendor package is later installed, audit its exact autostarts
    #   (Autoruns is appropriate) and remove/disable only components whose dependency
    #   role is known. Never blanket-disable GPU/chipset/LAN/audio vendor
    #   or FACEIT-related services/drivers merely because they are non-Microsoft.
    # - Unused onboard/PnP devices/controllers are hardware-topology decisions, not a
    #   thoughtless-run tweak. Do not call Disable-PnpDevice without an explicit,
    #   verified device InstanceId and confirmed lack of routing/wake dependencies.
    # - USB port/controller placement and mouse polling rate are physical/workload A/B
    #   items. Higher polling can reduce sample age while increasing raw-input/USB work;
    #   choose the highest rate that preserves CS2 frametime tails on this exact setup.
    # - FPS caps are a CS2/Reflex/display-profile decision, not a Windows baseline tweak.
    #   Prefer CS2's supported in-game latency path where available and measure PC latency/frametimes.
    # - xHCI IMOD MMIO writes via RWEverything are intentionally rejected. They bypass
    #   supported Windows tuning interfaces, alter host-controller interrupt behavior,
    #   require a low-level driver/tool, and are especially inappropriate for a FACEIT
    #   baseline. Interrupt moderation overrides remain absent.
    #
    # ChrisTitusTech/winutil notes:
    # - Windows Update / Delivery Optimization / Store auto-update policy is
    #   centralized in PostFormat-Policy-Baseline-v1.ps1. This core baseline
    #   keeps only selective device-metadata/app-state controls; do not duplicate
    #   WinUtil's broader presets here.
    # - DisablePushToInstall=1 is carried above as a supported Windows 11 Pro
    #   drift-prevention policy. It blocks remote/web Store pushes without removing
    #   Microsoft Store or changing AppX servicing.
    # - Keep Game Mode at fresh-Windows/user state instead of forcing registry
    #   values just to mirror WinUtil's toggle. IPv4 preference remains problem-
    #   specific only; Enterprise-only consumer-content policy is not used on Pro.
    # - Do not copy WinUtil ISO Creator's service/task deletion, fake WSUS, BITS/
    #   WaaSMedic/UsoSvc disable, broad provisioned-AppX sweep or component hacks.
    #
    # Atlas OS notes:
    # - Keep WSearch/service topology stock. Atlas's minimal-index configuration
    #   is preferable to killing Search on a general gaming PC, but this script
    #   does not need to rewrite index crawl scope because Windows already backs
    #   indexing off under activity/Game Mode.
    # - AUOptions/deferral/pause-date controls are intentionally absent here.
    #   The separate policy layer freezes normal OS/security/feature updating
    #   while retaining a read-only driver-catalog scan every other week.
    # - AllowAutomaticAppArchiving=0 is carried above through the documented
    #   App Package Deployment policy to prevent automatic app-state changes.
    # - Atlas global background-app deny, FTH disable, service-host regrouping,
    #   MMCSS=10, Win32PrioritySeparation and driver-registry network bundle are
    #   intentionally absent.
    #
    # ReviOS / meetrevision notes:
    # - Delivery Optimization HTTP-only/no-peering and Fast Startup OFF are
    #   already applied above; do not duplicate their broader update/hibernate
    #   bundles.
    # - TCP congestion-provider reset is intentionally absent on a stock install.
    #   Do not cargo-cult BBR/BBR2/CUBIC overrides for CS2; leave Windows TCP
    #   profile selection stock unless a prior custom provider is actually found.
    # - Fullscreen Optimizations remain stock globally. Do not use raw global
    #   FSO disable keys; only per-game compatibility testing can justify a change.
    # - ReviOS service grouping, memory-compression disable, CBS removal packages,
    #   AppxAllUserStore lifecycle registry edits and forced non-removable-policy
    #   changes are intentionally not carried into this baseline.
    # - Recall is not modified by default. On systems where Recall is present and
    #   unwanted, use the supported Windows Optional Features/policy path rather
    #   than AI/CBS component stripping.

    # ========================================================================
    # 13 - INTENTIONALLY PRESERVED
    # ========================================================================
    # - Current-user targeting is guarded against elevation under a different
    #   administrator account; HKCU/AppX changes must hit the gaming user profile.
    # - Microsoft Store / DesktopAppInstaller
    # - Game Bar/Xbox protocol packages and Gaming Services infrastructure
    # - AppX deployment framework needed for Windows servicing
    # - WebView2 / Windows App Runtime / VCLibs / UI.Xaml frameworks
    # - Defender / Security Center service topology; protection policy is handled by PostFormat-Policy-Baseline-v1.ps1
    # - DiagTrack / Windows Error Reporting service topology; diagnostic data is policy-limited
    # - Compatibility Appraiser / diagnostic / CEIP scheduled-task topology
    # - BcastDVRUserService service template (capture state disabled above)
    # - SysMain / Prefetch / Memory Compression
    # - Windows Update services / BITS / WaaSMedic / UsoSvc
    # - OneSettings / Services Configuration downloads (Windows dynamic configuration)
    # - Game Mode
    # - Processor Scheduling / Win32PrioritySeparation (stock Programs/default)
    # - Virtual memory/pagefile policy (stock system-managed/default)
    # - Secure Boot / TPM / SVM / IOMMU / VBS / HVCI security chain
    # - Audio capture/microphone APO configuration
    # - CPU idle states / core parking / SMT
    # - Timer / HPET / BCD timekeeping behavior remains untouched at fresh-stock defaults
    # - MSI/IRQ affinity / XHCI IMOD / ResourcePolicyStore tweaks
    # - UX standardization above is intentionally limited to documented/user-shell
    #   state; no visual-effects performance preset or DWM composition hack is used.

    Write-Host ''
    Write-Host '[DONE] Dedicated Steam / Counter-Strike 2 / FACEIT baseline applied.' -ForegroundColor Green
    Write-Host 'Restart Windows before benchmarking or treating this state as a baseline.'
    Write-Warning 'Windows update/security policy is finalized by PostFormat-Policy-Baseline-v1.ps1. Refresh this dedicated image by clean-format when you intentionally move to a newer Windows/security baseline; FACEIT can reject an out-of-date Windows security state.'
    Write-Host "Log: $LogFile"
}
finally {
    Stop-Transcript | Out-Null
}
