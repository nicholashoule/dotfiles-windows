# Turn on the Windows Subsystem for Linux (WSL) and install a Linux
# distribution, whose home `homeskillet wsl` links from home/wsl.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: enable-wsl.ps1 [-Distribution NAME | -NoDistribution] [-DryRun]
#
# Runs Microsoft's `wsl --install` in two parts. Turning WSL on changes Windows
# features and needs administrator rights, so `wsl --install --no-distribution`
# runs in a copy of wsl started as administrator, which Windows asks you to
# approve; homeskillet refuses to run as one. The distribution, Ubuntu unless
# -Distribution names another from `wsl --list --online`, then installs as you,
# since each user has their own, without starting it (--no-launch): run `wsl`
# afterward to create its user. -NoDistribution stops after the first part.
# It checks first, as a standard user can: whether `wsl --version` runs, whether
# the Virtual Machine Platform feature that WSL 2 needs is on, and whether
# Windows is waiting for a restart. What is on already is left alone, and while
# WSL is turned on but waiting for that restart, it says so instead of asking
# for administrator rights again; running it after the restart finishes the
# install. -DryRun reports what would change.
# Exit status: 0 when WSL is on and the distribution installed, or a restart is
# needed first, which it says, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7 on Windows.
# https://learn.microsoft.com/windows/wsl/install
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
param([string]$Distribution, [switch]$NoDistribution, [switch]$DryRun, [switch]$Help)

$ErrorActionPreference = 'Stop'

$DefaultDistribution = 'Ubuntu'
$NamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("enable-wsl.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: enable-wsl.ps1 [-Distribution NAME | -NoDistribution] [-DryRun]'
    'Turns on WSL, asking for administrator rights only for that, then installs'
    "a distribution as you: $DefaultDistribution unless -Distribution names another (wsl --list"
    '--online), or none with -NoDistribution. -DryRun reports what would change.'
}

# Stop-Usage MESSAGE prints MESSAGE and the usage to stderr, and exits with
# status 2.
function Stop-Usage {
    param([string]$Message)
    [Console]::Error.WriteLine("enable-wsl.ps1: $Message")
    Write-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
}

# Test-Wsl reports whether the WSL package is installed and runs: `wsl
# --version` fails with the wsl.exe Windows ships before WSL is installed.
function Test-Wsl {
    if (-not (Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    $null = wsl.exe --version 2>&1
    $LASTEXITCODE -eq 0
}

# Test-Feature NAME reports whether the Windows optional feature NAME is on, or
# prints nothing when Windows does not say. Unlike DISM, this needs no
# administrator rights.
function Test-Feature {
    param([string]$Name)
    try {
        $feature = Get-CimInstance Win32_OptionalFeature -Filter "Name='$Name'" -ErrorAction Stop
    } catch {
        return
    }
    # InstallState 1 is Enabled.
    if ($feature) { $feature.InstallState -eq 1 }
}

# Test-RestartPending reports whether Windows waits for a restart to finish
# changing its components, as it does after turning a feature on.
function Test-RestartPending {
    Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
}

# Get-WslState decides what WSL needs from what Test-Wsl, Test-Feature for the
# Virtual Machine Platform (-Platform) and WSL (-Subsystem) features, and
# Test-RestartPending found, where a feature Windows does not report is $null:
#   on       the package runs and the platform is not known to be off
#   restart  part of WSL is on and Windows waits for a restart, which turning
#            it on again would not replace
#   off      anything else, including a restart pending with no part of WSL on
function Get-WslState {
    param([bool]$Package, [object]$Platform, [object]$Subsystem, [bool]$RestartPending)
    if ($Package -and $Platform -ne $false) { return 'on' }
    if ($RestartPending -and ($Package -or $Platform -or $Subsystem)) { return 'restart' }
    'off'
}

# Read-WslState prints Get-WslState for this machine.
function Read-WslState {
    Get-WslState -Package (Test-Wsl) -Platform (Test-Feature VirtualMachinePlatform) `
        -Subsystem (Test-Feature Microsoft-Windows-Subsystem-Linux) -RestartPending (Test-RestartPending)
}

# Write-Restart prints that Windows must restart, and what to run afterward.
function Write-Restart {
    param([string]$Name)
    if ($Name) {
        "WSL is turned on, but Windows must restart first; restart, then run enable-wsl.ps1 again to install $Name."
    } else {
        'WSL is turned on; restart Windows before using it.'
    }
}

# Get-Distribution prints the name of each installed distribution.
function Get-Distribution {
    $names = wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -eq 0) {
        $names | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    }
}

# Invoke-Main checks the arguments, turns WSL on as administrator when it is
# off, and installs the distribution as the current user when it is missing.
function Invoke-Main {
    param([object[]]$Unexpected)
    if ($Help) {
        Write-Usage
        exit 0
    }
    if ($Unexpected.Count) {
        Stop-Usage "unexpected argument: $($Unexpected -join ' ')"
    }
    if ($Distribution -and $NoDistribution) {
        Stop-Usage 'give -Distribution or -NoDistribution, not both'
    }
    if ($Distribution -and $Distribution -notmatch $NamePattern) {
        Stop-Usage "$Distribution is not a distribution name, such as $DefaultDistribution"
    }
    if (-not $IsWindows) {
        Stop-Helper 'WSL is a Windows feature'
    }
    $name = if ($Distribution) { $Distribution } else { $DefaultDistribution }
    # wsl writes UTF-16 to a pipe unless WSL_UTF8 asks for UTF-8.
    $env:WSL_UTF8 = '1'

    $wanted = if ($NoDistribution) { '' } else { $name }
    $state = Read-WslState
    if ($state -eq 'on' -and ($NoDistribution -or @(Get-Distribution) -contains $name)) {
        if ($NoDistribution) { 'WSL is already on.' } else { "WSL is already on, and $name is installed." }
        exit 0
    }
    if ($state -eq 'restart') {
        Write-Restart $wanted
        exit 0
    }
    if ($DryRun) {
        if ($state -eq 'off') { 'Would turn on WSL, after Windows asks you to approve administrator rights.' }
        if (-not $NoDistribution) { "Would install $name." }
        exit 0
    }

    if ($state -eq 'off') {
        'Turning on WSL needs administrator rights; approve the Windows prompt.'
        try {
            $process = Start-Process -FilePath wsl.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
                '--install', '--no-distribution')
        } catch {
            Stop-Helper "Windows did not start wsl as administrator, so nothing changed: $($_.Exception.Message)"
        }
        # 3010 is Windows' code for a change that succeeded and needs a restart.
        if ($process.ExitCode -notin 0, 3010) {
            Stop-Helper "wsl --install --no-distribution failed with exit status $($process.ExitCode)"
        }
        # A restart Windows waits for now is almost surely for WSL, even if the
        # feature already reads as on.
        if ($process.ExitCode -eq 3010 -or (Read-WslState) -ne 'on' -or (Test-RestartPending)) {
            Write-Restart $wanted
            exit 0
        }
    }
    if ($NoDistribution) {
        'WSL is on.'
        exit 0
    }
    wsl.exe --install --distribution $name --no-launch
    if ($LASTEXITCODE -ne 0) {
        $status = $LASTEXITCODE
        $hint = if (Test-RestartPending) { '; Windows is waiting for a restart, so restart, then run enable-wsl.ps1 again' }
        Stop-Helper "wsl --install --distribution $name failed with exit status $status$hint"
    }
    if (@(Get-Distribution) -notcontains $name) {
        Stop-Helper "$name is not listed by wsl --list after installing it"
    }
    "WSL is on, and $name is installed; run wsl to start it and create its user."
}

# Run from PATH in a session, the helper shares that session's environment, so
# the WSL_UTF8 that Invoke-Main sets is put back afterward, even on exit.
# Dot-sourced, as the checks do to test Get-WslState, it only defines functions.
if ($MyInvocation.InvocationName -ne '.') {
    $savedWslUtf8 = $env:WSL_UTF8
    try {
        Invoke-Main -Unexpected $args
    } finally {
        $env:WSL_UTF8 = $savedWslUtf8
    }
}
