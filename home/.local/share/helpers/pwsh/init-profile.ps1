# Create the stub PowerShell runs as the current user's profile, which loads the
# dotfiles' profile from $HOME\.config\powershell\profile.ps1.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: init-profile.ps1 [-Path FILE] [-DryRun] [-Force]
#
# On Windows, PowerShell reads a user's profile only from Documents\PowerShell,
# and OneDrive may redirect Documents into the folder it syncs. So the dotfiles
# keep the profile in $HOME\.config\powershell, and this helper writes only a
# stub that dot-sources it where PowerShell looks: FILE, or by default
# $PROFILE.CurrentUserAllHosts, wherever Documents is. The stub is created, not
# linked, so no link into the repository lands in a folder OneDrive syncs, and
# on a machine without the dotfiles it loads nothing. An existing file,
# including a link, is left unchanged unless -Force is given; then it is renamed
# to FILE.bak.DATE-TIME first. Where PowerShell already reads the dotfiles'
# profile directly, as on Linux and macOS, no stub is needed. The home is HOME
# when it is set, as homeskillet sets it, and PowerShell's $HOME otherwise.
# Exit status: 0 when the stub exists, was created, or is not needed, 1 on
# failure, 2 for usage errors.
# Runs on PowerShell 7.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow. -Path is named only, and every other argument
# lands in $Unexpected, so a stray word is a usage error instead of a FILE.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Path, [switch]$DryRun, [switch]$Force, [switch]$Help,
    [Parameter(ValueFromRemainingArguments)] [object[]]$Unexpected
)

$ErrorActionPreference = 'Stop'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("init-profile.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: init-profile.ps1 [-Path FILE] [-DryRun] [-Force]'
    'Creates the profile PowerShell runs, FILE or $PROFILE.CurrentUserAllHosts, as'
    'a stub that loads ~\.config\powershell\profile.ps1, unless one exists.'
    '-Force backs up an existing one and replaces it; -DryRun only reports what'
    'would happen.'
}

# Get-Stub prints the stub. It names the profile through $HOME, so it follows
# the user it runs as, and loads nothing where the profile does not exist.
function Get-Stub {
    @'
# Loads the PowerShell profile from the dotfiles, $HOME\.config\powershell\profile.ps1.
# PowerShell reads a user's profile only from Documents\PowerShell, which OneDrive
# may redirect and sync, so only this stub lives here. The dotfiles' profile
# setup step (init-profile.ps1) created it and replaces it only with -Force; it
# loads nothing on a machine without the dotfiles.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
if (Test-Path -LiteralPath "$HOME/.config/powershell/profile.ps1" -PathType Leaf) {
    . "$HOME/.config/powershell/profile.ps1"
}
'@
}

# Get-BackupPath FILE prints an unused backup name for FILE:
# FILE.bak.YYYYMMDD-HHMMSS, with .N added when that is taken.
function Get-BackupPath {
    param([string]$File)
    $base = "$File.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $path = $base
    $n = 0
    while (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue) {
        $n++
        $path = "$base.$n"
    }
    $path
}

# Write-NewFile FILE TEXT creates FILE holding TEXT and a final newline, so a
# line appended later starts a line of its own, as UTF-8 without a byte-order
# mark. It fails, instead of replacing a file that appeared meanwhile.
function Write-NewFile {
    param([string]$File, [string]$Text)
    $stream = [System.IO.File]::Open($File, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
}

# Test-Stub FILE reports whether FILE is a regular file holding the stub, in
# either line ending.
function Test-Stub {
    param([string]$File)
    $item = Get-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -or $item.PSIsContainer) { return $false }
    ((Get-Content -LiteralPath $File -Raw) -replace "`r`n", "`n") -ceq ((Get-Stub) + "`n")
}

# Invoke-Main checks the arguments, finds the profile PowerShell runs, backs up
# an existing one when -Force asks to replace it, and creates the stub unless
# one exists.
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
    $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
    if (-not $homeDir -or -not (Test-Path -LiteralPath $homeDir -PathType Container)) {
        Stop-Helper 'the home directory (HOME) is not a directory'
    }
    $stubFile = if ($Path) { $Path } else { $PROFILE.CurrentUserAllHosts }
    if (-not $stubFile) {
        Stop-Helper 'PowerShell reports no profile path; give one with -Path'
    }
    $stubFile = [System.IO.Path]::GetFullPath($stubFile)
    $dotfilesProfile = [System.IO.Path]::GetFullPath((Join-Path $homeDir '.config/powershell/profile.ps1'))
    # A stub in place of the profile itself would dot-source itself forever.
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ([string]::Equals($stubFile, $dotfilesProfile, $comparison)) {
        "PowerShell reads $dotfilesProfile directly here; no stub is needed."
        exit 0
    }
    $stubDir = Split-Path -Parent $stubFile

    $backup = $null
    $existing = Get-Item -LiteralPath $stubFile -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.PSIsContainer -and -not $existing.LinkType) {
            Stop-Helper "$stubFile is a directory"
        }
        if (-not $Force) {
            if (Test-Stub $stubFile) {
                "$stubFile already loads the dotfiles' profile; leaving it unchanged."
            } else {
                "$stubFile exists; leaving it unchanged (-Force backs it up and replaces it)."
            }
            exit 0
        }
        $backup = Get-BackupPath $stubFile
    }
    if ($DryRun) {
        if ($backup) { "Would move $stubFile to $backup." }
        "Would create $stubFile."
        exit 0
    }
    try {
        $null = New-Item -ItemType Directory -Path $stubDir -Force
    } catch {
        Stop-Helper "could not create ${stubDir}: $($_.Exception.Message)"
    }
    # A rename, not a copy: a link is kept as a link, and the new file is never
    # written through it into whatever it points to.
    if ($backup) {
        try {
            Move-Item -LiteralPath $stubFile -Destination $backup
        } catch {
            Stop-Helper "could not move $stubFile to ${backup}: $($_.Exception.Message)"
        }
        "Moved $stubFile to $backup."
    }
    try {
        Write-NewFile $stubFile (Get-Stub)
    } catch {
        $old = if ($backup) { "; the old one is $backup" } else { '' }
        Stop-Helper "could not create ${stubFile}: $($_.Exception.Message)$old"
    }
    "Created $stubFile, which loads $dotfilesProfile."
}

Invoke-Main -Unexpected $Unexpected
