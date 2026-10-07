#requires -Version 5.1
<#
.SYNOPSIS
  Post-format online driver installer for this gaming PC.

.DESCRIPTION
  Downloads the CURRENT official driver baseline at run time and installs only
  the driver families intentionally selected for this machine. This is a
  review build; validate Audit and the install result on the target PC.

  Selected:
    - AMD B850 chipset driver from AMD
    - Intel I226-V LAN driver from the ASUS ROG STRIX B850-I support page
    - Realtek UCM driver from the ASUS motherboard support page, if matching hardware exists
    - AMD iGPU latest WHQL Recommended graphics package from AMD, extracted and
      installed as matching display INF only (no Adrenalin UI). If Windows tar
      cannot read AMD's SFX archive, the script falls back to the latest ASUS
      motherboard OEM VGA ZIP and still installs only the matching display INF.
    - NVIDIA RTX 3080 12GB (DEV_220A) latest WHQL Game Ready driver from NVIDIA,
      extracted before running the documented setup.exe Display.Driver-only
      installation (no NVIDIA App / HD Audio package selection)

  Intentionally NOT installed:
    - MediaTek Wi-Fi
    - Bluetooth
    - Realtek ALC4080 / Realtek USB audio
    - Armoury Crate / RGB software
    - NVIDIA App
    - AMD Adrenalin UI

  IMPORTANT:
    Provider/version checks happen BEFORE each installer call.
    If the exact current official provider/version is already bound and the
    device reports problem code 0, installation is skipped. PnPUtil success
    is not considered sufficient unless the target device is verified bound.
    This script never performs DDU, Driver Store purges, or forced downgrades.

  The script is designed for a clean-format workflow, not for maintaining an old
  Windows image indefinitely.

.PARAMETER Mode
  Install (default) or Audit.

  Audit resolves current official versions and inspects installed state, but does
  not install anything. It writes logs/cache, downloads selected packages and
  checks their hashes/signatures and extractability before Install mode.

.NOTES
  ASUS download-page parsing is intentionally fail-closed. If ASUS changes its
  support-page structure and the script cannot uniquely resolve an official
  dlcdnets.asus.com package + version + SHA-256, it stops instead of guessing.

  NVIDIA lookup uses NVIDIA's own driver-search backend used by the official
  driver-download workflow for GeForce RTX 30 Series / RTX 3080.
#>

[CmdletBinding()]
param(
    [ValidateSet('Install','Audit')]
    [string]$Mode = 'Install'
)

# ============================================================================
# ELEVATION / HOST
# ============================================================================

function Test-IsAdministratorToken {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$needsDesktopPS = ($PSVersionTable.PSEdition -ne 'Desktop')
$needs64Bit = (-not [Environment]::Is64BitProcess)
$needsAdmin = (-not (Test-IsAdministratorToken))

if ($needsDesktopPS -or $needs64Bit -or $needsAdmin) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Launch this script from its .ps1 file.'
    }

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $psExe = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $argLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1}' -f $PSCommandPath,$Mode

    $elevated = Start-Process `
        -FilePath $psExe `
        -ArgumentList $argLine `
        -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ErrorAction Stop
    exit $elevated.ExitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:WebSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$ScriptVersion = '2.3.4'
$ScriptRoot = Split-Path -Parent $PSCommandPath
$NvidiaTargetHardwareRegex = '^PCI\\VEN_10DE&DEV_220A(?:&|$)'

# ZOWIE's support page is client-rendered and does not expose a stable,
# documented machine-readable download API. The current official XL2566X+
# monitor package is therefore carried locally with this installer instead of
# using brittle page scraping. Its package hash is checked before extraction.
$MonitorPackageRelativePath = 'Assets\Monitor\XL2566X+_WHQL dirver_V001_Windows_240605180238.7z'
$MonitorPackagePath = Join-Path $ScriptRoot $MonitorPackageRelativePath
$MonitorPackageSha256 = 'E8B600BE155F85BA417BEE80EAE6065848885F9E72A331B19D17D53FD9751D38'
$MonitorPackageLabel = 'ZOWIE XL2566X+ V001 / 1.0 WHQL'

$AsusSupportUrl = 'https://www.asus.com/us/supportonly/rog%20strix%20b850-i%20gaming%20wifi/helpdesk_download/'
$AmdChipsetPage = 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/b850.html'
$AmdIgpuPage = 'https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-9000-series/amd-ryzen-7-9800x3d.html'
$NvidiaLookupBase = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php'

$Root = Join-Path $env:ProgramData 'GamingDriverInstaller'
$DownloadRoot = Join-Path $Root 'Downloads'
$ExtractRoot = Join-Path $Root 'Extracted'
$LogRoot = Join-Path $Root 'Logs'
$BootstrapGuardStatePath = Join-Path $Root 'DriverBootstrapGuardState.json'

foreach ($dir in @($Root,$DownloadRoot,$ExtractRoot,$LogRoot)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$LogFile = Join-Path $LogRoot ("driver-install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Force | Out-Null

$script:Installed = 0
$script:Skipped = 0
$script:WouldInstall = 0
$script:Failures = 0
$script:RebootRecommended = $false
$script:VerifiedDownloads = @{}
$script:StepResults = @()
$script:OfficialPages = @{}
$script:NvidiaLatest = $null
$script:BootstrapGuardActive = $false
$script:BootstrapGuardSnapshot = @()

# ============================================================================
# GENERIC HELPERS
# ============================================================================

function Write-Section {
    param([Parameter(Mandatory)][string]$Name)
    Write-Host ''
    Write-Host ('=' * 64)
    Write-Host (' {0}' -f $Name) -ForegroundColor Cyan
    Write-Host ('=' * 64)
}

function Convert-ToVersionSafe {
    param([string]$Text)
    try { return [version]$Text } catch { return $null }
}

function Compare-VersionText {
    param([string]$Installed,[string]$Target)
    $a = Convert-ToVersionSafe $Installed
    $b = Convert-ToVersionSafe $Target
    if ($null -eq $a -or $null -eq $b) { return $null }
    return $a.CompareTo($b)
}

function Get-OptionalPropertyString {
    param([object]$Record,[Parameter(Mandatory)][string]$Name)

    if ($null -eq $Record) { return '' }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function Get-OfficialPage {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Referer
    )

    if ($script:OfficialPages.ContainsKey($Url)) {
        return $script:OfficialPages[$Url]
    }

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36'
        'Accept'     = 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8'
    }
    if ($Referer) { $headers['Referer'] = $Referer }

    $r = Invoke-WebRequest -Uri $Url -Headers $headers -WebSession $script:WebSession -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop
    if ($r.StatusCode -lt 200 -or $r.StatusCode -ge 300) {
        throw "HTTP $($r.StatusCode) for $Url"
    }

    $content = [Net.WebUtility]::HtmlDecode([string]$r.Content)
    $content = $content.Replace('\/','/').Replace('\u002F','/').Replace('\u0026','&')
    $script:OfficialPages[$Url] = $content
    return $content
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Assert-AuthenticodePublisher {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$PublisherRegex
    )

    $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop

    if ($sig.Status -ne 'Valid') {
        throw "Authenticode signature is not valid for '$Path'. Status: $($sig.Status)"
    }

    $subject = [string]$sig.SignerCertificate.Subject
    if ($subject -notmatch $PublisherRegex) {
        throw "Unexpected signer for '$Path': $subject"
    }

    Write-Host ("Signature  : VALID | {0}" -f $subject)
}

function Download-OfficialFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Referer,
        [string]$ExpectedSha256
    )

    $allowed = @(
        'drivers.amd.com',
        'dlcdnets.asus.com',
        'dlcdnets.asus.com.cn',
        'download.nvidia.com',
        'us.download.nvidia.com',
        'international.download.nvidia.com',
        'uk.download.nvidia.com',
        'de.download.nvidia.com'
    )

    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https') {
        throw "Refusing non-HTTPS download: $Url"
    }
    if ($allowed -notcontains $uri.Host.ToLowerInvariant()) {
        throw "Refusing non-approved download host: $($uri.Host)"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null

    # ASUS supplies an official SHA-256. AMD/NVIDIA do not; for those EXEs,
    # reuse a previous download only after its URL + SHA-256 have been saved
    # following a VALID vendor signature. Callers validate the signature again
    # even when the file came from this cache.
    $cacheRecordPath = "$Destination.source.json"
    if (Test-Path -LiteralPath $Destination) {
        if ($ExpectedSha256) {
            $have = Get-FileSha256 -Path $Destination
            if ($have -eq $ExpectedSha256.ToUpperInvariant()) {
                Write-Host ("[CACHE OK] {0}" -f $Destination)
                return
            }
        }
        else {
            $verified = $null
            if ($script:VerifiedDownloads.ContainsKey($Destination)) {
                $verified = $script:VerifiedDownloads[$Destination]
            }
            elseif (Test-Path -LiteralPath $cacheRecordPath) {
                try {
                    $saved = Get-Content -LiteralPath $cacheRecordPath -Raw -ErrorAction Stop |
                        ConvertFrom-Json -ErrorAction Stop
                    $savedUrl = Get-OptionalPropertyString -Record $saved -Name 'Url'
                    $savedSha = Get-OptionalPropertyString -Record $saved -Name 'Sha256'
                    if ($savedUrl -eq $Url -and $savedSha -match '^[0-9A-Fa-f]{64}$') {
                        $verified = [pscustomobject]@{ Url = $savedUrl; Sha256 = $savedSha }
                    }
                }
                catch {
                    Write-Warning "Ignoring invalid download-cache record: $cacheRecordPath"
                }
            }
            if ($null -ne $verified -and $verified.Url -eq $Url -and
                (Get-FileSha256 -Path $Destination) -eq $verified.Sha256) {
                $script:VerifiedDownloads[$Destination] = $verified
                Write-Host ("[CACHE OK] URL + SHA-256; publisher signature checked next: {0}" -f $Destination)
                return
            }
        }
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    }

    Write-Host ("Downloading : {0}" -f $Url)

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36'
        'Accept'     = '*/*'
    }
    if ($Referer) { $headers['Referer'] = $Referer }

    $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue

    if ($bits -and -not $Referer) {
        Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop
    }
    else {
        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $Destination `
            -Headers $headers `
            -WebSession $script:WebSession `
            -UseBasicParsing `
            -TimeoutSec 1800 `
            -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        throw "Download did not create: $Destination"
    }

    $size = (Get-Item -LiteralPath $Destination).Length
    if ($size -lt 100KB) {
        throw "Downloaded file is unexpectedly small ($size bytes): $Destination"
    }

    $actualSha = Get-FileSha256 -Path $Destination
    Write-Host ("SHA-256    : {0}" -f $actualSha)

    if ($ExpectedSha256 -and $actualSha -ne $ExpectedSha256.ToUpperInvariant()) {
        throw "SHA-256 mismatch for '$Destination'. Expected $ExpectedSha256, got $actualSha"
    }

    $script:VerifiedDownloads[$Destination] = [pscustomobject]@{
        Url = $Url
        Sha256 = $actualSha
    }
}

function Register-SignedDownloadCache {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Url)

    # Invoke ONLY after Assert-AuthenticodePublisher succeeds. A partial or
    # modified sidecar never authorizes an install: the next run checks the
    # source URL, recomputes the payload hash and validates its signer again.
    if (-not $script:VerifiedDownloads.ContainsKey($Path)) {
        throw "No verified download state for: $Path"
    }
    $entry = $script:VerifiedDownloads[$Path]
    if ($entry.Url -ne $Url) {
        throw "Download cache source does not match official URL: $Path"
    }
    $record = [pscustomobject]@{ Url = $entry.Url; Sha256 = $entry.Sha256 }
    $record | ConvertTo-Json -Compress |
        Set-Content -LiteralPath "$Path.source.json" -Encoding UTF8 -Force -ErrorAction Stop
}

function Get-DeviceMatchIds {
    param([Parameter(Mandatory)][string]$InstanceId)

    $ids = @()
    foreach ($key in @('DEVPKEY_Device_HardwareIds', 'DEVPKEY_Device_CompatibleIds')) {
        try {
            $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $key -ErrorAction Stop
            $ids += @($p.Data | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        catch {
            # Some device classes have no compatible-ID property. The hardware
            # IDs remain usable, and a missing property does not identify a driver.
        }
    }

    # Windows can put PCI\VEN_xxxx&DEV_xxxx in Compatible IDs instead of
    # Hardware IDs. Derive only that documented base identity as a fallback
    # when a device property's list is incomplete; never use a vendor-only ID.
    if ($InstanceId -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})(?:&|\\)') {
        $ids += $matches[1]
    }

    return @($ids | Select-Object -Unique)
}

function Get-ProblemCode {
    param([Parameter(Mandatory)][string]$InstanceId)
    try {
        $p = Get-PnpDeviceProperty `
            -InstanceId $InstanceId `
            -KeyName 'DEVPKEY_Device_ProblemCode' `
            -ErrorAction Stop
        if ($null -eq $p.Data) { return 0 }
        return [int]$p.Data
    }
    catch {
        return $null
    }
}

function Get-SignedDriverForDevice {
    param([Parameter(Mandatory)][string]$InstanceId)

    return @(
        Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object {
            [string]::Equals(
                [string]$_.DeviceID,
                $InstanceId,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    ) | Select-Object -First 1
}

function Get-PresentDeviceByHardwareRegex {
    param(
        [Parameter(Mandatory)][string]$HardwareRegex,
        [string]$ClassRegex = '.*'
    )

    $deviceMatches = @()

    foreach ($dev in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if ([string]$dev.Class -notmatch $ClassRegex) { continue }

        $ids = @(Get-DeviceMatchIds -InstanceId ([string]$dev.InstanceId))
        if ($ids.Count -eq 0) { continue }

        if (@($ids | Where-Object { [string]$_ -match $HardwareRegex }).Count -gt 0) {
            $deviceMatches += [pscustomobject]@{
                Device      = $dev
                HardwareIds = $ids
            }
        }
    }

    return @($deviceMatches)
}

function Get-InfText {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $sr = [IO.StreamReader]::new($Path, $true)
        try { return $sr.ReadToEnd() }
        finally { $sr.Dispose() }
    }
    catch {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
    }
}

function Resolve-InfStringToken {
    param([string]$Text,[string]$Value)

    $v = $Value.Trim()
    if ($v -notmatch '^%([^%]+)%$') {
        return $v.Trim('"')
    }

    $token = $matches[1]
    $m = [regex]::Match(
        $Text,
        '(?im)^\s*' + [regex]::Escape($token) +
        '\s*=\s*(?:"(?<quoted>[^"\r\n]*)"|(?<plain>[^;\r\n]*?))\s*(?:;[^\r\n]*)?$'
    )
    if ($m.Success) {
        if ($m.Groups['quoted'].Success) { return $m.Groups['quoted'].Value.Trim() }
        return $m.Groups['plain'].Value.Trim()
    }
    return $v
}

function Get-InfMetadata {
    param([Parameter(Mandatory)][string]$InfPath)

    $text = Get-InfText -Path $InfPath

    $providerRaw = ''
    $providerMatch = [regex]::Match($text, '(?im)^\s*Provider\s*=\s*(.+?)\s*$')
    if ($providerMatch.Success) {
        $providerRaw = $providerMatch.Groups[1].Value.Trim()
    }

    $driverVer = ''
    $driverMatch = [regex]::Match(
        $text,
        '(?im)^\s*DriverVer\s*=\s*[^,\r\n]+,\s*([0-9\.]+)\s*$'
    )
    if ($driverMatch.Success) {
        $driverVer = $driverMatch.Groups[1].Value.Trim()
    }

    [pscustomobject]@{
        Path     = $InfPath
        Provider = Resolve-InfStringToken -Text $text -Value $providerRaw
        Version  = $driverVer
        Text     = $text
    }
}


function Assert-InfCatalogSignature {
    param(
        [Parameter(Mandatory)]$InfMetadata,
        [Parameter(Mandatory)][string]$SearchRoot
    )

    $catalogMatch = [regex]::Match(
        $InfMetadata.Text,
        '(?im)^\s*CatalogFile(?:\.[^=]+)?\s*=\s*"?([^"\r\n]+)"?\s*$'
    )

    if (-not $catalogMatch.Success) {
        throw "INF does not declare a CatalogFile: $($InfMetadata.Path)"
    }

    $catalogName = $catalogMatch.Groups[1].Value.Trim()
    $sameDir = Join-Path (Split-Path -Parent $InfMetadata.Path) $catalogName

    if (Test-Path -LiteralPath $sameDir) {
        $catalogPath = $sameDir
    }
    else {
        $catalogCandidates = @(
            Get-ChildItem -LiteralPath $SearchRoot -Filter $catalogName -File -Recurse -ErrorAction SilentlyContinue
        )

        if ($catalogCandidates.Count -ne 1) {
            throw "Could not uniquely resolve catalog '$catalogName' for INF '$($InfMetadata.Path)'."
        }

        $catalogPath = $catalogCandidates[0].FullName
    }

    $sig = Get-AuthenticodeSignature -LiteralPath $catalogPath -ErrorAction Stop
    if ($sig.Status -ne 'Valid') {
        throw "Driver catalog signature is not valid: '$catalogPath' (status: $($sig.Status))."
    }

    $subject = [string]$sig.SignerCertificate.Subject
    if ($subject -notmatch '(?i)Microsoft Windows Hardware Compatibility Publisher|Microsoft Windows|BenQ|ZOWIE') {
        throw "Unexpected monitor driver catalog signer: $subject"
    }

    Write-Host ("Catalog     : VALID | {0}" -f $subject)
    return $catalogPath
}

function Find-MatchingInf {
    param(
        [Parameter(Mandatory)][string]$RootFolder,
        [Parameter(Mandatory)][string[]]$HardwareIds
    )

    $found = @()

    foreach ($inf in @(Get-ChildItem -LiteralPath $RootFolder -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)) {
        $meta = Get-InfMetadata -InfPath $inf.FullName
        if ([string]::IsNullOrWhiteSpace($meta.Version)) { continue }

        # Only a model entry can bind a device. A hardware ID in a comment,
        # string table or unrelated directive is not sufficient evidence.
        $modelLines = @($meta.Text -split '\r?\n' | Where-Object {
            $_ -match '^\s*[^;\[\]\r\n=]+\s*=\s*[^;\r\n,]+,'
        })
        foreach ($id in $HardwareIds) {
            $modelPattern = '(?i)^\s*[^;\[\]\r\n=]+\s*=\s*[^;\r\n,]+,\s*"?' +
                [regex]::Escape([string]$id) + '"?\s*(?:,|;|$)'
            if (@($modelLines | Where-Object { $_ -match $modelPattern }).Count -gt 0) {
                $found += $meta
                break
            }
        }
    }

    if ($found.Count -eq 0) { return $null }

    if ($found.Count -gt 1) {
        throw ("Several INFs contain a matching model entry; refusing to guess: {0}" -f
            (($found | ForEach-Object { $_.Path }) -join '; '))
    }
    return $found[0]
}

function Expand-ZipFresh {
    param([Parameter(Mandatory)][string]$Zip,[Parameter(Mandatory)][string]$Destination)

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
}

function Invoke-PnpInstall {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)]$DeviceRecord,
        [Parameter(Mandatory)]$TargetInf,
        [Parameter(Mandatory)][string]$ExpectedProviderRegex
    )

    Write-Host ("[INSTALL] {0}" -f $DisplayName)
    $output = & "$env:windir\System32\pnputil.exe" /add-driver "$($TargetInf.Path)" /install 2>&1
    $rc = $LASTEXITCODE

    foreach ($line in @($output)) {
        Write-Host ('          {0}' -f [string]$line)
    }

    if ($rc -ne 0) {
        throw "PnPUtil failed for '$DisplayName' (exit $rc)."
    }
    $script:RebootRecommended = $true

    # Exit 0 can mean the INF was only staged: Windows still applies PnP
    # ranking. Never report success until the intended device is bound. Fresh
    # Windows can take longer than a few seconds to settle device state, so give
    # SetupAPI/PnP up to one minute before declaring a binding failure.
    Invoke-PnpRescanBestEffort
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $state = Test-PreInstallExact -DeviceRecord $DeviceRecord `
            -TargetInf $TargetInf -ExpectedProviderRegex $ExpectedProviderRegex -Quiet
        if ($state.Exact) {
            Write-Host ("[VERIFIED] {0}: {1} / {2} / {3}" -f
                $DeviceRecord.Device.InstanceId,$state.InstalledProvider,
                $state.InstalledVersion,$state.InstalledInf)
            $script:Installed++
            return
        }
        if ($attempt -lt 30) { Start-Sleep -Seconds 2 }
    }
    throw "PnPUtil completed, but '$DisplayName' did not bind to the expected device/driver within 60 seconds. Check PnP ranking or reboot and audit; no successful install is claimed."
}

function Test-PreInstallExact {
    param(
        [Parameter(Mandatory)]$DeviceRecord,
        [Parameter(Mandatory)]$TargetInf,
        [string]$ExpectedProviderRegex,
        [switch]$Quiet
    )

    $dev = $DeviceRecord.Device
    $installed = Get-SignedDriverForDevice -InstanceId ([string]$dev.InstanceId)

    $installedProvider = if ($installed) { [string]$installed.DriverProviderName } else { '' }
    $installedVersion  = if ($installed) { [string]$installed.DriverVersion } else { '' }
    $installedInf      = if ($installed) { [string]$installed.InfName } else { '' }
    $problemCode       = Get-ProblemCode -InstanceId ([string]$dev.InstanceId)

    if (-not $Quiet) {
        Write-Host ("Device              : {0}" -f $dev.FriendlyName)
        Write-Host ("Instance ID         : {0}" -f $dev.InstanceId)
        Write-Host ("Installed provider  : {0}" -f $(if ($installedProvider) {$installedProvider} else {'NONE'}))
        Write-Host ("Installed version   : {0}" -f $(if ($installedVersion) {$installedVersion} else {'NONE'}))
        Write-Host ("Installed INF       : {0}" -f $(if ($installedInf) {$installedInf} else {'NONE'}))
        Write-Host ("Problem code        : {0}" -f $(if ($null -eq $problemCode) {'N/A'} else {$problemCode}))
        Write-Host ("Current target prov.: {0}" -f $TargetInf.Provider)
        Write-Host ("Current target ver. : {0}" -f $TargetInf.Version)
        Write-Host ("Current target INF  : {0}" -f $TargetInf.Path)
    }

    $providerExact = $false

    if ($ExpectedProviderRegex) {
        $providerExact = (
            $installedProvider -match $ExpectedProviderRegex -and
            $TargetInf.Provider -match $ExpectedProviderRegex
        )
    }
    else {
        $providerExact = (
            $installedProvider -and
            $TargetInf.Provider -and
            [string]::Equals(
                $installedProvider.Trim(),
                $TargetInf.Provider.Trim(),
                [StringComparison]::OrdinalIgnoreCase
            )
        )
    }

    # Win32_PnPSignedDriver can normalize leading zeros (for example an INF
    # DriverVer 2.3.8.021 may be reported by Windows as 2.3.8.21).
    $versionExact = $false
    if ($installedVersion -and $TargetInf.Version) {
        $versionComparison = Compare-VersionText -Installed $installedVersion -Target $TargetInf.Version
        $versionExact = ($null -ne $versionComparison -and $versionComparison -eq 0)
    }
    $healthy = ($null -ne $problemCode -and $problemCode -eq 0)

    return [pscustomobject]@{
        Exact             = ($providerExact -and $versionExact -and $healthy)
        InstalledProvider = $installedProvider
        InstalledVersion  = $installedVersion
        InstalledInf      = $installedInf
        ProblemCode       = $problemCode
    }
}

# ============================================================================
# FRESH-INSTALL WINDOWS UPDATE / DRIVER GUARD
# ============================================================================

function Get-BootstrapRegistryDwordSnapshot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Path = $Path; Name = $Name; Exists = $false; Value = $null
        }
    }

    $props = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $property = $props.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return [pscustomobject]@{
            Path = $Path; Name = $Name; Exists = $false; Value = $null
        }
    }

    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    $kind = $key.GetValueKind($Name)
    if ($kind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw "Refusing to overwrite non-DWORD bootstrap policy '$Path\\$Name' (type: $kind)."
    }

    return [pscustomobject]@{
        Path = $Path; Name = $Name; Exists = $true; Value = [int]$property.Value
    }
}

function Set-BootstrapRegistryDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Save-DriverBootstrapSnapshot {
    param([Parameter(Mandatory)][object[]]$Snapshot)

    $Snapshot |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $BootstrapGuardStatePath -Encoding UTF8 -Force -ErrorAction Stop
}

function Read-DriverBootstrapSnapshot {
    if (-not (Test-Path -LiteralPath $BootstrapGuardStatePath)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $BootstrapGuardStatePath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Bootstrap guard state file is empty: $BootstrapGuardStatePath"
    }

    return @(ConvertFrom-Json -InputObject $raw -ErrorAction Stop)
}

function Test-BootstrapSnapshotEntry {
    param([Parameter(Mandatory)]$Entry)

    $current = Get-BootstrapRegistryDwordSnapshot -Path ([string]$Entry.Path) -Name ([string]$Entry.Name)
    if ([bool]$Entry.Exists) {
        return ($current.Exists -and [int]$current.Value -eq [int]$Entry.Value)
    }
    return (-not $current.Exists)
}

function Restore-DriverBootstrapGuard {
    param([string]$Reason = 'cleanup')

    $snapshot = @($script:BootstrapGuardSnapshot)
    if ($snapshot.Count -eq 0) {
        $snapshot = @(Read-DriverBootstrapSnapshot)
    }
    if ($snapshot.Count -eq 0) {
        throw 'No saved driver-bootstrap policy snapshot is available for restoration.'
    }

    foreach ($entry in $snapshot) {
        $path = [string]$entry.Path
        $name = [string]$entry.Name
        if ([bool]$entry.Exists) {
            Set-BootstrapRegistryDword -Path $path -Name $name -Value ([int]$entry.Value)
        }
        elseif (Test-Path -LiteralPath $path) {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
        }
    }

    $bad = @($snapshot | Where-Object { -not (Test-BootstrapSnapshotEntry -Entry $_) })
    if ($bad.Count -gt 0) {
        $names = ($bad | ForEach-Object { "{0}\\{1}" -f $_.Path,$_.Name }) -join ', '
        throw "Temporary driver-bootstrap policies did not restore to their pre-run state: $names"
    }

    Remove-Item -LiteralPath $BootstrapGuardStatePath -Force -ErrorAction SilentlyContinue
    $script:BootstrapGuardActive = $false
    $script:BootstrapGuardSnapshot = @()
    Write-Host ("[RESTORED] Temporary Windows Update / PnP driver policies ({0})." -f $Reason) -ForegroundColor Green
}

function Recover-StaleDriverBootstrapGuard {
    if (-not (Test-Path -LiteralPath $BootstrapGuardStatePath)) {
        return
    }

    Write-Warning "A previous driver-bootstrap guard state file was found. Restoring the saved pre-run driver policies before continuing: $BootstrapGuardStatePath"
    $script:BootstrapGuardSnapshot = @(Read-DriverBootstrapSnapshot)
    $script:BootstrapGuardActive = $true
    Restore-DriverBootstrapGuard -Reason 'stale-state recovery'
}

function Ensure-DriverBootstrapGuard {
    # This is intentionally policy-only. Windows Update / BITS / servicing
    # services are left at their stock topology. The guard exists only to stop
    # Windows Update / PnP from racing the vendor-driver baseline while large
    # official packages are being downloaded and inspected.
    #
    # The three driver-specific values are temporary and are snapshotted before
    # mutation. They are restored to their exact pre-run state after success OR
    # failure. NoAutoUpdate=1 is intentionally retained as part of this PC's
    # separate update policy baseline.
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $wuAuPath = Join-Path $wuPath 'AU'
    $driverSearchPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'

    Recover-StaleDriverBootstrapGuard

    foreach ($path in @($wuPath,$wuAuPath,$driverSearchPath)) {
        New-Item -Path $path -Force | Out-Null
    }

    $script:BootstrapGuardSnapshot = @(
        Get-BootstrapRegistryDwordSnapshot -Path $wuPath -Name 'ExcludeWUDriversInQualityUpdate'
        Get-BootstrapRegistryDwordSnapshot -Path $driverSearchPath -Name 'SearchOrderConfig'
        Get-BootstrapRegistryDwordSnapshot -Path $driverSearchPath -Name 'DontSearchWindowsUpdate'
    )
    Save-DriverBootstrapSnapshot -Snapshot $script:BootstrapGuardSnapshot
    $script:BootstrapGuardActive = $true

    Set-BootstrapRegistryDword -Path $wuAuPath -Name 'NoAutoUpdate' -Value 1
    Set-BootstrapRegistryDword -Path $wuPath -Name 'ExcludeWUDriversInQualityUpdate' -Value 1

    # Microsoft maps both policies below to
    # Software\Policies\Microsoft\Windows\DriverSearching. SearchOrderConfig=0
    # selects "Do not search Windows Update"; DontSearchWindowsUpdate=1 is the
    # older policy kept during bootstrap for compatibility with older components.
    Set-BootstrapRegistryDword -Path $driverSearchPath -Name 'SearchOrderConfig' -Value 0
    Set-BootstrapRegistryDword -Path $driverSearchPath -Name 'DontSearchWindowsUpdate' -Value 1

    $noAuto = (Get-ItemProperty -Path $wuAuPath -Name 'NoAutoUpdate' -ErrorAction Stop).NoAutoUpdate
    $exclude = (Get-ItemProperty -Path $wuPath -Name 'ExcludeWUDriversInQualityUpdate' -ErrorAction Stop).ExcludeWUDriversInQualityUpdate
    $search = (Get-ItemProperty -Path $driverSearchPath -Name 'SearchOrderConfig' -ErrorAction Stop).SearchOrderConfig
    $legacy = (Get-ItemProperty -Path $driverSearchPath -Name 'DontSearchWindowsUpdate' -ErrorAction Stop).DontSearchWindowsUpdate

    if ($noAuto -ne 1 -or $exclude -ne 1 -or $search -ne 0 -or $legacy -ne 1) {
        throw 'Temporary Windows Update / driver-search bootstrap guard did not verify.'
    }

    Write-Host '[BOOTSTRAP GUARD] Automatic Windows Update disabled.' -ForegroundColor Green
    Write-Host '[BOOTSTRAP GUARD] Windows Update driver delivery excluded.' -ForegroundColor Green
    Write-Host '[BOOTSTRAP GUARD] PnP Windows Update driver search blocked.' -ForegroundColor Green
    Write-Host ("[BOOTSTRAP GUARD] Pre-run driver policy state saved: {0}" -f $BootstrapGuardStatePath)
}

function Finalize-DriverBootstrapGuard {
    # Only called after ALL selected driver steps have succeeded. Restore the
    # temporary driver-specific values to exactly what existed before this run.
    # Automatic Windows Update remains disabled by design.
    $wuAuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

    Write-Section 'FINALIZE DRIVER BOOTSTRAP'
    Restore-DriverBootstrapGuard -Reason 'successful 6/6 verification'

    $noAuto = $null
    if (Test-Path -LiteralPath $wuAuPath) {
        $props = Get-ItemProperty -Path $wuAuPath -ErrorAction Stop
        if ($null -ne $props.PSObject.Properties['NoAutoUpdate']) {
            $noAuto = [int]$props.NoAutoUpdate
        }
    }

    if ($noAuto -ne 1) {
        throw 'NoAutoUpdate=1 was expected to remain enabled after driver bootstrap finalization.'
    }

    Write-Host '[KEPT] Automatic Windows Update disabled (NoAutoUpdate=1).' -ForegroundColor Green
}

function Invoke-PnpRescanBestEffort {
    try {
        & "$env:windir\System32\pnputil.exe" /scan-devices *> $null
    }
    catch {
        # Verification below is authoritative; a scan request failure is only
        # diagnostic and does not itself prove the driver install failed.
    }
}

# ============================================================================
# OFFICIAL ONLINE RESOLVERS
# ============================================================================

function Resolve-AmdChipsetLatest {
    $html = Get-OfficialPage -Url $AmdChipsetPage

    $m = [regex]::Match(
        $html,
        '(?is)AMD\s+Chipset\s+Drivers.*?Revision\s+Number\s*.*?([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*?Release\s+Date'
    )

    if (-not $m.Success) {
        throw 'Could not resolve current AMD B850 chipset version from AMD.'
    }

    $version = $m.Groups[1].Value

    $urlMatch = [regex]::Match(
        $html,
        '(?i)https://drivers\.amd\.com/[^"''<>\s]+AMD_Chipset_Software_' +
        [regex]::Escape($version) +
        '\.exe'
    )

    if (-not $urlMatch.Success) {
        throw "AMD did not publish a direct chipset download link for version $version on its B850 page."
    }
    $url = $urlMatch.Value

    return [pscustomobject]@{
        Name    = 'AMD B850 Chipset'
        Version = $version
        Url     = $url
        Referer = $AmdChipsetPage
    }
}

function Resolve-AsusPackage {
    param(
        [Parameter(Mandatory)][string]$TitleRegex
    )

    $html = Get-OfficialPage -Url $AsusSupportUrl

    # The ASUS support page serializes each package as a compact record:
    # "filename.zip","version","title",...,"/pub/ASUS/.../filename.zip",...,"SHA256"
    # The visible title/version panel has no download URL next to it. Bind all
    # four fields to ONE record, never a window that can cross package boundaries.
    $recordPattern = '(?is)"(?<file>[^"/\\\r\n]+\.zip)","(?<ver>[0-9][0-9A-Za-z\.\-_]{1,40})",' +
        '"(?<title>[^"\r\n]{3,300})"(?<tail>(?:(?!\{"Id":).){0,2000})'
    $records = @()

    foreach ($entry in [regex]::Matches($html, $recordPattern)) {
        if ($entry.Groups['title'].Value -notmatch $TitleRegex) { continue }

        $version = $entry.Groups['ver'].Value
        if ($null -eq (Convert-ToVersionSafe -Text $version)) {
            throw "ASUS package version is not numeric: '$version' for $TitleRegex"
        }

        $tail = $entry.Groups['tail'].Value
        $paths = @([regex]::Matches($tail, '(?i)"(?<path>/pub/ASUS/[^"\r\n]+\.zip)"') |
            ForEach-Object { $_.Groups['path'].Value } | Select-Object -Unique)
        $hashes = @([regex]::Matches($tail, '(?i)"(?<hash>[A-F0-9]{64})"') |
            ForEach-Object { $_.Groups['hash'].Value.ToUpperInvariant() } | Select-Object -Unique)
        $filename = @($entry.Groups['file'].Value -split '@')[-1]
        $valid = ($paths.Count -eq 1 -and $hashes.Count -eq 1)
        if ($valid) {
            $valid = [string]::Equals([IO.Path]::GetFileName($paths[0]),
                $filename, [StringComparison]::OrdinalIgnoreCase)
        }
        $sha = if ($hashes.Count -eq 1) { $hashes[0] } else { '' }
        $url = if ($paths.Count -eq 1) { 'https://dlcdnets.asus.com' + $paths[0] } else { '' }

        $records += [pscustomobject]@{
            Version = $version
            Sha256  = $sha
            Url     = $url
            Valid   = $valid
        }
    }

    if ($records.Count -eq 0) {
        throw "No complete ASUS package record found for: $TitleRegex"
    }

    $sorted = @($records | Sort-Object -Property @{Expression = { [version]$_.Version }} -Descending)
    $latest = $sorted[0]
    foreach ($candidate in @($sorted | Where-Object { $_.Version -eq $latest.Version })) {
        if (-not $candidate.Valid -or $candidate.Url -ne $latest.Url -or
            $candidate.Sha256 -ne $latest.Sha256) {
            throw "Latest ASUS package version $($latest.Version) is incomplete or ambiguous for '$TitleRegex'."
        }
    }

    return [pscustomobject]@{
        Version = $latest.Version
        Sha256  = $latest.Sha256
        Url     = $latest.Url
        Referer = $AsusSupportUrl
    }
}


function Resolve-AmdIgpuRecommendedLatest {
    $html = Get-OfficialPage -Url $AmdIgpuPage

    $m = [regex]::Match(
        $html,
        '(?is)Adrenalin\s+([0-9]+\.[0-9]+\.[0-9]+)\s*\(WHQL\s+Recommended\)'
    )

    if (-not $m.Success) {
        throw 'Could not resolve AMD WHQL Recommended graphics version for Ryzen 7 9800X3D.'
    }

    $version = $m.Groups[1].Value

    $urls = @(
        [regex]::Matches(
            $html,
            '(?i)https://drivers\.amd\.com/[^"''<>\s]+\.exe'
        ) |
        ForEach-Object { $_.Value } |
        Where-Object {
            $_ -match '(?i)whql-amd-software-adrenalin-edition' -and
            $_ -match [regex]::Escape($version)
        } |
        Select-Object -Unique
    )

    if ($urls.Count -eq 0) {
        throw "AMD did not publish a direct WHQL Recommended download link for $version on the 9800X3D page."
    }

    return [pscustomobject]@{
        Version = $version
        Urls    = $urls
        Referer = $AmdIgpuPage
    }
}

function Expand-ArchiveWithWindowsTar {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Destination
    )

    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar)) {
        return $false
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # Current Windows tar is bsdtar/libarchive and supports .7z archives. AMD's
    # package is tested as an archive first; if the SFX wrapper is not readable,
    # caller can use the ASUS OEM VGA fallback instead of guessing.
    & $tar -tf $Archive *> $null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    & $tar -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    return $true
}

function Resolve-NvidiaLatestGameReady {
    if ($null -ne $script:NvidiaLatest) {
        return $script:NvidiaLatest
    }

    # NVIDIA official driver lookup backend:
    # psid=120 => GeForce RTX 30 Series
    # pfid=929 => GeForce RTX 3080 (including the 12GB variant)
    # osID=57  => Windows 10/11 64-bit driver family
    $query = (
        $NvidiaLookupBase +
        '?func=DriverManualLookup' +
        '&psid=120' +
        '&pfid=929' +
        '&osID=57' +
        '&languageCode=1033' +
        '&beta=0' +
        '&isWHQL=1' +
        '&dltype=1' +
        '&dch=1' +
        '&sort1=0' +
        '&numberOfResults=10'
    )

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        'Accept' = 'application/json,text/plain,*/*'
        'Referer' = 'https://www.nvidia.com/en-us/geforce/drivers/'
    }

    $raw = Invoke-WebRequest -Uri $query -Headers $headers -WebSession $script:WebSession -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop
    $payload = $raw.Content | ConvertFrom-Json

    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['IDS']) {
        throw 'NVIDIA lookup did not return an IDS result list.'
    }
    $rows = @($payload.IDS | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        throw 'NVIDIA returned no WHQL driver results for RTX 3080.'
    }

    $candidates = @()

    foreach ($row in $rows) {
        $infoProperty = $row.PSObject.Properties['downloadInfo']
        $info = if ($null -ne $infoProperty) { $infoProperty.Value } else { $null }
        if ($null -eq $info) { continue }

        $name = [Uri]::UnescapeDataString((Get-OptionalPropertyString -Record $info -Name 'Name'))
        if ($name -notmatch '(?i)^GeForce\s+Game\s+Ready\s+Driver$') { continue }
        if ((Get-OptionalPropertyString -Record $info -Name 'DownloadTypeID') -ne '1' -or
            (Get-OptionalPropertyString -Record $info -Name 'IsWHQL') -ne '1') { continue }

        $supportedProducts = @(
            foreach ($series in @($info.series)) {
                foreach ($product in @($series.products)) {
                    [Uri]::UnescapeDataString((Get-OptionalPropertyString -Record $product -Name 'productName'))
                }
            }
        )
        if ($supportedProducts -notcontains 'GeForce RTX 3080') { continue }

        $candidateVersion = Get-OptionalPropertyString -Record $info -Name 'Version'
        if ($null -eq (Convert-ToVersionSafe -Text $candidateVersion)) { continue }
        $candidates += $info
    }

    if ($candidates.Count -eq 0) {
        throw 'NVIDIA lookup returned results but no WHQL Game Ready package explicitly supports RTX 3080.'
    }
    $selected = @($candidates | Sort-Object -Property @{
        Expression = { [version](Get-OptionalPropertyString -Record $_ -Name 'Version') }
    } -Descending)[0]

    $version = Get-OptionalPropertyString -Record $selected -Name 'Version'
    $url = Get-OptionalPropertyString -Record $selected -Name 'DownloadURL'

    if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($url)) {
        throw 'NVIDIA result did not include both Version and DownloadURL.'
    }

    $downloadHost = ([Uri]$url).Host.ToLowerInvariant()
    if ($downloadHost -notmatch '(^|\.)download\.nvidia\.com$') {
        throw "NVIDIA returned an unexpected download host: $downloadHost"
    }

    $script:NvidiaLatest = [pscustomobject]@{
        Version = $version
        Url     = $url
        Referer = 'https://www.nvidia.com/en-us/geforce/drivers/'
    }
    return $script:NvidiaLatest
}

# ============================================================================
# PLATFORM CHECKS
# ============================================================================

function Assert-TargetPlatform {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    if ([int]$cv.CurrentBuild -lt 22000) {
        throw "Windows 11 required. Build detected: $($cv.CurrentBuild)"
    }

    $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
    $boardName = [string]$board.Product
    if ($boardName -notmatch '(?i)ROG\s+STRIX\s+B850-I\s+GAMING\s+WIFI') {
        throw "This installer targets ROG STRIX B850-I GAMING WIFI. Detected board: '$boardName'"
    }

    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    if ([string]$cpu.Name -notmatch '(?i)Ryzen\s+7\s+9800X3D') {
        throw "This installer targets Ryzen 7 9800X3D. Detected CPU: '$($cpu.Name)'"
    }

    $nvidia = @(Get-PresentDeviceByHardwareRegex -HardwareRegex $NvidiaTargetHardwareRegex)
    if ($nvidia.Count -eq 0) {
        throw 'This package targets RTX 3080 12GB (DEV_220A), but it is not present. No driver installation was started. Confirm the current GPU before changing the target.'
    }

    Write-Host ("Board : {0}" -f $boardName)
    Write-Host ("CPU   : {0}" -f $cpu.Name)
    foreach ($record in $nvidia) {
        Write-Host ("GPU   : {0} | {1}" -f $record.Device.FriendlyName,$record.Device.InstanceId)
    }
}

# ============================================================================
# INSTALL STEPS
# ============================================================================

function Get-InstalledAmdChipsetPackageVersion {
    $installedVersion = $null
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $candidate = @(
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object {
                $name = Get-OptionalPropertyString -Record $_ -Name 'DisplayName'
                $version = Get-OptionalPropertyString -Record $_ -Name 'DisplayVersion'
                ($name -match '(?i)^AMD Chipset Software') -and (-not [string]::IsNullOrWhiteSpace($version))
            }
        ) | Select-Object -First 1

        if ($candidate) {
            $installedVersion = Get-OptionalPropertyString -Record $candidate -Name 'DisplayVersion'
            break
        }
    }

    return $installedVersion
}

function Install-AmdChipset {
    Write-Section '1/6 AMD CHIPSET'

    $latest = Resolve-AmdChipsetLatest
    Write-Host ("Official latest : {0}" -f $latest.Version)

    $installedVersion = Get-InstalledAmdChipsetPackageVersion
    Write-Host ("Installed      : {0}" -f $(if ($installedVersion) {$installedVersion} else {'NOT DETECTED'}))

    if ($installedVersion -eq $latest.Version) {
        Write-Host '[SKIP] Exact current AMD chipset package is already installed.' -ForegroundColor Green
        $script:Skipped++
        return
    }

    if ($installedVersion) {
        $cmp = Compare-VersionText -Installed $installedVersion -Target $latest.Version
        if ($null -ne $cmp -and $cmp -gt 0) {
            Write-Warning 'Installed chipset package is newer than AMD current page. No downgrade attempted.'
            $script:Skipped++
            return
        }
    }

    if ($Mode -eq 'Audit') {
        $file = Join-Path $DownloadRoot ("AMD_Chipset_Software_{0}.exe" -f $latest.Version)
        Download-OfficialFile -Url $latest.Url -Destination $file -Referer $latest.Referer
        Assert-AuthenticodePublisher -Path $file -PublisherRegex '(?i)Advanced Micro Devices|AMD'
        Register-SignedDownloadCache -Path $file -Url $latest.Url
        Write-Host '[WOULD INSTALL] AMD current B850 chipset package; signed payload verified.' -ForegroundColor Yellow
        $script:WouldInstall++
        return
    }

    $file = Join-Path $DownloadRoot ("AMD_Chipset_Software_{0}.exe" -f $latest.Version)
    Download-OfficialFile -Url $latest.Url -Destination $file -Referer $latest.Referer
    Assert-AuthenticodePublisher -Path $file -PublisherRegex '(?i)Advanced Micro Devices|AMD'
    Register-SignedDownloadCache -Path $file -Url $latest.Url

    # AMD documents /S for silent chipset deployment. Current 8.x outer
    # packages can return a non-zero wrapper code even though the inner chipset
    # install continues/completes; therefore the outer EXE code is diagnostic,
    # not the success criterion. Success is the registered AMD Chipset Software
    # package version after allowing the child installer time to settle.
    $p = Start-Process -FilePath $file -ArgumentList '/S' -Wait -PassThru -ErrorAction Stop
    Write-Host ("AMD wrapper exit code : {0}" -f $p.ExitCode)
    $script:RebootRecommended = $true

    $boundPackageVersion = $null
    for ($attempt = 1; $attempt -le 90; $attempt++) {
        $boundPackageVersion = Get-InstalledAmdChipsetPackageVersion
        if ($boundPackageVersion -eq $latest.Version) { break }
        if ($attempt -lt 90) { Start-Sleep -Seconds 2 }
    }

    if ($boundPackageVersion -ne $latest.Version) {
        $summaryCandidates = @(
            'C:\AMD\Chipset_Software\Logs\AMD_Chipset_Software_Install_Summary.txt',
            (Join-Path $env:USERPROFILE 'AMD_Chipset_IODrivers.Log')
        )
        foreach ($candidate in $summaryCandidates) {
            if (Test-Path -LiteralPath $candidate) {
                Write-Host ("AMD installer log     : {0}" -f $candidate) -ForegroundColor Yellow
            }
        }
        throw "AMD chipset did not verify after silent install. WrapperExit=$($p.ExitCode); target=$($latest.Version); registered=$(if ($boundPackageVersion) {$boundPackageVersion} else {'NOT DETECTED'})."
    }

    if ($p.ExitCode -notin @(0,3010)) {
        Write-Warning "AMD outer installer returned code $($p.ExitCode), but the target chipset package version verified successfully; accepting verified state."
    }

    Write-Host ("[VERIFIED] AMD chipset package registered version: {0}" -f $boundPackageVersion)
    $script:Installed++
    $script:RebootRecommended = $true
}

function Install-AsusInfFamily {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [Parameter(Mandatory)][string]$TitleRegex,
        [Parameter(Mandatory)][string]$HardwareRegex,
        [string]$ClassRegex = '.*',
        [string]$ProviderRegex = ''
    )

    Write-Section $StepName

    $devices = @(Get-PresentDeviceByHardwareRegex -HardwareRegex $HardwareRegex -ClassRegex $ClassRegex)
    if ($devices.Count -eq 0) {
        throw "Required hardware not detected for $StepName. Check Device Manager and the exact hardware ID."
    }

    $pkg = Resolve-AsusPackage -TitleRegex $TitleRegex
    Write-Host ("ASUS package version : {0}" -f $pkg.Version)
    Write-Host ("ASUS SHA-256         : {0}" -f $pkg.Sha256)

    # The ASUS page's marketing package version is not guaranteed to be the
    # DriverVer of its INF. Inspect the hash-verified ZIP before deciding.

    $ext = if ($pkg.Url -match '(?i)\.exe(?:\?|$)') { '.exe' } else { '.zip' }
    $safe = ($StepName -replace '[^A-Za-z0-9\-]','_')
    $download = Join-Path $DownloadRoot ("{0}-{1}{2}" -f $safe,$pkg.Version,$ext)

    Download-OfficialFile `
        -Url $pkg.Url `
        -Destination $download `
        -Referer $pkg.Referer `
        -ExpectedSha256 $pkg.Sha256

    if ($ext -ne '.zip') {
        throw "Expected an ASUS ZIP driver package for '$StepName', got EXE. Fail-closed."
    }

    $extract = Join-Path $ExtractRoot ("{0}-{1}" -f $safe,$pkg.Version)
    Expand-ZipFresh -Zip $download -Destination $extract

    foreach ($record in $devices) {
        $targetInf = Find-MatchingInf -RootFolder $extract -HardwareIds $record.HardwareIds
        if ($null -eq $targetInf) {
            Write-Host ("Device match IDs: {0}" -f ($record.HardwareIds -join ' | '))
            throw "No matching INF in current ASUS package for '$($record.Device.InstanceId)'."
        }

        $state = Test-PreInstallExact `
            -DeviceRecord $record `
            -TargetInf $targetInf `
            -ExpectedProviderRegex $ProviderRegex

        if ($state.Exact) {
            Write-Host '[SKIP] Exact provider + exact INF DriverVer already bound before install.' -ForegroundColor Green
            $script:Skipped++
            continue
        }

        if ($state.InstalledVersion -and $state.InstalledProvider -match $ProviderRegex) {
            $cmp = Compare-VersionText -Installed $state.InstalledVersion -Target $targetInf.Version
            if ($null -ne $cmp -and $cmp -gt 0) {
                Write-Warning 'Installed INF driver version is newer than the current ASUS package. No downgrade attempted.'
                $script:Skipped++
                continue
            }
        }

        if ($Mode -eq 'Audit') {
            Write-Host '[WOULD INSTALL] Matching ASUS INF after SHA-256 and DriverVer inspection.' -ForegroundColor Yellow
            $script:WouldInstall++
            continue
        }

        Invoke-PnpInstall -DisplayName $StepName -DeviceRecord $record `
            -TargetInf $targetInf -ExpectedProviderRegex $ProviderRegex
    }
}

function Install-AmdIgpuDriverOnly {
    Write-Section '4/6 AMD iGPU - DRIVER ONLY'

    $devices = @(Get-PresentDeviceByHardwareRegex -HardwareRegex '^PCI\\VEN_1002&DEV_13C0(?:&|$)' -ClassRegex '^Display$')
    if ($devices.Count -eq 0) {
        Write-Host '[SKIP] AMD display device is not present.'
        $script:Skipped++
        return
    }

    $amd = Resolve-AmdIgpuRecommendedLatest
    Write-Host ("AMD WHQL Recommended : {0}" -f $amd.Version)

    $amdExe = Join-Path $DownloadRoot ("AMD-Adrenalin-WHQL-{0}.exe" -f $amd.Version)
    $amdExtract = Join-Path $ExtractRoot ("AMD-Adrenalin-WHQL-{0}" -f $amd.Version)

    $downloaded = $false
    $lastDownloadError = $null

    foreach ($candidateUrl in @($amd.Urls)) {
        try {
            Download-OfficialFile `
                -Url $candidateUrl `
                -Destination $amdExe `
                -Referer $amd.Referer

            Assert-AuthenticodePublisher `
                -Path $amdExe `
                -PublisherRegex '(?i)Advanced Micro Devices|AMD'
            Register-SignedDownloadCache -Path $amdExe -Url $candidateUrl

            $downloaded = $true
            break
        }
        catch {
            $lastDownloadError = $_.Exception.Message
            Remove-Item -LiteralPath $amdExe -Force -ErrorAction SilentlyContinue
        }
    }

    $useAsusFallback = $false

    if (-not $downloaded) {
        Write-Warning "AMD WHQL package could not be downloaded from the official candidate URLs: $lastDownloadError"
        $useAsusFallback = $true
    }
    else {
        Write-Host 'Attempting driver-only extraction with Windows tar/libarchive...'
        if (-not (Expand-ArchiveWithWindowsTar -Archive $amdExe -Destination $amdExtract)) {
            Write-Warning 'Windows tar could not read the AMD self-extracting package as an archive. Falling back to the latest ASUS OEM VGA package for a driver-only INF install.'
            $useAsusFallback = $true
        }
    }

    if (-not $useAsusFallback) {
        foreach ($record in $devices) {
            $targetInf = Find-MatchingInf -RootFolder $amdExtract -HardwareIds $record.HardwareIds

            if ($null -eq $targetInf) {
                Write-Warning "AMD WHQL package extracted, but no matching display INF was found for '$($record.Device.InstanceId)'. Falling back to ASUS OEM VGA."
                $useAsusFallback = $true
                break
            }

            $state = Test-PreInstallExact `
                -DeviceRecord $record `
                -TargetInf $targetInf `
                -ExpectedProviderRegex '(?i)Advanced Micro Devices|AMD'

            if ($state.Exact) {
                Write-Host '[SKIP] Exact AMD WHQL Recommended INF DriverVer already bound.' -ForegroundColor Green
                $script:Skipped++
                continue
            }

            if ($state.InstalledVersion -and $state.InstalledProvider -match '(?i)Advanced Micro Devices|AMD') {
                $cmp = Compare-VersionText -Installed $state.InstalledVersion -Target $targetInf.Version
                if ($null -ne $cmp -and $cmp -gt 0) {
                    Write-Warning 'Installed AMD display driver is newer than the current WHQL Recommended INF. No downgrade attempted.'
                    $script:Skipped++
                    continue
                }
            }

            if ($Mode -eq 'Audit') {
                Write-Host '[WOULD INSTALL] AMD WHQL Recommended matching display INF only.' -ForegroundColor Yellow
                $script:WouldInstall++
                continue
            }

            Invoke-PnpInstall -DisplayName 'AMD iGPU WHQL Recommended - Driver Only' `
                -DeviceRecord $record -TargetInf $targetInf `
                -ExpectedProviderRegex '(?i)Advanced Micro Devices|AMD'
        }

        if (-not $useAsusFallback) {
            return
        }
    }

    # Supported fail-safe fallback: exact motherboard's latest OEM VGA ZIP.
    # Still INF-only: no Adrenalin UI or ASUS setup program is executed.
    $pkg = Resolve-AsusPackage -TitleRegex '(?i)AMD\s+VGA\s+driver'
    Write-Host ("ASUS OEM VGA fallback : {0}" -f $pkg.Version)

    $download = Join-Path $DownloadRoot ("ASUS-AMD-VGA-{0}.zip" -f $pkg.Version)
    $extract = Join-Path $ExtractRoot ("ASUS-AMD-VGA-{0}" -f $pkg.Version)

    Download-OfficialFile `
        -Url $pkg.Url `
        -Destination $download `
        -Referer $pkg.Referer `
        -ExpectedSha256 $pkg.Sha256

    Expand-ZipFresh -Zip $download -Destination $extract

    foreach ($record in $devices) {
        $targetInf = Find-MatchingInf -RootFolder $extract -HardwareIds $record.HardwareIds
        if ($null -eq $targetInf) {
            throw "ASUS OEM VGA fallback contains no matching INF for AMD display '$($record.Device.InstanceId)'."
        }

        $state = Test-PreInstallExact `
            -DeviceRecord $record `
            -TargetInf $targetInf `
            -ExpectedProviderRegex '(?i)Advanced Micro Devices|AMD'

        if ($state.Exact) {
            Write-Host '[SKIP] Exact ASUS OEM AMD display INF DriverVer already bound.' -ForegroundColor Green
            $script:Skipped++
            continue
        }

        if ($state.InstalledVersion -and $state.InstalledProvider -match '(?i)Advanced Micro Devices|AMD') {
            $cmp = Compare-VersionText -Installed $state.InstalledVersion -Target $targetInf.Version
            if ($null -ne $cmp -and $cmp -gt 0) {
                Write-Warning 'Installed AMD display driver is newer than ASUS OEM fallback. No downgrade attempted.'
                $script:Skipped++
                continue
            }
        }

        if ($Mode -eq 'Audit') {
            Write-Host '[WOULD INSTALL] ASUS OEM AMD display INF only.' -ForegroundColor Yellow
            $script:WouldInstall++
            continue
        }

        Invoke-PnpInstall -DisplayName 'AMD iGPU ASUS OEM fallback - Driver Only' `
            -DeviceRecord $record -TargetInf $targetInf `
            -ExpectedProviderRegex '(?i)Advanced Micro Devices|AMD'
    }
}

function Convert-NvidiaInstalledToMarketingVersion {
    param([string]$DriverVersion)

    $v = Convert-ToVersionSafe $DriverVersion
    if ($null -eq $v) { return $null }

    $p = $DriverVersion.Split('.')
    if ($p.Count -ne 4) { return $null }

    try {
        $third = [int]$p[2]
        $fourth = [int]$p[3]

        # Example:
        # 32.0.15.6094 -> 560.94
        # 32.0.16.1714 -> 617.14
        $majorHundreds = ($third % 10) * 100
        $majorRemainder = [math]::Floor($fourth / 100)
        $minor = $fourth % 100

        return ('{0}.{1:00}' -f ($majorHundreds + $majorRemainder),$minor)
    }
    catch {
        return $null
    }
}

function Install-NvidiaGameReady {
    Write-Section '5/6 NVIDIA RTX 3080 12GB - GAME READY DISPLAY DRIVER ONLY'

    $devices = @(Get-PresentDeviceByHardwareRegex -HardwareRegex $NvidiaTargetHardwareRegex)
    if ($devices.Count -eq 0) {
        throw 'The expected RTX 3080 12GB (DEV_220A) is not present. NVIDIA was not installed.'
    }

    $latest = Resolve-NvidiaLatestGameReady
    Write-Host ("Latest WHQL GRD : {0}" -f $latest.Version)

    $allExact = $true
    foreach ($record in $devices) {
        $installed = Get-SignedDriverForDevice -InstanceId ([string]$record.Device.InstanceId)
        $raw = if ($installed) { [string]$installed.DriverVersion } else { '' }
        $marketing = Convert-NvidiaInstalledToMarketingVersion -DriverVersion $raw
        $provider = if ($installed) { [string]$installed.DriverProviderName } else { '' }
        $problem = Get-ProblemCode -InstanceId ([string]$record.Device.InstanceId)

        Write-Host ("Installed provider : {0}" -f $(if ($provider) {$provider} else {'NONE'}))
        Write-Host ("Installed raw ver.  : {0}" -f $(if ($raw) {$raw} else {'NONE'}))
        Write-Host ("Installed GRD ver.  : {0}" -f $(if ($marketing) {$marketing} else {'UNKNOWN'}))

        if (-not ($provider -match '(?i)NVIDIA' -and $marketing -eq $latest.Version -and $null -ne $problem -and $problem -eq 0)) {
            $allExact = $false
        }
    }

    if ($allExact) {
        Write-Host '[SKIP] Exact current NVIDIA Game Ready version already bound.' -ForegroundColor Green
        $script:Skipped += $devices.Count
        return
    }

    foreach ($record in $devices) {
        $installed = Get-SignedDriverForDevice -InstanceId ([string]$record.Device.InstanceId)
        if ($installed -and [string]$installed.DriverProviderName -match '(?i)NVIDIA') {
            $marketing = Convert-NvidiaInstalledToMarketingVersion -DriverVersion ([string]$installed.DriverVersion)
            if ($marketing) {
                $cmp = Compare-VersionText -Installed $marketing -Target $latest.Version
                if ($null -ne $cmp -and $cmp -gt 0) {
                    Write-Warning "Installed NVIDIA version $marketing is newer than NVIDIA current lookup $($latest.Version). No downgrade attempted."
                    $script:Skipped++
                    return
                }
            }
        }
    }

    $file = Join-Path $DownloadRoot ("NVIDIA-GRD-{0}.exe" -f $latest.Version)
    Download-OfficialFile -Url $latest.Url -Destination $file -Referer $latest.Referer
    Assert-AuthenticodePublisher -Path $file -PublisherRegex '(?i)NVIDIA'
    Register-SignedDownloadCache -Path $file -Url $latest.Url

    $nvidiaExtract = Join-Path $ExtractRoot ("NVIDIA-GRD-{0}" -f $latest.Version)
    if (-not (Expand-ArchiveWithWindowsTar -Archive $file -Destination $nvidiaExtract)) {
        throw 'Windows tar could not extract the NVIDIA self-extracting archive. The undocumented outer-EXE switches were not attempted; install this driver manually or provide a tested extractor.'
    }
    $setups = @(Get-ChildItem -LiteralPath $nvidiaExtract -Filter 'setup.exe' -File -Recurse |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'Display.Driver') })
    if ($setups.Count -ne 1) {
        throw "Could not uniquely identify NVIDIA setup.exe beside Display.Driver in the official package ($($setups.Count) candidates)."
    }
    Assert-AuthenticodePublisher -Path $setups[0].FullName -PublisherRegex '(?i)NVIDIA'

    if ($Mode -eq 'Audit') {
        Write-Host '[WOULD INSTALL] NVIDIA WHQL Game Ready; signed archive and setup verified.' -ForegroundColor Yellow
        $script:WouldInstall++
        return
    }

    $nvidiaLogDir = Join-Path $LogRoot ("NVIDIA-{0}" -f $latest.Version)
    New-Item -ItemType Directory -Path $nvidiaLogDir -Force | Out-Null

    # NVIDIA documents:
    #   setup.exe -s -n Display.Driver
    # for silent display-driver-only installation.
    $setupArguments = @(
        '-s',
        '-n',
        'Display.Driver',
        "-log:$nvidiaLogDir",
        '-loglevel:6'
    )

    $p = Start-Process -FilePath $setups[0].FullName -WorkingDirectory $setups[0].DirectoryName `
        -ArgumentList $setupArguments -Wait -PassThru -ErrorAction Stop
    if ($p.ExitCode -notin @(0,1)) {
        throw "NVIDIA installer returned exit code $($p.ExitCode)."
    }
    $script:RebootRecommended = $true

    $verified = $false
    Invoke-PnpRescanBestEffort
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $verified = $true
        foreach ($record in $devices) {
            $bound = Get-SignedDriverForDevice -InstanceId ([string]$record.Device.InstanceId)
            $boundVersion = if ($bound) { Convert-NvidiaInstalledToMarketingVersion -DriverVersion ([string]$bound.DriverVersion) } else { $null }
            $boundProblem = Get-ProblemCode -InstanceId ([string]$record.Device.InstanceId)
            if (-not ($bound -and [string]$bound.DriverProviderName -match '(?i)NVIDIA' -and
                $boundVersion -eq $latest.Version -and $null -ne $boundProblem -and $boundProblem -eq 0)) {
                $verified = $false
                break
            }
        }
        if ($verified) { break }
        if ($attempt -lt 30) { Start-Sleep -Seconds 2 }
    }
    if (-not $verified) {
        throw 'NVIDIA setup completed, but the expected Game Ready driver was not verified as bound within 60 seconds. Reboot and audit before claiming success.'
    }
    Write-Host ("[VERIFIED] NVIDIA RTX 3080 Game Ready {0} is bound." -f $latest.Version)
    $script:Installed++
    $script:RebootRecommended = $true
}


function Install-ZowieMonitorDriver {
    Write-Section '6/6 ZOWIE XL2566X+ MONITOR INF'

    if (-not (Test-Path -LiteralPath $MonitorPackagePath)) {
        throw "Bundled monitor package is missing: $MonitorPackagePath"
    }

    $actualSha = Get-FileSha256 -Path $MonitorPackagePath
    Write-Host ("Package      : {0}" -f $MonitorPackageLabel)
    Write-Host ("Package SHA  : {0}" -f $actualSha)

    if ($actualSha -ne $MonitorPackageSha256) {
        throw "Bundled XL2566X+ package SHA-256 mismatch. Expected $MonitorPackageSha256, got $actualSha"
    }

    $extract = Join-Path $ExtractRoot 'ZOWIE-XL2566X+-V001'

    if (-not (Expand-ArchiveWithWindowsTar -Archive $MonitorPackagePath -Destination $extract)) {
        throw 'Windows tar could not extract the bundled XL2566X+ .7z package.'
    }

    # Monitor hardware identity can be re-enumerated when the NVIDIA display
    # driver binds. During precheck, absence/non-match is therefore deferred.
    # During the real 6/6 step (which runs after NVIDIA), rescan and retry.
    $monitors = @()
    $monitorAttempts = if ($Mode -eq 'Audit') { 1 } else { 15 }
    for ($attempt = 1; $attempt -le $monitorAttempts; $attempt++) {
        if ($Mode -ne 'Audit') { Invoke-PnpRescanBestEffort }
        $monitors = @(Get-PresentDeviceByHardwareRegex -HardwareRegex '^MONITOR\\' -ClassRegex '^Monitor$')
        if ($monitors.Count -gt 0) { break }
        if ($attempt -lt $monitorAttempts) { Start-Sleep -Seconds 2 }
    }

    if ($monitors.Count -eq 0) {
        if ($Mode -eq 'Audit') {
            Write-Host '[DEFERRED] No present monitor-class device yet; install step will rescan after NVIDIA.' -ForegroundColor Yellow
            return
        }
        Write-Warning 'No present monitor-class PnP devices were detected after the NVIDIA step.'
        $script:Skipped++
        return
    }

    $matchedCount = 0

    foreach ($record in $monitors) {
        $targetInf = Find-MatchingInf -RootFolder $extract -HardwareIds $record.HardwareIds
        if ($null -eq $targetInf) {
            continue
        }

        $matchedCount++

        # A WHQL monitor package should carry a signed catalog. Validate it
        # before allowing PnPUtil to stage the package.
        Assert-InfCatalogSignature -InfMetadata $targetInf -SearchRoot $extract | Out-Null

        $state = Test-PreInstallExact `
            -DeviceRecord $record `
            -TargetInf $targetInf `
            -ExpectedProviderRegex '(?i)BenQ|ZOWIE'

        if ($state.Exact) {
            Write-Host '[SKIP] Exact ZOWIE provider + monitor INF DriverVer already bound before install.' -ForegroundColor Green
            $script:Skipped++
            continue
        }

        # Do NOT compare a Microsoft Generic Monitor version number against a
        # ZOWIE INF version number. They are different provider/version schemes.
        # A "newer" skip is valid only if a ZOWIE/BenQ provider is already bound.
        if ($state.InstalledProvider -match '(?i)BenQ|ZOWIE' -and $state.InstalledVersion) {
            $cmp = Compare-VersionText -Installed $state.InstalledVersion -Target $targetInf.Version
            if ($null -ne $cmp -and $cmp -gt 0) {
                Write-Warning 'Installed ZOWIE/BenQ monitor INF is newer than the bundled official V001 package. No downgrade attempted.'
                $script:Skipped++
                continue
            }
        }

        if ($Mode -eq 'Audit') {
            Write-Host '[WOULD INSTALL] ZOWIE XL2566X+ WHQL monitor INF.' -ForegroundColor Yellow
            $script:WouldInstall++
            continue
        }

        Invoke-PnpInstall `
            -DisplayName 'ZOWIE XL2566X+ WHQL Monitor Driver' `
            -DeviceRecord $record `
            -TargetInf $targetInf `
            -ExpectedProviderRegex '(?i)BenQ|ZOWIE'
    }

    if ($matchedCount -eq 0) {
        if ($Mode -eq 'Audit') {
            Write-Host '[DEFERRED] XL2566X+ INF did not match the current pre-driver monitor identity; install step will rescan after NVIDIA.' -ForegroundColor Yellow
            return
        }

        # Give the post-NVIDIA monitor stack one additional settle window.
        for ($attempt = 1; $attempt -le 15 -and $matchedCount -eq 0; $attempt++) {
            Invoke-PnpRescanBestEffort
            Start-Sleep -Seconds 2
            $retryMonitors = @(Get-PresentDeviceByHardwareRegex -HardwareRegex '^MONITOR\\' -ClassRegex '^Monitor$')
            foreach ($record in $retryMonitors) {
                $targetInf = Find-MatchingInf -RootFolder $extract -HardwareIds $record.HardwareIds
                if ($null -eq $targetInf) { continue }
                $matchedCount++
                Assert-InfCatalogSignature -InfMetadata $targetInf -SearchRoot $extract | Out-Null
                $state = Test-PreInstallExact -DeviceRecord $record -TargetInf $targetInf -ExpectedProviderRegex '(?i)BenQ|ZOWIE'
                if ($state.Exact) {
                    Write-Host '[SKIP] Exact ZOWIE provider + monitor INF DriverVer already bound after display rescan.' -ForegroundColor Green
                    $script:Skipped++
                }
                else {
                    Invoke-PnpInstall -DisplayName 'ZOWIE XL2566X+ WHQL Monitor Driver' -DeviceRecord $record -TargetInf $targetInf -ExpectedProviderRegex '(?i)BenQ|ZOWIE'
                }
                break
            }
        }

        if ($matchedCount -eq 0) {
            Write-Warning 'The bundled XL2566X+ WHQL INF still did not match a present monitor hardware ID after NVIDIA/display rescan; nothing was installed.'
            $script:Skipped++
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================

function Invoke-DriverSteps {
    param([switch]$ContinueOnFailure)

    $steps = @(
        [pscustomobject]@{ Name = 'AMD chipset'; Action = { Install-AmdChipset } }
        [pscustomobject]@{ Name = 'Intel I226-V LAN'; Action = {
            Install-AsusInfFamily `
                -StepName '2/6 INTEL I226-V LAN' `
                -TitleRegex '(?i)Intel\s+I225/I226\s+LAN\s+driver' `
                -HardwareRegex '^PCI\\VEN_8086&DEV_125C(?:&|$)' `
                -ProviderRegex '(?i)Intel'
        } }
        [pscustomobject]@{ Name = 'Realtek UCM'; Action = {
            Install-AsusInfFamily `
                -StepName '3/6 REALTEK UCM' `
                -TitleRegex '(?i)Realtek\s+UCM\s+driver' `
                -HardwareRegex '^ACPI\\RTK5452' `
                -ProviderRegex '(?i)Realtek'
        } }
        [pscustomobject]@{ Name = 'AMD iGPU'; Action = { Install-AmdIgpuDriverOnly } }
        [pscustomobject]@{ Name = 'NVIDIA RTX 3080'; Action = { Install-NvidiaGameReady } }
        [pscustomobject]@{ Name = 'ZOWIE monitor'; Action = { Install-ZowieMonitorDriver } }
    )

    foreach ($step in $steps) {
        try {
            & $step.Action
            $script:StepResults += [pscustomobject]@{
                Name = $step.Name; Status = 'OK'; Error = ''
            }
        }
        catch {
            $script:Failures++
            $message = $_.Exception.Message
            Write-Host ("[STEP FAILED] {0}: {1}" -f $step.Name,$message) -ForegroundColor Red
            if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber -gt 0) {
                Write-Host ("ERROR LOCATION: {0}, line {1}" -f
                    $_.InvocationInfo.ScriptName,$_.InvocationInfo.ScriptLineNumber)
            }
            $script:StepResults += [pscustomobject]@{
                Name = $step.Name; Status = 'FAILED'; Error = $message
            }
            if (-not $ContinueOnFailure) { break }
        }
    }

    return ($script:Failures -eq 0)
}

function Write-FinalDriverReport {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' FINAL REPORT'
    Write-Host '============================================================'
    foreach ($result in $script:StepResults) {
        Write-Host ("{0,-18} : {1}" -f $result.Name,$result.Status)
        if ($result.Error) { Write-Host ("  Reason: {0}" -f $result.Error) }
    }
    Write-Host ("Mode               : {0}" -f $Mode)
    Write-Host ("Installed          : {0}" -f $script:Installed)
    Write-Host ("Skipped            : {0}" -f $script:Skipped)
    Write-Host ("Would install      : {0}" -f $script:WouldInstall)
    Write-Host ("Failures           : {0}" -f $script:Failures)
    Write-Host ("Reboot recommended : {0}" -f $script:RebootRecommended)
    Write-Host ("Log                : {0}" -f $LogFile)
}

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (' GAMING DRIVER INSTALLER - v{0} REVIEW BUILD' -f $ScriptVersion)
    Write-Host '============================================================'
    Write-Host ("Mode : {0}" -f $Mode)
    Write-Host ("Log  : {0}" -f $LogFile)
    Write-Host ''

    Assert-TargetPlatform

    if ($Mode -eq 'Install') {
        Ensure-DriverBootstrapGuard
        Write-Host 'PRECHECK: all six driver steps will be audited before any installer runs.' -ForegroundColor Cyan
        $Mode = 'Audit'
        $precheckOk = Invoke-DriverSteps -ContinueOnFailure
        $Mode = 'Install'

        Write-Host ''
        Write-Host 'PRECHECK RESULTS:'
        foreach ($result in $script:StepResults) {
            Write-Host ("  {0,-18} : {1}" -f $result.Name,$result.Status)
            if ($result.Error) { Write-Host ("    {0}" -f $result.Error) }
        }

        if (-not $precheckOk) {
            Write-Host 'INSTALL ABORTED: no installer or PnP binding command was started.' -ForegroundColor Red
            Write-FinalDriverReport
            exit 1
        }

        $script:StepResults = @()
        $script:Failures = 0
        $script:Skipped = 0
        $script:WouldInstall = 0
        Write-Host ''
        Write-Host 'PRECHECK PASSED: starting sequential installation.' -ForegroundColor Green
        $stepsOk = Invoke-DriverSteps
    }
    else {
        $stepsOk = Invoke-DriverSteps -ContinueOnFailure
    }

    if ($Mode -eq 'Install' -and $stepsOk) {
        Finalize-DriverBootstrapGuard
    }

    Write-FinalDriverReport

    if ($Mode -eq 'Audit') {
        Write-Host ''
        Write-Host 'AUDIT: no installers or PnP binding commands were executed.' -ForegroundColor Cyan
        Write-Host 'Audit downloads and inspects applicable packages; it can use several gigabytes.'
        Write-Host 'Disabled-device state (Wi-Fi, Bluetooth and onboard audio) is outside this package.'
    }

    if ($script:RebootRecommended) {
        Write-Host ''
        Write-Host 'Restart Windows once before running the CS2 gaming baseline launcher.' -ForegroundColor Yellow
    }

    if (-not $stepsOk) { exit 1 }
    exit 0
}
catch {
    $script:Failures++
    Write-Host ''
    Write-Host ("FATAL: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber -gt 0) {
        Write-Host ("ERROR LOCATION: {0}, line {1}" -f $_.InvocationInfo.ScriptName,$_.InvocationInfo.ScriptLineNumber)
    }
    Write-Host ("PARTIAL REPORT: verified installs={0}; skipped={1}; would install={2}; failure={3}" -f
        $script:Installed,$script:Skipped,$script:WouldInstall,$script:Failures)
    if ($script:RebootRecommended) {
        Write-Host 'A previous step changed drivers; reboot before auditing or retrying.' -ForegroundColor Yellow
    }
    Write-Host ("Log: {0}" -f $LogFile)
    exit 1
}
finally {
    if ($script:BootstrapGuardActive) {
        try {
            Write-Warning 'Driver install did not reach normal bootstrap finalization. Restoring the pre-run temporary driver policies now.'
            Restore-DriverBootstrapGuard -Reason 'failure/incomplete-run cleanup'
        }
        catch {
            Write-Warning ("BOOTSTRAP CLEANUP FAILED: {0}" -f $_.Exception.Message)
            Write-Warning ("Saved recovery state retained at: {0}" -f $BootstrapGuardStatePath)
        }
    }
    try { Stop-Transcript | Out-Null } catch {}
}
