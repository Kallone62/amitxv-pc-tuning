#requires -Version 5.1
param([switch]$Preview)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root 'PostFormat-Logs'
$started = Get-Date
$report = Join-Path $logDir ('report-{0}.txt' -f $started.ToString('yyyyMMdd-HHmmss'))
$records = New-Object System.Collections.Generic.List[string]
$exitCode = 0
$currentStep = ''
$index = 0
$isElevated = $false
$directXPackageVersion = '9.29.1974.1'
$directXStateDir = Join-Path $env:LOCALAPPDATA 'PostFormat-Apps'
$directXStateFile = Join-Path $directXStateDir 'directx-june2010-state.json'

$steps = @(
    @{ Name = 'Microsoft Visual C++ 2008 x86'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2008.x86' },
    @{ Name = 'Microsoft Visual C++ 2008 x64'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2008.x64' },
    @{ Name = 'Microsoft Visual C++ 2010 x86'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2010.x86' },
    @{ Name = 'Microsoft Visual C++ 2010 x64'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2010.x64' },
    @{ Name = 'Microsoft Visual C++ 2012 x86'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2012.x86' },
    @{ Name = 'Microsoft Visual C++ 2012 x64'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2012.x64' },
    @{ Name = 'Microsoft Visual C++ 2013 x86'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2013.x86' },
    @{ Name = 'Microsoft Visual C++ 2013 x64'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2013.x64' },
    @{ Name = 'Microsoft Visual C++ current x86'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2015+.x86' },
    @{ Name = 'Microsoft Visual C++ current x64'; Kind = 'Winget'; Id = 'Microsoft.VCRedist.2015+.x64' },
    @{ Name = 'DirectX legacy components (June 2010)'; Kind = 'DirectX' },
    @{ Name = 'Google Chrome'; Kind = 'Winget'; Id = 'Google.Chrome' },
    @{ Name = 'AutoHotkey v2'; Kind = 'Winget'; Id = 'AutoHotkey.AutoHotkey' },
    @{ Name = 'FACEIT Anti-Cheat only'; Kind = 'FaceitACOnly'; Id = 'FACEITLTD.FACEITAC' },
    @{ Name = 'Spotify'; Kind = 'Winget'; Id = 'Spotify.Spotify' },
    @{ Name = 'TeamSpeak 3.6.2 only (no Overwolf)'; Kind = 'TeamSpeakClean'; Id = 'TeamSpeakSystems.TeamSpeakClient'; Version = '3.6.2' },
    @{ Name = 'Peripheral setup pages'; Kind = 'PeripheralPages' },
    @{ Name = 'Steam'; Kind = 'Winget'; Id = 'Valve.Steam' },
    @{ Name = 'Bundled extras final guard'; Kind = 'BundleGuard' },
    @{ Name = 'ExitLag (manual / optional)'; Kind = 'ExitLag' }
)

function Add-Record([string]$status, [string]$detail) {
    $line = '[{0}/{1}] {2} | {3} | {4}' -f $index, $steps.Count, $currentStep, $status, $detail
    $records.Add($line)
    Write-Host $line
}

function Assert-SignedBy([string]$path, [string]$publisher) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installer not found: $path" }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
        $subject -notmatch [regex]::Escape($publisher)) {
        throw "Installer signature not verified for $publisher. Status: $($signature.Status); signer: $subject"
    }
}

function Get-UninstallEntries {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    }
}

function Test-ChromePresent {
    if (Get-UninstallEntries | Where-Object { $_.DisplayName -eq 'Google Chrome' -and $_.Publisher -match 'Google' } | Select-Object -First 1) { return $true }
    foreach ($path in @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe' }),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    }
    return $false
}

function Test-AutoHotkeyPresent {
    if (Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)^AutoHotkey' } | Select-Object -First 1) { return $true }
    foreach ($path in @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\UX\AutoHotkeyUX.exe')
    )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $true }
    }
    return $false
}

function Test-ExitLagPresent {
    if (Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)^ExitLag( version)?\b' } | Select-Object -First 1) { return $true }
    foreach ($path in @(
        (Join-Path $env:ProgramFiles 'ExitLag\ExitLag.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'ExitLag\ExitLag.exe' })
    )) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    }
    return $false
}

function Test-FaceitPresent {
    if (Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)^FACEIT.*Anti.?Cheat|^FACEIT AC' } | Select-Object -First 1) { return $true }
    foreach ($path in @(
        (Join-Path $env:ProgramFiles 'FACEIT AC\FACEITAC.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'FACEIT AC\FACEITAC.exe' })
    )) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    }
    return $false
}

function Test-SpotifyPresent {
    $spotifyExe = Join-Path $env:APPDATA 'Spotify\Spotify.exe'
    if (Test-Path -LiteralPath $spotifyExe -PathType Leaf) { return $true }
    if (Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)^Spotify($|\s)' } | Select-Object -First 1) { return $true }
    return $false
}

function Get-TeamSpeakInstalledVersion {
    $entry = Get-UninstallEntries |
        Where-Object { $_.DisplayName -match '(?i)^TeamSpeak.*Client|^TeamSpeak 3' } |
        Select-Object -First 1
    if ($entry -and $entry.DisplayVersion) { return [string]$entry.DisplayVersion }
    return ''
}

function Test-SteamPresent {
    $candidatePaths = New-Object System.Collections.Generic.List[string]
    try {
        $steam = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop
        if ($steam.SteamExe) { $candidatePaths.Add([string]$steam.SteamExe) }
        if ($steam.SteamPath) { $candidatePaths.Add((Join-Path ([string]$steam.SteamPath) 'steam.exe')) }
    } catch { }

    if (${env:ProgramFiles(x86)}) { $candidatePaths.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam\steam.exe')) }
    if ($env:ProgramFiles) { $candidatePaths.Add((Join-Path $env:ProgramFiles 'Steam\steam.exe')) }

    foreach ($path in ($candidatePaths | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    }

    if (Get-UninstallEntries | Where-Object { $_.DisplayName -eq 'Steam' -and $_.Publisher -match 'Valve' } | Select-Object -First 1) { return $true }
    return $false
}


function Get-WingetInstalledInfo([hashtable]$step, [string]$wingetPath, [switch]$WriteLog) {
    $listLog = Join-Path $logDir ('winget-check-{0:00}-{1}.txt' -f $index, $step.Id)
    $args = @('list', '--id', $step.Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $wingetPath @args 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($WriteLog) { $lines | Out-File -LiteralPath $listLog -Encoding UTF8 }

    $escapedId = [regex]::Escape([string]$step.Id)
    $row = $lines | Where-Object { [string]$_ -match ('(^|\s)' + $escapedId + '(\s|$)') } | Select-Object -First 1
    $version = ''
    if ($row) {
        $m = [regex]::Match([string]$row, ('(?:^|\s)' + $escapedId + '\s+(?<version>\S+)'))
        if ($m.Success) { $version = $m.Groups['version'].Value }
    }

    [pscustomobject]@{
        Present = [bool]$row
        Version = $version
        ExitCode = $code
        Log = $listLog
        Row = [string]$row
    }
}

function Get-ApplicationFallbackState([hashtable]$step) {
    switch ($step.Id) {
        'Google.Chrome' {
            if (Test-ChromePresent) { return [pscustomobject]@{ Present = $true; Version = ''; Detail = 'Chrome registry/executable detected' } }
        }
        'AutoHotkey.AutoHotkey' {
            if (Test-AutoHotkeyPresent) { return [pscustomobject]@{ Present = $true; Version = ''; Detail = 'AutoHotkey registry/executable detected' } }
        }
        'Spotify.Spotify' {
            if (Test-SpotifyPresent) { return [pscustomobject]@{ Present = $true; Version = ''; Detail = 'Spotify registry/executable detected' } }
        }
        'TeamSpeakSystems.TeamSpeakClient' {
            $v = Get-TeamSpeakInstalledVersion
            if ($v) { return [pscustomobject]@{ Present = $true; Version = $v; Detail = "TeamSpeak uninstall entry detected ($v)" } }
        }
        'Valve.Steam' {
            if (Test-SteamPresent) { return [pscustomobject]@{ Present = $true; Version = ''; Detail = 'Steam registry/executable detected' } }
        }
    }
    return [pscustomobject]@{ Present = $false; Version = ''; Detail = '' }
}

function Get-WingetStepState([hashtable]$step, [string]$wingetPath, [switch]$WriteLog) {
    $wingetState = Get-WingetInstalledInfo -step $step -wingetPath $wingetPath -WriteLog:$WriteLog
    if ($wingetState.Present) {
        return [pscustomobject]@{
            Present = $true
            Version = $wingetState.Version
            Detail = if ($wingetState.Version) { "WinGet verified $($step.Id) version $($wingetState.Version)" } else { "WinGet verified $($step.Id)" }
            Source = 'WinGet'
            Log = $wingetState.Log
        }
    }

    $fallback = Get-ApplicationFallbackState $step
    if ($fallback.Present) {
        return [pscustomobject]@{
            Present = $true
            Version = $fallback.Version
            Detail = $fallback.Detail
            Source = 'Fallback'
            Log = $wingetState.Log
        }
    }

    return [pscustomobject]@{
        Present = $false
        Version = ''
        Detail = "Not installed; WinGet check exit $($wingetState.ExitCode)"
        Source = 'None'
        Log = $wingetState.Log
    }
}

function Test-RequestedVersionSatisfied([hashtable]$step, $state) {
    if (-not $state.Present) { return $false }
    if (-not $step.Version) { return $true }
    if ([string]::IsNullOrWhiteSpace([string]$state.Version)) { return $false }
    return ([string]$state.Version -eq [string]$step.Version)
}

function Invoke-Winget([hashtable]$step, [string]$wingetPath) {
    # Always check before invoking any installer. This is intentionally install-only,
    # not an "install or upgrade every time" workflow.
    $before = Get-WingetStepState -step $step -wingetPath $wingetPath -WriteLog
    if (Test-RequestedVersionSatisfied $step $before) {
        Add-Record 'ALREADY INSTALLED' ($before.Detail + "; installer skipped. Check: " + $before.Log)
        return
    }

    if ($before.Present -and $step.Version) {
        Write-Host ("Installed version does not match requested {0}; requested version will be attempted." -f $step.Version)
    }

    $args = @('install', '--id', $step.Id, '--exact', '--source', 'winget',
        '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($step.Version) { $args += @('--version', $step.Version) }

    $log = Join-Path $logDir ('winget-install-{0:00}-{1}.txt' -f $index, $step.Id)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $wingetPath @args 2>&1 | Tee-Object -FilePath $log
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($code -eq 3010) {
        throw "Installer requested restart (3010). Restart, then rerun this CMD. Log: $log"
    }

    # Verify state after *every* attempt, including nonzero WinGet results.
    # This catches installers that complete but return an unusual code, without
    # blindly treating the code as success.
    Start-Sleep -Seconds 1
    $after = Get-WingetStepState -step $step -wingetPath $wingetPath -WriteLog
    if (Test-RequestedVersionSatisfied $step $after) {
        if ($code -eq 0) {
            Add-Record 'INSTALLED' ($after.Detail + "; post-install verification passed. Log: " + $log)
        } else {
            Add-Record 'INSTALLED / VERIFIED' ("WinGet returned $code, but the requested package is now verified present. " + $after.Detail + ". Log: " + $log)
        }
        return
    }

    if ($code -eq -1978335189) {
        throw "WinGet reports no applicable update (0x8A15002B), but the requested installed state could not be verified. Log: $log; check: $($after.Log)"
    }
    if ($code -eq -1978335226) {
        throw "WinGet ShellExecute failed (0x8A150006 / $code). The package is still not verified as installed. Installer log: $log; check: $($after.Log)"
    }
    if ($code -ne 0) {
        throw "WinGet failed (exit $code) and post-install verification failed. Log: $log; check: $($after.Log)"
    }
    throw "WinGet returned success, but post-install verification could not confirm $($step.Id). Log: $log; check: $($after.Log)"
}

function Get-CurrentMachineGuid {
    try {
        return [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop)
    } catch {
        return ''
    }
}

function Get-DirectXLegacyFileSet {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($n in 33..43) { $names.Add(('D3DCompiler_{0}.dll' -f $n)) }
    foreach ($n in 42..43) { $names.Add(('d3dcsx_{0}.dll' -f $n)) }
    $names.Add('d3dx10.dll')
    foreach ($n in 33..43) { $names.Add(('d3dx10_{0}.dll' -f $n)) }
    foreach ($n in 42..43) { $names.Add(('d3dx11_{0}.dll' -f $n)) }
    foreach ($n in 24..43) { $names.Add(('d3dx9_{0}.dll' -f $n)) }
    foreach ($n in 0..7) { $names.Add(('X3DAudio1_{0}.dll' -f $n)) }
    foreach ($n in 0..9) { $names.Add(('xactengine2_{0}.dll' -f $n)) }
    foreach ($n in 0..7) { $names.Add(('xactengine3_{0}.dll' -f $n)) }
    foreach ($n in 0..5) { $names.Add(('XAPOFX1_{0}.dll' -f $n)) }
    foreach ($n in 0..7) { $names.Add(('XAudio2_{0}.dll' -f $n)) }
    foreach ($n in 1..3) { $names.Add(('xinput1_{0}.dll' -f $n)) }
    return @($names | Select-Object -Unique)
}

function Test-DirectXLegacyFilesPresent {
    $folders = New-Object System.Collections.Generic.List[string]
    $folders.Add((Join-Path $env:windir 'System32'))
    if ([Environment]::Is64BitOperatingSystem) {
        $folders.Add((Join-Path $env:windir 'SysWOW64'))
    }

    $required = @(Get-DirectXLegacyFileSet)
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($folder in $folders) {
        foreach ($name in $required) {
            $path = Join-Path $folder $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $missing.Add($path)
            }
        }
    }

    [pscustomobject]@{
        Present = ($missing.Count -eq 0)
        RequiredCount = ($required.Count * $folders.Count)
        Missing = @($missing)
    }
}

function Test-DirectXLegacyState {
    $machineGuid = Get-CurrentMachineGuid
    if (-not [string]::IsNullOrWhiteSpace($machineGuid) -and (Test-Path -LiteralPath $directXStateFile -PathType Leaf)) {
        try {
            $state = Get-Content -LiteralPath $directXStateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ([string]$state.PackageVersion -eq $directXPackageVersion -and
                [string]$state.MachineGuid -eq $machineGuid -and
                [string]$state.Status -eq 'Success') {
                return [pscustomobject]@{ Present = $true; Detail = "successful package $directXPackageVersion state marker matches this Windows installation" }
            }
        } catch { }
    }

    $files = Test-DirectXLegacyFilesPresent
    if ($files.Present) {
        return [pscustomobject]@{ Present = $true; Detail = "complete legacy DirectX component file set verified ($($files.RequiredCount) files across required system directories)" }
    }

    $sample = @($files.Missing | Select-Object -First 4)
    $detail = if ($sample.Count -gt 0) { 'missing examples: ' + ($sample -join '; ') } else { 'legacy component set not verified' }
    return [pscustomobject]@{ Present = $false; Detail = $detail }
}

function Set-DirectXLegacyState {
    $machineGuid = Get-CurrentMachineGuid
    if ([string]::IsNullOrWhiteSpace($machineGuid)) {
        throw 'DirectX setup succeeded, but Windows MachineGuid could not be read for the idempotency marker.'
    }
    New-Item -ItemType Directory -Path $directXStateDir -Force | Out-Null
    $state = [ordered]@{
        PackageVersion = $directXPackageVersion
        MachineGuid = $machineGuid
        Status = 'Success'
        CompletedAt = (Get-Date).ToString('o')
    }
    $tmp = $directXStateFile + '.tmp'
    $state | ConvertTo-Json | Out-File -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $directXStateFile -Force
}

function Invoke-DirectX {
    $before = Test-DirectXLegacyState
    if ($before.Present) {
        Add-Record 'ALREADY INSTALLED' ("DirectX June 2010 legacy components verified: " + $before.Detail + '; DXSETUP skipped')
        return
    }

    $download = Join-Path $logDir 'directx_Jun2010_redist.exe'
    $extract = Join-Path $logDir 'DirectX-extracted'
    $uri = 'https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe'

    if (-not (Test-Path -LiteralPath $download -PathType Leaf)) {
        Write-Host 'Downloading Microsoft DirectX legacy components...'
        Invoke-WebRequest -Uri $uri -OutFile $download -UseBasicParsing
    }
    Assert-SignedBy $download 'Microsoft'

    if (Test-Path -LiteralPath $extract -PathType Container) {
        Remove-Item -LiteralPath $extract -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    $unpack = Start-Process -FilePath $download -ArgumentList @('/Q', ('/T:"{0}"' -f $extract)) -Wait -PassThru
    if ($unpack.ExitCode -ne 0) { throw "DirectX extraction failed: $($unpack.ExitCode)" }

    $setup = Join-Path $extract 'DXSETUP.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'DXSETUP.exe was not found in the signed Microsoft package.' }

    if ($script:isElevated) {
        $process = Start-Process -FilePath $setup -ArgumentList '/silent' -Wait -PassThru
    } else {
        Write-Host 'DirectX needs administrator permission; approve the Windows UAC prompt.'
        $process = Start-Process -FilePath $setup -ArgumentList '/silent' -Verb RunAs -Wait -PassThru
    }
    if ($process.ExitCode -ne 0) { throw "DirectX setup failed: $($process.ExitCode)" }

    $after = Test-DirectXLegacyFilesPresent
    if (-not $after.Present) {
        $sample = @($after.Missing | Select-Object -First 8)
        throw ('DirectX setup returned success, but the expected legacy component set is incomplete. Missing examples: ' + ($sample -join '; '))
    }

    Set-DirectXLegacyState
    Add-Record 'INSTALLED' "DirectX June 2010 package $directXPackageVersion completed and legacy component set was verified"
}


function Get-OverwolfEntries {
    return @(
        Get-UninstallEntries |
        Where-Object {
            $n = [string]$_.DisplayName
            -not [string]::IsNullOrWhiteSpace($n) -and
            $n -match '(?i)^Overwolf($|\s)'
        }
    )
}

function Test-OverwolfPresent {
    if (@(Get-OverwolfEntries).Count -gt 0) { return $true }

    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA 'Overwolf\OverwolfLauncher.exe'),
        (Join-Path $env:LOCALAPPDATA 'Overwolf\Overwolf.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Overwolf\OverwolfLauncher.exe' }),
        (Join-Path $env:ProgramFiles 'Overwolf\OverwolfLauncher.exe')
    )) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
    }

    return $false
}

function Split-RegisteredCommandLine([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }

    $s = $CommandLine.Trim()
    if ($s -match '^"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1]; Arguments = $matches[2] }
    }

    # Unquoted executable path with no spaces.
    if ($s -match '^(\S+\.exe)\s*(.*)$') {
        return [pscustomobject]@{ FilePath = $matches[1]; Arguments = $matches[2] }
    }

    return $null
}

function Invoke-QuietUninstallEntry($Entry, [string]$Label) {
    $display = [string]$Entry.DisplayName
    $quiet = [string]$Entry.QuietUninstallString
    $normal = [string]$Entry.UninstallString

    # MSI product code path is deterministic even when QuietUninstallString is absent.
    if ($normal -match '(?i)MsiExec(?:\.exe)?\s+/[IX]\s*({[0-9A-Fa-f-]+})') {
        $productCode = $matches[1]
        Write-Host ("[{0}] MSI uninstall: {1}" -f $Label,$display)
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
            -ArgumentList @('/x',$productCode,'/qn','/norestart') -Wait -PassThru
        if ($p.ExitCode -notin @(0,1605,1614,3010)) {
            throw "$Label uninstall failed for '$display' (MSI exit $($p.ExitCode))."
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($quiet)) {
        throw "$Label '$display' is installed but exposes no QuietUninstallString; refusing to guess an interactive uninstall switch."
    }

    $cmd = Split-RegisteredCommandLine $quiet
    if ($null -eq $cmd -or -not (Test-Path -LiteralPath $cmd.FilePath -PathType Leaf)) {
        throw "$Label '$display' exposes a QuietUninstallString that could not be parsed safely: $quiet"
    }

    Write-Host ("[{0}] Quiet uninstall: {1}" -f $Label,$display)
    $args = if ([string]::IsNullOrWhiteSpace($cmd.Arguments)) { @() } else { $cmd.Arguments }
    $p = Start-Process -FilePath $cmd.FilePath -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -notin @(0,3010)) {
        throw "$Label quiet uninstall failed for '$display' (exit $($p.ExitCode))."
    }
}

function Remove-OverwolfStrict {
    if (-not (Test-OverwolfPresent)) {
        Write-Host '[BUNDLE GUARD] Overwolf absent.'
        return
    }

    Write-Host '[BUNDLE GUARD] Overwolf detected; removing bundled platform...' -ForegroundColor Yellow

    $entries = @(Get-OverwolfEntries)
    if ($entries.Count -eq 0) {
        throw 'Overwolf executable was detected but no uninstall entry exists; automatic cleanup cannot be verified safely.'
    }

    foreach ($entry in $entries) {
        Invoke-QuietUninstallEntry -Entry $entry -Label 'OVERWOLF'
    }

    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and (Test-OverwolfPresent)) {
        Start-Sleep -Seconds 2
    }

    if (Test-OverwolfPresent) {
        throw 'Overwolf is still present after the registered quiet uninstall completed.'
    }

    Write-Host '[BUNDLE GUARD] Overwolf removal verified.' -ForegroundColor Green
}

function Invoke-TeamSpeakClean {
    $targetVersion = '3.6.2'
    $installerUrl = 'https://files.teamspeak-services.com/releases/client/3.6.2/TeamSpeak3-Client-win64-3.6.2.exe'
    $expectedSha256 = 'EAB9E0C1A7134643E5F7116B7E0E58FAFFB20D6DB528F8B333D2C2B5D1AB68AE'
    $installer = Join-Path $logDir 'TeamSpeak3-Client-win64-3.6.2.exe'

    $installedVersion = Get-TeamSpeakInstalledVersion
    if ($installedVersion -eq $targetVersion) {
        Remove-OverwolfStrict
        Add-Record 'ALREADY INSTALLED' 'TeamSpeak 3.6.2 verified; Overwolf absent'
        return
    }

    if ($installedVersion) {
        throw "TeamSpeak is present at version $installedVersion, but this baseline is pinned to $targetVersion. Refusing an in-place version change."
    }

    if ($Preview) {
        Add-Record 'PREVIEW' 'Would install official TeamSpeak 3.6.2 with /S /CURRENTUSER and without the /Overwolf opt-in switch'
        return
    }

    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        Write-Host 'Downloading official TeamSpeak 3.6.2 installer...'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installer -UseBasicParsing
    }

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash
    if ($hash -ne $expectedSha256) {
        throw "TeamSpeak installer SHA-256 mismatch. Expected $expectedSha256, got $hash"
    }
    Assert-SignedBy $installer 'TeamSpeak'

    # TeamSpeak's installer uses /Overwolf as the explicit opt-in. We omit it.
    $p = Start-Process -FilePath $installer -ArgumentList @('/S','/CURRENTUSER') -Wait -PassThru
    if ($p.ExitCode -notin @(0,3010)) {
        throw "TeamSpeak 3.6.2 installer failed with exit code $($p.ExitCode)."
    }

    $deadline = (Get-Date).AddSeconds(60)
    do {
        $installedVersion = Get-TeamSpeakInstalledVersion
        if ($installedVersion -eq $targetVersion) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if ($installedVersion -ne $targetVersion) {
        throw "TeamSpeak installer completed, but pinned version $targetVersion could not be verified."
    }

    # Fail closed if any bundled Overwolf platform appeared despite the opt-out path.
    Remove-OverwolfStrict

    Add-Record 'INSTALLED / VERIFIED' 'TeamSpeak 3.6.2 installed from official signed installer; /Overwolf was not used; Overwolf absent'
}

function Enforce-FaceitACOnlyStable([string]$wingetPath) {
    # FACEIT's AC bootstrapper can finish chained installs asynchronously.
    # Enforce the desired final state for a full settling window.
    $deadline = (Get-Date).AddSeconds(180)
    $stableSince = $null

    while ((Get-Date) -lt $deadline) {
        if (-not (Test-FaceitPresent)) {
            throw 'FACEIT Anti-Cheat disappeared while enforcing the AC-only final state.'
        }

        if (Test-FaceitPlatformClientPresent) {
            $stableSince = $null
            Remove-FaceitPlatformClient -wingetPath $wingetPath
            Start-Sleep -Seconds 3
            continue
        }

        if ($null -eq $stableSince) {
            $stableSince = Get-Date
        }

        if ((Get-Date) -ge $stableSince.AddSeconds(30)) {
            Write-Host '[FACEIT] AC-only state remained stable for 30 seconds.' -ForegroundColor Green
            return
        }

        Start-Sleep -Seconds 3
    }

    if (Test-FaceitPlatformClientPresent) {
        throw 'FACEIT platform client reappeared during the AC-only stabilization window.'
    }
    if (-not (Test-FaceitPresent)) {
        throw 'FACEIT Anti-Cheat final verification failed.'
    }
}

function Invoke-BundleGuard([string]$wingetPath) {
    Remove-OverwolfStrict

    if (Test-FaceitPlatformClientPresent) {
        Write-Host '[BUNDLE GUARD] FACEIT platform client detected late; removing it...' -ForegroundColor Yellow
        Remove-FaceitPlatformClient -wingetPath $wingetPath
    }

    if (Test-FaceitPlatformClientPresent) {
        throw 'Bundled-extras guard failed: FACEIT platform client is still installed.'
    }
    if (Test-OverwolfPresent) {
        throw 'Bundled-extras guard failed: Overwolf is still installed.'
    }

    Add-Record 'VERIFIED' 'Overwolf absent; separate FACEIT platform client absent'
}


function Invoke-ExitLag {
    if (Test-ExitLagPresent) {
        Add-Record 'ALREADY INSTALLED' 'ExitLag registry/executable detected; installer skipped'
        return
    }

    $localInstaller = Join-Path $root 'ExitLag-installer.exe'

    if (-not (Test-Path -LiteralPath $localInstaller -PathType Leaf)) {
        Write-Host 'ExitLag is a manual/optional final step.'
        Write-Host 'Opening the official download page. Install it whenever you want.'
        Write-Host ('If you want this script to install it on a later rerun, save the official installer as: ' + $localInstaller)
        try {
            Start-Process 'https://www.exitlag.com/download/' -ErrorAction Stop
        } catch {
            Write-Warning ('Could not open the ExitLag page automatically: ' + $_.Exception.Message)
        }
        Add-Record 'DEFERRED / MANUAL' 'ExitLag installer is not present; all automated application steps were allowed to complete'
        return
    }

    try {
        Assert-SignedBy $localInstaller 'ExitLag'
    } catch {
        Write-Warning $_.Exception.Message
        Add-Record 'DEFERRED / MANUAL' ('Local ExitLag installer was not executed because its signature could not be verified: ' + $_.Exception.Message)
        return
    }

    $process = Start-Process -FilePath $localInstaller -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        if (Test-ExitLagPresent) {
            Add-Record 'INSTALLED / VERIFIED' ("ExitLag installer returned $($process.ExitCode), but ExitLag is verified present")
            return
        }
        Write-Warning ("ExitLag installer returned $($process.ExitCode). This optional step will not fail the rest of the application baseline.")
        Add-Record 'DEFERRED / MANUAL' ("ExitLag installer returned $($process.ExitCode) and installation could not be verified")
        return
    }

    if (-not (Test-ExitLagPresent)) {
        Add-Record 'DEFERRED / MANUAL' 'ExitLag installer exited, but installed state could not be verified'
        return
    }

    if ($process.ExitCode -eq 3010) {
        Add-Record 'INSTALLED / REBOOT REQUIRED' 'ExitLag verified after installer completion; installer requested reboot (3010)'
        return
    }

    Add-Record 'INSTALLED' 'ExitLag verified after installer completion'
}


function Test-FaceitPlatformClientPresent {
    # Prefer the distinct WinGet package identity when correlation is available.
    try {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            $oldPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $out = & $winget.Source list --id FACEITLTD.FACEITClient --exact --accept-source-agreements 2>&1
                $code = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $oldPreference
            }
            if ($code -eq 0 -and (($out | Out-String) -match '(?i)FACEITLTD\.FACEITClient|(^|\s)FACEIT(\s|$)')) {
                return $true
            }
        }
    } catch { }

    # Fallback: match the platform client, but deliberately exclude AC entries.
    $entry = Get-UninstallEntries | Where-Object {
        $n = [string]$_.DisplayName
        $n -match '(?i)^FACEIT($|\s|Client)' -and
        $n -notmatch '(?i)Anti.?Cheat|FACEIT\s*AC'
    } | Select-Object -First 1
    return ($null -ne $entry)
}

function Remove-FaceitPlatformClient([string]$wingetPath) {
    if (-not (Test-FaceitPlatformClientPresent)) {
        Write-Host '[FACEIT] Separate platform client not detected after Anti-Cheat installation.'
        return
    }

    Write-Host '[FACEIT] Separate FACEIT platform client detected; removing it while preserving Anti-Cheat...'

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $wingetPath uninstall --id FACEITLTD.FACEITClient --exact --silent --disable-interactivity 2>&1 |
            Out-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    # Some publisher bootstrappers finish child installs asynchronously.
    # Give Apps & Features / WinGet correlation time to settle before declaring failure.
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and (Test-FaceitPlatformClientPresent)) {
        Start-Sleep -Seconds 2
    }

    if (Test-FaceitPlatformClientPresent) {
        throw "FACEIT platform client is still present after targeted uninstall attempt (WinGet exit $code)."
    }

    if (-not (Test-FaceitPresent)) {
        throw 'FACEIT platform client was removed, but FACEIT Anti-Cheat is no longer verified present. AC-only final state was not achieved.'
    }

    Write-Host '[FACEIT] AC-only final state verified: platform client absent, Anti-Cheat present.'
}

function Invoke-FaceitACOnly([string]$wingetPath) {
    if (-not (Test-FaceitPresent)) {
        Write-Host '[FACEIT] Installing FACEIT Anti-Cheat package...'

        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $wingetPath install --id FACEITLTD.FACEITAC --exact --source winget `
                --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 |
                Out-Host
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        # Publisher installer can spawn/chain child installers. Verify the intended
        # Anti-Cheat state instead of trusting only WinGet's exit code.
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline -and -not (Test-FaceitPresent)) {
            Start-Sleep -Seconds 2
        }

        if (-not (Test-FaceitPresent)) {
            throw "FACEIT Anti-Cheat could not be verified after WinGet installation (exit $code)."
        }

        Write-Host '[FACEIT] Anti-Cheat verified present.'
    } else {
        Write-Host '[FACEIT] Anti-Cheat already present.'
    }

    # The publisher bootstrapper can chain the separate FACEIT platform client
    # after the AC itself has already registered. Do not trust a single early
    # check; enforce and observe the desired final state until it stays stable.
    Enforce-FaceitACOnlyStable -wingetPath $wingetPath

    Add-Record 'INSTALLED / VERIFIED' 'FACEIT Anti-Cheat present; separate FACEIT platform client absent after stabilization window'
}

function Invoke-SpotifyFromElevatedSession {
    if (Test-SpotifyPresent) {
        Add-Record 'ALREADY INSTALLED' 'Spotify registry/executable detected; installer skipped'
        return
    }

    $worker = Join-Path $PSScriptRoot 'Install-Spotify-Unelevated.ps1'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) { throw "Spotify helper missing: $worker" }
    $taskName = 'PostFormat-Spotify-' + [guid]::NewGuid().ToString('N')
    $resultFile = Join-Path $logDir ($taskName + '.json')
    $workerLog = Join-Path $logDir ($taskName + '.log')
    $taskCreated = $false

    try {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $ps = Join-Path $PSHOME 'powershell.exe'
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -ResultFile "{1}" -LogFile "{2}"' -f $worker, $resultFile, $workerLog
        $action = New-ScheduledTaskAction -Execute $ps -Argument $arguments -WorkingDirectory $root
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        $taskCreated = $true
        Write-Host "Spotify: starting under the logged-in user's limited account; waiting for completion..."
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $deadline = (Get-Date).AddMinutes(30)
        $startedWaiting = Get-Date

        while (-not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
            if ((Get-Date) -ge $deadline) { throw "Spotify did not finish within 30 minutes. Task: $taskName; log: $workerLog" }
            Start-Sleep -Seconds 2
            if ((Get-Date) -ge $startedWaiting.AddSeconds(20)) {
                $state = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
                if ($state.State -eq 'Ready' -and $info.LastTaskResult -notin @(0, 267009)) {
                    throw "Spotify worker failed to start or finish. Task result: $($info.LastTaskResult); log: $workerLog"
                }
                if ($state.State -eq 'Ready' -and (Get-Date) -ge $startedWaiting.AddSeconds(60)) {
                    throw "Spotify task ended without a result file. Task result: $($info.LastTaskResult); log: $workerLog"
                }
            }
        }

        $outcome = Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($outcome.ExitCode -ne 0) { throw "Spotify failed in limited user session: $($outcome.Detail). Log: $workerLog" }
        Add-Record $outcome.Status "Spotify.Spotify; $($outcome.Detail). Log: $workerLog"
    } finally {
        if ($taskCreated) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

function New-UrlShortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url
    )

    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcut = Join-Path $programs ($Name + '.url')

    New-Item -ItemType Directory -Path $programs -Force | Out-Null
    "[InternetShortcut]`r`nURL=$Url`r`n" | Out-File -LiteralPath $shortcut -Encoding ASCII

    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
        throw "URL shortcut could not be created: $shortcut"
    }

    return $shortcut
}

function Open-UrlAsInteractiveUser {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Label
    )

    # Post-format normally runs elevated. Use a temporary scheduled task with the
    # same logged-in user at Limited integrity so the default browser launches in
    # the normal desktop session instead of inheriting administrator elevation.
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskName = 'PostFormat-OpenUrl-' + [guid]::NewGuid().ToString('N')
    $taskCreated = $false

    try {
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $escaped = $Url.Replace("'", "''")
        $arguments = "-NoLogo -NoProfile -WindowStyle Hidden -Command `"Start-Process '$escaped'`""

        $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Principal $principal `
            -Settings $settings `
            -Force `
            -ErrorAction Stop | Out-Null

        $taskCreated = $true
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Start-Sleep -Seconds 3

        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
        if ($info.LastTaskResult -notin @(0,267009)) {
            throw "$Label browser-launch task returned $($info.LastTaskResult)."
        }

        Write-Host ("[OPENED] {0}: {1}" -f $Label,$Url) -ForegroundColor Green
    }
    finally {
        if ($taskCreated) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-PeripheralSetupPages {
    $wootilityUrl = 'https://v5.wootility.io/'
    $logitechOmmUrl = 'https://support.logi.com/hc/en-us/articles/29742998779415-Onboard-Memory-Manager'

    $wootShortcut = New-UrlShortcut -Name 'Wootility Web' -Url $wootilityUrl
    $logitechShortcut = New-UrlShortcut -Name 'Logitech Onboard Memory Manager' -Url $logitechOmmUrl

    if ($Preview) {
        Add-Record 'PREVIEW' ("Would open Wootility Web + Logitech OMM and create shortcuts: $wootShortcut ; $logitechShortcut")
        return
    }

    Open-UrlAsInteractiveUser -Url $wootilityUrl -Label 'Wootility Web'
    Start-Sleep -Seconds 1
    Open-UrlAsInteractiveUser -Url $logitechOmmUrl -Label 'Logitech Onboard Memory Manager'

    Add-Record 'OPENED / SHORTCUTS CREATED' ("Wootility Web and Logitech OMM pages opened in the normal user session; shortcuts: $wootShortcut ; $logitechShortcut")
}

try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'WinGet is missing. Install/update App Installer from Microsoft Store, then rerun.' }

    Write-Host ('WinGet: ' + (& $winget.Source --version))
    Write-Host ('Mode: ' + $(if ($Preview) { 'PREVIEW' } else { 'INSTALL' }))

    if (-not $Preview) {
        $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
        $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isElevated -and -not (Test-SpotifyPresent)) {
            if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Install-Spotify-Unelevated.ps1') -PathType Leaf)) {
                throw 'Spotify helper is missing from the .scripts folder. No installation steps were started.'
            }
            if ((Get-Service -Name Schedule -ErrorAction Stop).Status -ne 'Running') {
                throw 'Task Scheduler must be running to install Spotify from an administrator session. No installation steps were started.'
            }
            foreach ($command in @('New-ScheduledTaskAction', 'New-ScheduledTaskPrincipal', 'New-ScheduledTaskSettingsSet', 'Register-ScheduledTask', 'Start-ScheduledTask', 'Get-ScheduledTask', 'Get-ScheduledTaskInfo', 'Unregister-ScheduledTask')) {
                if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "ScheduledTasks command missing: $command. No installation steps were started." }
            }
        }
    }

    if ($Preview) {
        foreach ($step in $steps) {
            $index++
            $currentStep = $step.Name
            Add-Record 'PREVIEW' $step.Kind
        }
    } else {
        foreach ($step in $steps) {
            $index++
            $currentStep = $step.Name
            Write-Host ("Starting [$index/$($steps.Count)] $currentStep")

            if ($step.Id -eq 'Spotify.Spotify' -and $isElevated) {
                Invoke-SpotifyFromElevatedSession
                continue
            }

            switch ($step.Kind) {
                'Winget' { Invoke-Winget $step $winget.Source }
                'DirectX' { Invoke-DirectX }
                'FaceitACOnly' { Invoke-FaceitACOnly $winget.Source }
                'TeamSpeakClean' { Invoke-TeamSpeakClean }
                'BundleGuard' { Invoke-BundleGuard $winget.Source }
                'ExitLag' { Invoke-ExitLag }
                'PeripheralPages' { Invoke-PeripheralSetupPages }
                default { throw "Unknown step type: $($step.Kind)" }
            }
        }
    }
} catch {
    $exitCode = 1
    if (-not $currentStep) { $currentStep = 'PREFLIGHT'; $index = 0; $exitCode = 2 }
    Add-Record 'FAILED - STOPPED' $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $logDir -PathType Container) {
        $lines = @(
            'POST-FORMAT GAMING APPLICATION REPORT',
            ('Started: ' + $started.ToString('o')),
            ('Finished: ' + (Get-Date).ToString('o')),
            ('Mode: ' + $(if ($Preview) { 'PREVIEW' } else { 'INSTALL' })),
            ('Final exit code: ' + $exitCode),
            ('Completed steps: ' + @($records | Where-Object { $_ -notmatch '\| (FAILED|PREVIEW)' }).Count),
            ''
        ) + $records.ToArray() + @(
            '',
            'REV12 behavior: every automated step is checked before installation; already-present software is skipped.',
            'Every installer attempt is also followed by a presence/version verification before the script continues.',
            'Unversioned applications are install-only: REV12 does not upgrade them just because a newer version exists.',
            'TeamSpeak remains pinned to 3.6.2 and is installed directly without the /Overwolf opt-in switch; Overwolf is forbidden by final-state verification.',
            'Peripheral setup opens Wootility Web and the official Logitech Onboard Memory Manager page in the normal interactive user session and creates Start Menu URL shortcuts.',
            'Automated application failures remain fail-closed. FACEIT is enforced to an AC-only final state with a stabilization window; Overwolf and the separate FACEIT platform client are forbidden final-state bundles. ExitLag remains manual/optional.',
            'No GPU drivers, RGB tools, debug tools, CS2 tweaks, CS2 or KovaaKs are installed here.'
        )
        $lines | Out-File -LiteralPath $report -Encoding UTF8
        Write-Host ('Report: ' + $report)
    }
}

exit $exitCode
