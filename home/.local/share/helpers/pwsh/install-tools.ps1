# Install or upgrade every winget package that tools.psd1 lists.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-tools.ps1 [-Path FILE] [-NoUpgrade] [-DryRun]
#
# Runs `winget install --id ID --exact --source winget` for each package in the
# list, ~\.config\winget\tools.psd1 unless -Path names another, which installs
# what is missing and upgrades what is outdated; -NoUpgrade leaves installed
# packages as they are. A package that is installed and up to date counts as
# done. Every package is tried, and the helper fails if any did. winget adds
# programs to PATH for new processes only, so open a new terminal to use them.
# -DryRun prints each command without running it, and needs no winget.
# Exit status: 0 when every package is installed, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7.
# https://learn.microsoft.com/windows/package-manager/winget/install
param([string]$Path, [switch]$NoUpgrade, [switch]$DryRun, [switch]$Help)

$ErrorActionPreference = 'Stop'

# winget's exit codes for a package that is already installed: no applicable
# upgrade (0x8A15002B), and already installed when --no-upgrade is given
# (0x8A150061).
$AlreadyInstalled = @(-1978335189, -1978335135)

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("install-tools.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: install-tools.ps1 [-Path FILE] [-NoUpgrade] [-DryRun]'
    'Installs and upgrades every winget package ~\.config\winget\tools.psd1 (or'
    'FILE) lists. -NoUpgrade leaves installed packages alone; -DryRun prints the'
    'commands without running them.'
}

# Invoke-Main reads the list and installs each package, or prints the commands.
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
    if (-not $Path) {
        $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
        $Path = Join-Path $homeDir '.config/winget/tools.psd1'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Helper "$Path is missing; link this repository with homeskillet first, or pass -Path"
    }
    try {
        $packages = @((Import-PowerShellDataFile -LiteralPath $Path).WingetPackages)
    } catch {
        Stop-Helper "could not read ${Path}: $($_.Exception.Message)"
    }
    foreach ($package in $packages) {
        if (-not $package.Id) { Stop-Helper "$Path lists a package without an Id" }
    }
    if (-not $DryRun -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Helper 'winget is not available: install App Installer from the Microsoft Store'
    }

    $failed = @()
    foreach ($package in $packages) {
        $wingetArgs = @('install', '--id', $package.Id, '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements')
        if ($NoUpgrade) { $wingetArgs += '--no-upgrade' }
        if ($DryRun) {
            "winget $($wingetArgs -join ' ')"
            continue
        }
        "--- $($package.Name) ($($package.Id))"
        winget @wingetArgs
        if ($LASTEXITCODE -ne 0 -and $AlreadyInstalled -notcontains $LASTEXITCODE) {
            $failed += "$($package.Id) (exit $LASTEXITCODE)"
        }
    }
    if ($failed) {
        Stop-Helper "failed: $($failed -join ', ')"
    }
}

Invoke-Main -Unexpected $args
