# Create the starter ~\.config\powershell\profile.d\local.ps1, for this machine's
# own settings.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: init-local.ps1 [-DryRun] [-Force]
#
# profile.ps1 dot-sources every *.ps1 file in ~\.config\powershell\profile.d,
# and local.ps1 is the one there for settings that belong to this machine only,
# so it is created here instead of linked from the public dotfiles repository.
# The starter holds only comments: examples of the overrides the dotfiles
# support, to uncomment. An existing local.ps1, including a link, is left
# unchanged unless -Force is given; then it is renamed to
# local.ps1.bak.DATE-TIME first. profile.d must be a real directory, because a
# linked one could lead into the repository. The home is HOME when it is set, as
# homeskillet sets it, and PowerShell's $HOME otherwise.
# Exit status: 0 when the file exists or was created, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
param([switch]$DryRun, [switch]$Force, [switch]$Help)

$ErrorActionPreference = 'Stop'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("init-local.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: init-local.ps1 [-DryRun] [-Force]'
    'Creates ~\.config\powershell\profile.d\local.ps1, with commented examples of'
    'settings for this machine only, unless one exists. -Force backs up an'
    'existing one and replaces it; -DryRun only reports what would happen.'
}

# Get-Starter prints the starter file: comments only, so it changes nothing
# until you uncomment a line.
function Get-Starter {
    @'
# Settings for this machine only. The dotfiles' local setup step (init-local.ps1)
# created this file and never links or replaces it, so nothing here reaches the
# public repository. Uncomment what you need.
#
# profile.ps1 dot-sources it with the other files in
# ~\.config\powershell\profile.d, in alphabetical order. A file that sorts after
# it, such as oh-my-posh.ps1, reads its settings while loading; one that sorts
# before it, such as 00-psreadline.ps1, has already run, so a setting here
# replaces that file's. Credentials belong in each tool's own files, not here.

# Prompt theme: the name of a theme in ~\.config\oh-my-posh\themes, without
# .omp.json, or a path to any theme file.
# $env:OHMYPOSH_THEME = 'bubbles'

# PSReadLine, in interactive sessions: replace a setting from 00-psreadline.ps1.
# if (Get-Module PSReadLine) { Set-PSReadLineOption -PredictionViewStyle InlineView }

# A directory first on PATH.
# $env:PATH = "$HOME\opt\tool\bin;$env:PATH"

# Commands for this machine.
# function proj { Set-Location "$HOME\projects" }
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

# Invoke-Main checks the arguments, backs up an existing local.ps1 when -Force
# asks to replace it, and creates the starter unless one exists.
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
    $localDir = Join-Path $homeDir '.config/powershell/profile.d'
    $localFile = Join-Path $localDir 'local.ps1'
    $dirItem = Get-Item -LiteralPath $localDir -Force -ErrorAction SilentlyContinue
    if ($dirItem -and $dirItem.LinkType) {
        Stop-Helper "$localDir is a link; local.ps1 belongs in a real directory, outside the repository"
    }
    if ($dirItem -and -not $dirItem.PSIsContainer) {
        Stop-Helper "$localDir is not a directory"
    }

    $backup = $null
    if (Get-Item -LiteralPath $localFile -Force -ErrorAction SilentlyContinue) {
        if (-not $Force) {
            "$localFile exists; leaving it unchanged (-Force backs it up and replaces it)."
            exit 0
        }
        $backup = Get-BackupPath $localFile
    }
    if ($DryRun) {
        if ($backup) { "Would move $localFile to $backup." }
        "Would create $localFile."
        exit 0
    }
    try {
        $null = New-Item -ItemType Directory -Path $localDir -Force
    } catch {
        Stop-Helper "could not create ${localDir}: $($_.Exception.Message)"
    }
    # A rename, not a copy: a link is kept as a link, and the new file is never
    # written through it into whatever it points to.
    if ($backup) {
        try {
            Move-Item -LiteralPath $localFile -Destination $backup
        } catch {
            Stop-Helper "could not move $localFile to ${backup}: $($_.Exception.Message)"
        }
        "Moved $localFile to $backup."
    }
    try {
        Write-NewFile $localFile (Get-Starter)
    } catch {
        $old = if ($backup) { "; the old one is $backup" } else { '' }
        Stop-Helper "could not create ${localFile}: $($_.Exception.Message)$old"
    }
    "Created $localFile with commented examples; uncomment what this machine needs."
}

Invoke-Main -Unexpected $args
