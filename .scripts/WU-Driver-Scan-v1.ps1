#requires -Version 5.1
<#
.SYNOPSIS
    Read-only Windows Update driver scan for the gaming baseline. Revision 1.0.1.

.DESCRIPTION
    Searches the public Windows Update service for updates whose Type is Driver.
    It NEVER downloads or installs an update.

    Intended to be launched by the scheduled task created by
    PostFormat-Policy-Baseline-v1.ps1 every other week while the PC is idle.

    Reports:
      C:\ProgramData\GamingPolicyBaseline\WU-Driver-Scan\latest.txt
      C:\ProgramData\GamingPolicyBaseline\WU-Driver-Scan\AVAILABLE.txt (only when results exist)
      timestamped .txt and .json files

    Search criteria:
      IsInstalled = 0 AND IsHidden = 0 AND Type = 'Driver'
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:ProgramData 'GamingPolicyBaseline\WU-Driver-Scan'
New-Item -ItemType Directory -Path $Root -Force | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$TextReport = Join-Path $Root ("driver-scan-{0}.txt" -f $Stamp)
$JsonReport = Join-Path $Root ("driver-scan-{0}.json" -f $Stamp)
$Latest = Join-Path $Root 'latest.txt'
$AvailableMarker = Join-Path $Root 'AVAILABLE.txt'

$lines = New-Object 'System.Collections.Generic.List[string]'

function Add-Line {
    param(
        [AllowEmptyString()]
        [string]$Text = ''
    )

    $lines.Add($Text)
    Write-Host $Text
}

try {
    Add-Line '============================================================'
    Add-Line ' WINDOWS UPDATE DRIVER-ONLY SCAN'
    Add-Line '============================================================'
    Add-Line ("Started      : {0}" -f (Get-Date).ToString('o'))
    Add-Line 'Mutation     : NONE - search/report only'
    Add-Line "Server       : Windows Update (ssWindowsUpdate)"
    Add-Line "Criteria     : IsInstalled=0 AND IsHidden=0 AND Type='Driver'"
    Add-Line ''

    $session = New-Object -ComObject 'Microsoft.Update.Session'
    $session.ClientApplicationID = 'GamingBaseline.DriverOnlyScan'

    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $true

    # ServerSelection enum:
    #   0 = Default, 1 = ManagedServer, 2 = WindowsUpdate, 3 = Others
    $searcher.ServerSelection = 2

    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
    $count = [int]$result.Updates.Count

    Add-Line ("Result code  : {0}" -f $result.ResultCode)
    Add-Line ("Drivers found: {0}" -f $count)
    Add-Line ''

    $rows = @()

    for ($i = 0; $i -lt $count; $i++) {
        $u = $result.Updates.Item($i)

        $row = [pscustomobject]@{
            Index              = $i + 1
            Title              = [string]$u.Title
            DriverClass        = $(try { [string]$u.DriverClass } catch { '' })
            DriverManufacturer = $(try { [string]$u.DriverManufacturer } catch { '' })
            DriverModel        = $(try { [string]$u.DriverModel } catch { '' })
            DriverProvider     = $(try { [string]$u.DriverProvider } catch { '' })
            DriverVerDate      = $(try {
                if ($null -ne $u.DriverVerDate) {
                    ([datetime]$u.DriverVerDate).ToString('o')
                } else { '' }
            } catch { '' })
            HardwareID         = $(try { [string]$u.DriverHardwareID } catch { '' })
            UpdateID           = $(try { [string]$u.Identity.UpdateID } catch { '' })
            RevisionNumber     = $(try { [int]$u.Identity.RevisionNumber } catch { 0 })
            IsDownloaded       = [bool]$u.IsDownloaded
        }

        $rows += $row

        Add-Line ("[{0}] {1}" -f $row.Index,$row.Title)
        if ($row.DriverProvider)     { Add-Line ("    Provider     : {0}" -f $row.DriverProvider) }
        if ($row.DriverManufacturer) { Add-Line ("    Manufacturer : {0}" -f $row.DriverManufacturer) }
        if ($row.DriverModel)        { Add-Line ("    Model        : {0}" -f $row.DriverModel) }
        if ($row.DriverClass)        { Add-Line ("    Class        : {0}" -f $row.DriverClass) }
        if ($row.HardwareID)         { Add-Line ("    Hardware ID  : {0}" -f $row.HardwareID) }
        if ($row.DriverVerDate)      { Add-Line ("    Driver date  : {0}" -f $row.DriverVerDate) }
        Add-Line ''
    }

    Add-Line 'No updates were downloaded or installed.'
    Add-Line ("Finished     : {0}" -f (Get-Date).ToString('o'))

    $lines | Set-Content -LiteralPath $TextReport -Encoding UTF8
    $lines | Set-Content -LiteralPath $Latest -Encoding UTF8
    @($rows) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $JsonReport -Encoding UTF8

    if ($count -gt 0) {
        $lines | Set-Content -LiteralPath $AvailableMarker -Encoding UTF8
    }
    else {
        Remove-Item -LiteralPath $AvailableMarker -Force -ErrorAction SilentlyContinue
    }

    exit 0
}
catch {
    Add-Line ''
    Add-Line ("ERROR: {0}" -f $_.Exception.Message)
    Add-Line ("Finished: {0}" -f (Get-Date).ToString('o'))

    $lines | Set-Content -LiteralPath $TextReport -Encoding UTF8
    $lines | Set-Content -LiteralPath $Latest -Encoding UTF8

    exit 20
}
