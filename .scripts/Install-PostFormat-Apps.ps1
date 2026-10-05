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
    @{ Name = 'ExitLag'; Kind = 'ExitLag' },
    @{ Name = 'FACEIT Anti-Cheat'; Kind = 'Winget'; Id = 'FACEITLTD.FACEITAC' },
    @{ Name = 'Spotify'; Kind = 'Winget'; Id = 'Spotify.Spotify' },
    @{ Name = 'TeamSpeak 3.6.2'; Kind = 'Winget'; Id = 'TeamSpeakSystems.TeamSpeakClient'; Version = '3.6.2' },
    @{ Name = 'Wootility Web shortcut'; Kind = 'WootilityWeb' },
    @{ Name = 'Steam'; Kind = 'Winget'; Id = 'Valve.Steam' }
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

function Test-WootilityShortcutPresent {
    $shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Wootility Web.url'
    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) { return $false }
    try {
        $content = Get-Content -LiteralPath $shortcut -Raw -ErrorAction Stop
        return $content -match '(?im)^URL=https://wootility\.io/?\s*$'
    } catch {
        return $false
    }
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
        'FACEITLTD.FACEITAC' {
            if (Test-FaceitPresent) { return [pscustomobject]@{ Present = $true; Version = ''; Detail = 'FACEIT Anti-Cheat registry/executable detected' } }
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
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
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

function Invoke-ExitLag {
    if (Test-ExitLagPresent) {
        Add-Record 'ALREADY INSTALLED' 'ExitLag registry/executable detected; installer skipped'
        return
    }

    $localInstaller = Join-Path $root 'ExitLag-installer.exe'
    if (-not (Test-Path -LiteralPath $localInstaller -PathType Leaf)) {
        Write-Host 'ExitLag: open the official page, download the Windows installer, and save it as:'
        Write-Host ('  ' + $localInstaller)
        Write-Host 'The installer will wait here. It will NOT proceed to FACEIT until ExitLag completes.'
        Start-Process 'https://www.exitlag.com/download/'
        [void](Read-Host 'Press ENTER after saving the installer to the path above')
    }

    Assert-SignedBy $localInstaller 'ExitLag'
    $process = Start-Process -FilePath $localInstaller -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        if (Test-ExitLagPresent) {
            Add-Record 'INSTALLED / VERIFIED' "ExitLag installer returned $($process.ExitCode), but ExitLag is verified present"
            return
        }
        throw "ExitLag installer failed: $($process.ExitCode)"
    }
    if (-not (Test-ExitLagPresent)) { throw 'ExitLag installer exited but ExitLag was not found in installed applications or its expected path.' }
    if ($process.ExitCode -eq 3010) { throw 'ExitLag requested restart (3010). Restart, then rerun this CMD.' }
    Add-Record 'INSTALLED' 'ExitLag verified after installer completion'
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

function New-WootilityShortcut {
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcut = Join-Path $programs 'Wootility Web.url'

    if (Test-WootilityShortcutPresent) {
        Add-Record 'ALREADY PRESENT' $shortcut
        return
    }

    New-Item -ItemType Directory -Path $programs -Force | Out-Null
    "[InternetShortcut]`r`nURL=https://wootility.io/`r`n" | Out-File -LiteralPath $shortcut -Encoding ASCII
    if (-not (Test-WootilityShortcutPresent)) { throw 'Wootility Web shortcut could not be created or verified.' }
    Add-Record 'CREATED' $shortcut
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
                'ExitLag' { Invoke-ExitLag }
                'WootilityWeb' { New-WootilityShortcut }
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
            'REV8 behavior: every step is checked before installation; already-present software is skipped.',
            'Every installer attempt is also followed by a presence/version verification before the script continues.',
            'Unversioned applications are install-only: REV8 does not upgrade them just because a newer version exists.',
            'TeamSpeak remains pinned to 3.6.2.',
            'A failed step stops the sequence. Read its install and check logs, fix it, then rerun the CMD.',
            'No GPU drivers, RGB tools, debug tools, CS2 tweaks, CS2 or KovaaKs are installed here.'
        )
        $lines | Out-File -LiteralPath $report -Encoding UTF8
        Write-Host ('Report: ' + $report)
    }
}

exit $exitCode
