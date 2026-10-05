#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$ResultFile,
    [Parameter(Mandatory = $true)][string]$LogFile
)

$ErrorActionPreference = 'Stop'
$outcome = @{ ExitCode = 1; Status = 'FAILED'; Detail = 'Spotify worker did not complete' }

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

try {
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Limited user task is still elevated; Spotify cannot run as administrator.'
    }

    if (Test-SpotifyPresent) {
        $outcome = @{ ExitCode = 0; Status = 'ALREADY INSTALLED'; Detail = 'Spotify registry/executable already present; installer skipped' }
    } else {
        $winget = Get-Command winget.exe -ErrorAction Stop
        $args = @('install', '--id', 'Spotify.Spotify', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')

        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $winget.Source @args 2>&1 | Tee-Object -FilePath $LogFile
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        Start-Sleep -Seconds 1
        if (Test-SpotifyPresent) {
            if ($code -eq 0) {
                $outcome = @{ ExitCode = 0; Status = 'INSTALLED'; Detail = 'Spotify installation completed and presence was verified' }
            } else {
                $outcome = @{ ExitCode = 0; Status = 'INSTALLED / VERIFIED'; Detail = "WinGet returned $code, but Spotify is verified present" }
            }
        } elseif ($code -eq 3010) {
            throw 'Installer requested restart (3010); restart and rerun the CMD.'
        } elseif ($code -eq -1978335226) {
            throw "WinGet ShellExecute failed (0x8A150006 / $code), and Spotify is not present."
        } elseif ($code -ne 0) {
            throw "WinGet failed (exit $code), and Spotify is not present."
        } else {
            throw 'WinGet returned success, but Spotify could not be verified after installation.'
        }
    }
} catch {
    $outcome = @{ ExitCode = 1; Status = 'FAILED'; Detail = $_.Exception.Message }
} finally {
    $tempFile = $ResultFile + '.tmp'
    try {
        $outcome | ConvertTo-Json -Compress | Out-File -LiteralPath $tempFile -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tempFile -Destination $ResultFile -Force -ErrorAction Stop
    } catch {
        Write-Error "Could not write Spotify result to $ResultFile`: $($_.Exception.Message)"
        exit 1
    }
}

exit $outcome.ExitCode
