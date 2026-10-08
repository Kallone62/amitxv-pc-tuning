#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$ResultFile,
    [Parameter(Mandatory = $true)][string]$LogFile
)

$ErrorActionPreference = 'Stop'
$outcome = @{ ExitCode = 1; Status = 'FAILED'; Detail = 'Spotify worker did not complete' }

# WinGet HRESULTs observed as signed Int32 exit codes.
$WingetUnsupportedManifestVersion = -1978335225 # 0x8A150007
$WingetInstallerHashMismatch      = -1978335215 # 0x8A150011

function Test-SpotifyPresent {
    $spotifyExe = Join-Path $env:APPDATA 'Spotify\Spotify.exe'
    if (Test-Path -LiteralPath $spotifyExe -PathType Leaf) { return $true }

    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        if (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)^Spotify($|\s)' } |
            Select-Object -First 1) { return $true }
    }
    return $false
}

function Wait-SpotifyPresent {
    param([int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-SpotifyPresent) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return (Test-SpotifyPresent)
}

function Invoke-WingetSpotifyInstall {
    param([Parameter(Mandatory)][string]$WingetPath)

    $args = @(
        'install', '--id', 'Spotify.Spotify', '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity'
    )

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $WingetPath @args 2>&1 | Tee-Object -FilePath $LogFile -Append
        return [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Update-WingetSourceBestEffort {
    param([Parameter(Mandatory)][string]$WingetPath)

    Add-Content -LiteralPath $LogFile -Value '[Spotify] Refreshing WinGet source before one retry...'
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $WingetPath source update --name winget 2>&1 | Tee-Object -FilePath $LogFile -Append | Out-Host
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Assert-SpotifySignature {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }

    if ($signature.Status -ne 'Valid' -or
        -not $signature.SignerCertificate -or
        $subject -notmatch '(?i)(^|,\s*)CN=Spotify AB(,|$)') {
        throw "Official Spotify fallback signature verification failed. Status: $($signature.Status); signer: $subject"
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Add-Content -LiteralPath $LogFile -Value ("[Spotify] Official installer Authenticode OK; signer={0}; SHA256={1}" -f $subject,$hash)
}

function Invoke-OfficialSpotifyFallback {
    # WinGet's Spotify manifest uses Spotify's official CDN. We deliberately do
    # NOT use --ignore-security-hash. If the repository manifest is temporarily
    # too new for the inbox WinGet client or its vanity-URL hash has gone stale,
    # download the same publisher endpoint directly and require a valid Spotify AB
    # Authenticode signature before execution.
    $arch = [string]$env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        $uri = 'https://download.scdn.co/SpotifyFullSetupARM64.exe'
    } else {
        $uri = 'https://download.scdn.co/SpotifyFullSetupX64.exe'
    }

    $installer = Join-Path $env:TEMP ('PostFormat-Spotify-{0}.exe' -f [guid]::NewGuid().ToString('N'))
    try {
        Add-Content -LiteralPath $LogFile -Value ("[Spotify] WinGet manifest path unavailable; downloading official fallback: {0}" -f $uri)
        Invoke-WebRequest -Uri $uri -OutFile $installer -UseBasicParsing -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw 'Official Spotify fallback download did not produce an installer file.'
        }

        Assert-SpotifySignature -Path $installer

        $process = Start-Process -FilePath $installer -ArgumentList @('/silent','/skip-app-launch') -Wait -PassThru -ErrorAction Stop
        Add-Content -LiteralPath $LogFile -Value ("[Spotify] Official installer exit code: {0}" -f $process.ExitCode)

        if (Wait-SpotifyPresent -Seconds 120) {
            return [pscustomobject]@{
                Present = $true
                ExitCode = [int]$process.ExitCode
                Detail = 'official Spotify CDN fallback completed; valid Spotify AB signature and installed state verified'
            }
        }

        throw "Official Spotify installer finished with exit code $($process.ExitCode), but Spotify was not verified present within 120 seconds."
    }
    finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }
}

try {
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Limited user task is still elevated; Spotify cannot run as administrator.'
    }

    if (Test-SpotifyPresent) {
        $outcome = @{ ExitCode = 0; Status = 'ALREADY INSTALLED'; Detail = 'Spotify registry/executable already present; installer skipped' }
    }
    else {
        $winget = Get-Command winget.exe -ErrorAction Stop
        Add-Content -LiteralPath $LogFile -Value ("[Spotify] WinGet version: {0}" -f (& $winget.Source --version 2>$null))

        $code = Invoke-WingetSpotifyInstall -WingetPath $winget.Source

        if (-not (Test-SpotifyPresent) -and $code -in @($WingetUnsupportedManifestVersion,$WingetInstallerHashMismatch)) {
            if ($code -eq $WingetUnsupportedManifestVersion) {
                Add-Content -LiteralPath $LogFile -Value '[Spotify] WinGet 0x8A150007: manifest schema is newer than this client supports.'
            } else {
                Add-Content -LiteralPath $LogFile -Value '[Spotify] WinGet 0x8A150011: installer hash does not match the repository manifest.'
            }

            Update-WingetSourceBestEffort -WingetPath $winget.Source
            $code = Invoke-WingetSpotifyInstall -WingetPath $winget.Source
        }

        if (Wait-SpotifyPresent -Seconds 120) {
            if ($code -eq 0) {
                $outcome = @{ ExitCode = 0; Status = 'INSTALLED'; Detail = 'Spotify installation completed through WinGet and presence was verified' }
            } else {
                $outcome = @{ ExitCode = 0; Status = 'INSTALLED / VERIFIED'; Detail = "WinGet returned $code, but Spotify is verified present" }
            }
        }
        elseif ($code -in @($WingetUnsupportedManifestVersion,$WingetInstallerHashMismatch)) {
            $fallback = Invoke-OfficialSpotifyFallback
            $outcome = @{ ExitCode = 0; Status = 'INSTALLED / VERIFIED'; Detail = $fallback.Detail }
        }
        elseif ($code -eq 3010) {
            throw 'Installer requested restart (3010); restart and rerun the CMD.'
        }
        elseif ($code -eq -1978335226) {
            throw "WinGet ShellExecute failed (0x8A150006 / $code), and Spotify is not present."
        }
        elseif ($code -ne 0) {
            throw "WinGet failed (exit $code), and Spotify is not present."
        }
        else {
            throw 'WinGet returned success, but Spotify could not be verified after installation.'
        }
    }
}
catch {
    $outcome = @{ ExitCode = 1; Status = 'FAILED'; Detail = $_.Exception.Message }
}
finally {
    $tempFile = $ResultFile + '.tmp'
    try {
        $outcome | ConvertTo-Json -Compress | Out-File -LiteralPath $tempFile -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tempFile -Destination $ResultFile -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Could not write Spotify result to ${ResultFile}: $($_.Exception.Message)"
        exit 1
    }
}

exit $outcome.ExitCode
