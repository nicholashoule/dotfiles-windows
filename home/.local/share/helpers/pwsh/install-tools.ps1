# Install or upgrade every winget package that tools.psd1 lists.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-tools.ps1 [-Path FILE] [-NoUpgrade] [-DryRun]
#
# Reads the list, ~\.config\winget\tools.psd1 unless -Path names another, and
# asks winget once which packages are installed (`winget export`). It runs
# `winget install --id ID --exact --source winget` for each package that is
# missing and, unless -NoUpgrade is given, for each that is installed, which
# upgrades it when a newer version exists; -NoUpgrade leaves installed packages
# alone without running winget for them. Each package gets one line saying what
# happened, and winget's own output is shown only for a package that failed. A
# package that is up to date, or that winget cannot upgrade, counts as done.
# Every package is tried, and the helper fails if any did. winget adds programs
# to PATH for new processes only, so open a new terminal to use them. -DryRun
# prints each command without running it, and needs no winget.
# Exit status: 0 when every package is installed, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7.
# https://learn.microsoft.com/windows/package-manager/winget/install
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow. -Path is named only, and every other argument
# lands in $Unexpected, so a stray word is a usage error instead of a FILE.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Path, [switch]$NoUpgrade, [switch]$DryRun, [switch]$Help,
    [Parameter(ValueFromRemainingArguments)] [object[]]$Unexpected
)

$ErrorActionPreference = 'Stop'

# winget's exit codes that leave a package installed, and what each means;
# `winget error CODE` describes any code. Every other nonzero code is a failure.
$Done = @{
    0x8A15002B = 'up to date'
    0x8A150061 = 'already installed'
    0x8A15010D = 'already installed'
    0x8A150109 = 'installed; restart Windows to finish'
    # MSYS2's installer, for one, cannot upgrade it; it updates itself with pacman.
    0x8A150114 = 'installed; winget cannot upgrade it'
}

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

# Get-InstalledId prints the ID of each package winget finds installed, from one
# `winget export`. When that fails it prints nothing, and every package goes
# through winget install, which checks for itself.
function Get-InstalledId {
    $file = Join-Path ([System.IO.Path]::GetTempPath()) "install-tools.$PID.json"
    try {
        $null = winget export --output $file --source winget --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file -PathType Leaf)) {
            (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).Sources.Packages.PackageIdentifier
        }
    } catch {
        # An unreadable export is the same as none.
        $null = $_
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

# Get-PackageName PACKAGE prints the package's Name, or its Id without one.
function Get-PackageName {
    param([hashtable]$Package)
    if ($Package.Name) { $Package.Name } else { $Package.Id }
}

# Invoke-Winget ARGUMENTS runs winget with its output captured and prints the
# lines that carry text, without progress bars. winget writes UTF-8, which
# PowerShell decodes with the console's output encoding, so that is UTF-8 while
# winget runs. $LASTEXITCODE is winget's afterward.
function Invoke-Winget {
    param([string[]]$Arguments)
    $encoding = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $null = $_ }
        $lines = winget @Arguments 2>&1
    } finally {
        try { [Console]::OutputEncoding = $encoding } catch { $null = $_ }
    }
    # Progress bars draw with full and shaded blocks (U+2588, U+2592).
    $bars = '[{0}{1}]' -f [char]0x2588, [char]0x2592
    $lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '\p{L}' -and $_ -notmatch $bars }
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

    # Lines go straight to the console, as the partial line below must, so they
    # stay in order.
    $installed = if ($DryRun) { @() } else { @(Get-InstalledId) }
    $kept = @($packages | Where-Object { $NoUpgrade -and $installed -contains $_.Id })
    if ($kept) {
        [Console]::Out.WriteLine("Already installed: $(($kept | ForEach-Object { Get-PackageName $_ }) -join ', ')")
    }
    $failed = @()
    $added = $false
    foreach ($package in $packages | Where-Object { $kept -notcontains $_ }) {
        # --disable-interactivity, since a question in captured output would wait unseen.
        $wingetArgs = @('install', '--id', $package.Id, '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
        if ($NoUpgrade) { $wingetArgs += '--no-upgrade' }
        if ($DryRun) {
            "winget $($wingetArgs -join ' ')"
            continue
        }
        $wasInstalled = $installed -contains $package.Id
        # The name goes out first, so a long download or an administrator prompt
        # shows which package it is for; the result completes the line.
        [Console]::Out.Write("$(Get-PackageName $package) ... ")
        $lines = @(Invoke-Winget $wingetArgs)
        $status = $LASTEXITCODE
        if ($status -eq 0) {
            $added = $added -or -not $wasInstalled
            [Console]::Out.WriteLine($(if ($wasInstalled) { 'upgraded' } else { 'installed' }))
        } elseif ($Done.ContainsKey($status)) {
            [Console]::Out.WriteLine($Done[$status])
        } else {
            # winget's own codes are negative as integers; it documents them in hex.
            $code = if ($status -lt 0) { '0x{0:X8}' -f $status } else { $status }
            $failed += "$($package.Id) (exit $code)"
            [Console]::Out.WriteLine("failed, exit $code")
            $lines | ForEach-Object { [Console]::Out.WriteLine("    $_") }
        }
    }
    if ($added) {
        [Console]::Out.WriteLine('Open a new terminal to use what winget installed.')
    }
    if ($failed) {
        Stop-Helper "failed: $($failed -join ', '); winget error CODE says what a code means"
    }
}

Invoke-Main -Unexpected $Unexpected
