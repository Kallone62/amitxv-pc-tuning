#requires -RunAsAdministrator
<#
.SYNOPSIS
  Conservative background-task cleanup for the gaming baseline.

.DESCRIPTION
  Default mode is Apply.

  Apply:
    - Disables Google Updater scheduled tasks.
    - Disables Google Platform Experience Helper scheduled tasks.
    - Disables only clearly Teams-client scheduled tasks when their task/action
      metadata explicitly identifies Microsoft Teams.
    - Sets Microsoft Edge Update / WebView2 automatic update-check minimum
      interval to 24 hours (1440 minutes) using the supported Edge Update policy.

  Intentionally NOT changed:
    - Microsoft Edge / WebView2 scheduled task definitions or triggers.
    - Windows servicing tasks.
    - SecurityHealth.
    - Steam / Spotify startup.
    - SoftLanding task.
    - Any Windows networking/device/service topology.

  The Edge/WebView2 policy limits automatic update checks; the updater's own
  scheduled task may still wake briefly and exit without performing a network
  update check until the configured interval has elapsed.

  Restore:
    - Re-enables only tasks this script itself disabled.
    - Restores the previous Edge Update policy value (or removes it if absent).

.PARAMETER Mode
  Apply (default), Audit, or Restore.

.PARAMETER EdgeUpdateCheckMinutes
  Minimum interval between automatic Microsoft Edge Update checks.
  Default: 1440 (24 hours).

.EXAMPLE
  .\Gaming-Background-Cleanup-v1.ps1

.EXAMPLE
  .\Gaming-Background-Cleanup-v1.ps1 -Mode Audit

.EXAMPLE
  .\Gaming-Background-Cleanup-v1.ps1 -Mode Restore
#>

[CmdletBinding()]
param(
    [ValidateSet('Apply','Audit','Restore')]
    [string]$Mode = 'Apply',

    [ValidateRange(60,43200)]
    [int]$EdgeUpdateCheckMinutes = 1440
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateDir  = Join-Path $env:ProgramData 'GamingDeviceBaseline\BackgroundCleanup'
$StateFile = Join-Path $StateDir 'background-cleanup-state.json'
$LogFile   = Join-Path $StateDir 'background-cleanup.log'

$EdgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
$EdgePolicyName = 'AutoUpdateCheckPeriodMinutes'

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line
}

function Get-TaskActionText {
    param([Parameter(Mandatory)]$Task)

    $parts = @()
    foreach ($action in @($Task.Actions)) {
        if ($null -eq $action) { continue }

        $execute = ''
        $args = ''
        try { $execute = [string]$action.Execute } catch {}
        try { $args = [string]$action.Arguments } catch {}

        $parts += (($execute + ' ' + $args).Trim())
    }

    return (($parts | Where-Object { $_ }) -join ' | ')
}

function Get-CandidateTasks {
    $tasks = @(Get-ScheduledTask -ErrorAction Stop)

    foreach ($task in $tasks) {
        $path = [string]$task.TaskPath
        $name = [string]$task.TaskName
        $actionText = Get-TaskActionText -Task $task
        $meta = ('{0}{1} {2}' -f $path,$name,$actionText)

        $category = $null

        if ($path -like '\GoogleSystem\GoogleUpdater\*') {
            $category = 'Google Updater'
        }
        elseif ($path -like '\GoogleUserPEH\*') {
            $category = 'Google Platform Experience Helper'
        }
        else {
            # Teams safety rule:
            # Do not disable a generic Microsoft/Windows task simply because its
            # display name contains "Teams". Require explicit Teams-client evidence.
            $teamsEvidence = (
                $meta -match '(?i)(ms-teams\.exe|MSTeams|Teams\.exe|Microsoft Teams)'
            )

            if ($teamsEvidence) {
                $category = 'Microsoft Teams client'
            }
        }

        if ($null -ne $category) {
            [pscustomobject]@{
                Category = $category
                TaskPath = $path
                TaskName = $name
                State    = [string]$task.State
                Actions  = $actionText
            }
        }
    }
}

function Get-State {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Log ("WARNING: Could not read state file: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Save-State {
    param(
        [Parameter(Mandatory)][object[]]$OwnedTasks,
        [Parameter(Mandatory)]$EdgePolicyState
    )

    $state = [pscustomobject]@{
        Version    = 1
        UpdatedAt  = (Get-Date).ToString('o')
        Computer   = $env:COMPUTERNAME
        OwnedTasks = @(
            $OwnedTasks |
            Group-Object { ('{0}|{1}' -f $_.TaskPath,$_.TaskName).ToUpperInvariant() } |
            ForEach-Object { $_.Group[0] }
        )
        EdgePolicy = $EdgePolicyState
    }

    $tmp = "$StateFile.tmp"
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Get-CurrentEdgePolicy {
    $exists = $false
    $value = $null

    if (Test-Path -LiteralPath $EdgePolicyPath) {
        try {
            $p = Get-ItemProperty -LiteralPath $EdgePolicyPath -Name $EdgePolicyName -ErrorAction Stop
            $exists = $true
            $value = [int]$p.$EdgePolicyName
        }
        catch {}
    }

    return [pscustomobject]@{
        Exists = $exists
        Value  = $value
    }
}

function Set-EdgePolicy {
    param([Parameter(Mandatory)][int]$Minutes)

    New-Item -Path $EdgePolicyPath -Force | Out-Null
    New-ItemProperty `
        -Path $EdgePolicyPath `
        -Name $EdgePolicyName `
        -PropertyType DWord `
        -Value $Minutes `
        -Force | Out-Null
}

function Restore-EdgePolicy {
    param([Parameter(Mandatory)]$EdgeState)

    if (-not [bool]$EdgeState.Owned) {
        Write-Log 'Edge Update policy was not owned by this script; no restore action required.'
        return
    }

    if ([bool]$EdgeState.PreviousExists) {
        New-Item -Path $EdgePolicyPath -Force | Out-Null
        New-ItemProperty `
            -Path $EdgePolicyPath `
            -Name $EdgePolicyName `
            -PropertyType DWord `
            -Value ([int]$EdgeState.PreviousValue) `
            -Force | Out-Null

        Write-Log ("Restored Edge Update policy to previous value: {0} minutes" -f $EdgeState.PreviousValue)
    }
    else {
        if (Test-Path -LiteralPath $EdgePolicyPath) {
            Remove-ItemProperty -LiteralPath $EdgePolicyPath -Name $EdgePolicyName -ErrorAction SilentlyContinue
        }
        Write-Log 'Removed Edge Update interval policy because it did not exist before this script.'
    }
}

Write-Host ''
Write-Host '=== Gaming Background Cleanup v1 ===' -ForegroundColor Cyan
Write-Host ('Mode                    : {0}' -f $Mode)
Write-Host ('Edge/WebView2 check min : {0} minutes' -f $EdgeUpdateCheckMinutes)
Write-Host ''

if ($Mode -eq 'Restore') {
    $state = Get-State

    if ($null -eq $state) {
        Write-Host 'No saved state found; nothing to restore.' -ForegroundColor Yellow
        exit 0
    }

    $failures = 0

    foreach ($item in @($state.OwnedTasks)) {
        try {
            $task = Get-ScheduledTask -TaskName ([string]$item.TaskName) -TaskPath ([string]$item.TaskPath) -ErrorAction Stop

            if ([string]$task.State -eq 'Disabled') {
                Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
                Write-Log ("REENABLED task: {0}{1}" -f $item.TaskPath,$item.TaskName)
            }
            else {
                Write-Log ("Task already enabled/not-disabled: {0}{1}" -f $item.TaskPath,$item.TaskName)
            }
        }
        catch {
            $failures++
            Write-Log ("FAILED to restore task {0}{1}: {2}" -f $item.TaskPath,$item.TaskName,$_.Exception.Message)
        }
    }

    try {
        Restore-EdgePolicy -EdgeState $state.EdgePolicy
    }
    catch {
        $failures++
        Write-Log ("FAILED to restore Edge Update policy: {0}" -f $_.Exception.Message)
    }

    if ($failures -gt 0) {
        Write-Host ''
        Write-Host ("Restore completed with {0} failure(s)." -f $failures) -ForegroundColor Red
        exit 1
    }

    Write-Host ''
    Write-Host 'Restore completed.' -ForegroundColor Green
    exit 0
}

$candidates = @(Get-CandidateTasks)
$currentPolicy = Get-CurrentEdgePolicy

Write-Host 'Candidate scheduled tasks:' -ForegroundColor Green
if ($candidates.Count -eq 0) {
    Write-Host '  None matched.'
}
else {
    $candidates |
        Select-Object Category,TaskPath,TaskName,State,Actions |
        Format-Table -AutoSize
}

Write-Host ''
Write-Host ('Current Edge Update policy : {0}' -f $(if ($currentPolicy.Exists) { "$($currentPolicy.Value) minutes" } else { 'Not configured (default updater behavior)' }))

if ($Mode -eq 'Audit') {
    Write-Host ''
    Write-Host 'AUDIT ONLY: nothing was changed.' -ForegroundColor Cyan
    exit 0
}

$existingState = Get-State
$ownedTasks = @()
$edgeState = $null

if ($null -ne $existingState) {
    $ownedTasks = @($existingState.OwnedTasks)
    $edgeState = $existingState.EdgePolicy
}

# Preserve original Edge policy ownership only once.
if ($null -eq $edgeState) {
    if ($currentPolicy.Exists -and $currentPolicy.Value -eq $EdgeUpdateCheckMinutes) {
        $edgeState = [pscustomobject]@{
            Owned          = $false
            PreviousExists = $true
            PreviousValue  = $currentPolicy.Value
        }
    }
    else {
        $edgeState = [pscustomobject]@{
            Owned          = $true
            PreviousExists = $currentPolicy.Exists
            PreviousValue  = $currentPolicy.Value
        }
    }
}

$ownedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $ownedTasks) {
    [void]$ownedKeys.Add(('{0}|{1}' -f $item.TaskPath,$item.TaskName))
}

$newlyDisabled = 0
$alreadyOwned = 0
$alreadyExternal = 0
$failures = 0

foreach ($candidate in $candidates) {
    $key = ('{0}|{1}' -f $candidate.TaskPath,$candidate.TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $candidate.TaskName -TaskPath $candidate.TaskPath -ErrorAction Stop

        if ([string]$task.State -eq 'Disabled') {
            if ($ownedKeys.Contains($key)) {
                $alreadyOwned++
                Write-Log ("ALREADY DISABLED (managed): {0}{1}" -f $candidate.TaskPath,$candidate.TaskName)
            }
            else {
                $alreadyExternal++
                Write-Log ("ALREADY DISABLED (external/manual): {0}{1}" -f $candidate.TaskPath,$candidate.TaskName)
            }
            continue
        }

        Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null

        $entry = [pscustomobject]@{
            Category = $candidate.Category
            TaskPath = $candidate.TaskPath
            TaskName = $candidate.TaskName
            DisabledAt = (Get-Date).ToString('o')
        }

        $ownedTasks += $entry
        [void]$ownedKeys.Add($key)
        $newlyDisabled++
        Write-Log ("DISABLED task: {0}{1} [{2}]" -f $candidate.TaskPath,$candidate.TaskName,$candidate.Category)
    }
    catch {
        $failures++
        Write-Log ("FAILED task {0}{1}: {2}" -f $candidate.TaskPath,$candidate.TaskName,$_.Exception.Message)
    }
}

try {
    $now = Get-CurrentEdgePolicy
    if (-not $now.Exists -or $now.Value -ne $EdgeUpdateCheckMinutes) {
        Set-EdgePolicy -Minutes $EdgeUpdateCheckMinutes
        Write-Log ("SET Edge Update minimum automatic check interval: {0} minutes" -f $EdgeUpdateCheckMinutes)
    }
    else {
        Write-Log ("Edge Update interval already set to {0} minutes." -f $EdgeUpdateCheckMinutes)
    }
}
catch {
    $failures++
    Write-Log ("FAILED to set Edge Update policy: {0}" -f $_.Exception.Message)
}

Save-State -OwnedTasks $ownedTasks -EdgePolicyState $edgeState

Write-Host ''
Write-Host ('Newly disabled tasks       : {0}' -f $newlyDisabled) -ForegroundColor Green
Write-Host ('Already disabled (managed) : {0}' -f $alreadyOwned)
Write-Host ('Already disabled (external): {0}' -f $alreadyExternal)
Write-Host ('Failures                   : {0}' -f $failures)
Write-Host ('State file                 : {0}' -f $StateFile)
Write-Host ('Log file                   : {0}' -f $LogFile)
Write-Host ''
Write-Host ('Edge/WebView2 automatic update checks are limited to no more often than every {0} hours.' -f [math]::Round($EdgeUpdateCheckMinutes/60,2))
Write-Host 'The Microsoft updater task definitions themselves are intentionally left stock.' -ForegroundColor Yellow

if ($failures -gt 0) {
    exit 1
}

exit 0
