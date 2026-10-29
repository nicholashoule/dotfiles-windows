# Turn on Windows' Developer Mode, which lets you create symbolic links without
# administrator rights, as homeskillet does to install itself and link files.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: enable-developer-mode.ps1 [-DryRun]
#
# Developer Mode is the AllowDevelopmentWithoutDevLicense value under
# HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock, the registry
# setting Microsoft documents beside the switch in Settings (For developers).
# Run this from a normal PowerShell 7, before installing homeskillet: when the
# value is not 1 yet, it starts itself again as administrator, which Windows
# asks you to approve, sets it, and reports the result here. homeskillet refuses
# to run as administrator, so only this write is elevated. Developer Mode also
# lets you install apps from any source; turn it off in Settings if you no
# longer want it. -DryRun reports whether anything would change.
# Exit status: 0 when Developer Mode is on, or would be turned on with -DryRun,
# 1 on failure, 2 for usage errors.
# Runs on PowerShell 7 on Windows.
# https://learn.microsoft.com/windows/apps/get-started/enable-your-device-for-development
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow. -Elevated marks the copy this helper starts as
# administrator, so that copy never starts another.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
param([switch]$DryRun, [switch]$Elevated, [switch]$Help)

$ErrorActionPreference = 'Stop'

$KeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$ValueName = 'AllowDevelopmentWithoutDevLicense'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("enable-developer-mode.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: enable-developer-mode.ps1 [-DryRun]'
    "Turns on Windows' Developer Mode, asking for administrator rights only to"
    'change it, so symbolic links work without them. -DryRun reports whether'
    'anything would change.'
}

# Test-DeveloperMode reports whether Developer Mode is on.
function Test-DeveloperMode {
    $value = Get-ItemProperty -LiteralPath $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
    $null -ne $value -and $value.$ValueName -eq 1
}

# Test-Administrator reports whether this process runs as administrator.
function Test-Administrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Invoke-Main checks the arguments and the current setting, then sets it here
# when running as administrator, or in a copy of this helper started as one.
function Invoke-Main {
    param([object[]]$Unexpected)
    if ($Help) {
        Write-Usage
        exit 0
    }
    if ($Unexpected.Count) {
        Write-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 2
    }
    if (-not $IsWindows) {
        Stop-Helper 'Developer Mode is a Windows setting'
    }
    if (Test-DeveloperMode) {
        'Developer Mode is already on.'
        exit 0
    }
    if ($DryRun) {
        'Would turn on Developer Mode, after Windows asks you to approve administrator rights.'
        exit 0
    }
    if (Test-Administrator) {
        try {
            $null = New-Item -Path $KeyPath -Force
            Set-ItemProperty -LiteralPath $KeyPath -Name $ValueName -Value 1 -Type DWord
        } catch {
            Stop-Helper "could not turn on Developer Mode: $($_.Exception.Message)"
        }
    } elseif ($Elevated) {
        Stop-Helper 'the copy started as administrator is not running as one'
    } else {
        'Turning on Developer Mode needs administrator rights; approve the Windows prompt.'
        $pwsh = (Get-Process -Id $PID).Path
        try {
            $process = Start-Process -FilePath $pwsh -Verb RunAs -Wait -PassThru -ArgumentList @(
                '-NoLogo', '-NoProfile', '-File', "`"$PSCommandPath`"", '-Elevated')
        } catch {
            Stop-Helper "Windows did not start it as administrator, so nothing changed: $($_.Exception.Message)"
        }
        if ($process.ExitCode -ne 0) {
            Stop-Helper "the copy run as administrator failed with exit status $($process.ExitCode)"
        }
    }
    if (-not (Test-DeveloperMode)) {
        Stop-Helper 'Developer Mode is still off'
    }
    'Developer Mode is on.'
}

Invoke-Main -Unexpected $args
