# Create Scoop's ~\.config\scoop\config.json, with this machine's Scoop settings.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: init-scoop-config.ps1 [-DryRun] [-Force]
#
# Scoop writes to its configuration, recording the time of every `scoop update`,
# and a write would follow a link into the public dotfiles repository, so the
# file is created here instead of linked. It names the repository and branch
# Scoop updates itself from, the Scoop-Core fork's master, and extracts MSI
# packages with lessmsi. Scoop reads it from %XDG_CONFIG_HOME%\scoop when
# XDG_CONFIG_HOME is set, and from ~\.config\scoop otherwise; so does this
# helper. An existing config.json, including a link, is left unchanged unless
# -Force is given; then it is renamed to config.json.bak.DATE-TIME first. The
# home is HOME when it is set, as homeskillet sets it, and PowerShell's $HOME
# otherwise.
# Exit status: 0 when the file exists or was created, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7.
# https://github.com/ScoopInstaller/Scoop/wiki/Scoop-Configuration
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
param([switch]$DryRun, [switch]$Force, [switch]$Help)

$ErrorActionPreference = 'Stop'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("init-scoop-config.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: init-scoop-config.ps1 [-DryRun] [-Force]'
    "Creates Scoop's ~\.config\scoop\config.json, unless one exists. -Force backs"
    'up an existing one and replaces it; -DryRun only reports what would happen.'
}

# Get-Configuration prints the configuration, in the form Scoop writes it back.
function Get-Configuration {
    @'
{
  "scoop_repo": "https://github.com/Ash258/Scoop-Core",
  "scoop_branch": "master",
  "MSIEXTRACT_USE_LESSMSI": true
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

# Write-NewFile FILE TEXT creates FILE holding TEXT and a final newline, as
# UTF-8 without a byte-order mark. It fails, instead of replacing a file that
# appeared meanwhile.
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

# Invoke-Main checks the arguments, backs up an existing config.json when -Force
# asks to replace it, and creates the configuration unless one exists.
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
    $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $homeDir '.config' }
    $scoopDir = Join-Path $configHome 'scoop'
    $configFile = Join-Path $scoopDir 'config.json'

    $backup = $null
    if (Get-Item -LiteralPath $configFile -Force -ErrorAction SilentlyContinue) {
        if (-not $Force) {
            "$configFile exists; leaving it unchanged (-Force backs it up and replaces it)."
            exit 0
        }
        $backup = Get-BackupPath $configFile
    }
    if ($DryRun) {
        if ($backup) { "Would move $configFile to $backup." }
        "Would create $configFile."
        exit 0
    }
    try {
        $null = New-Item -ItemType Directory -Path $scoopDir -Force
    } catch {
        Stop-Helper "could not create ${scoopDir}: $($_.Exception.Message)"
    }
    # A rename, not a copy: a link is kept as a link, and the new file is never
    # written through it into whatever it points to.
    if ($backup) {
        try {
            Move-Item -LiteralPath $configFile -Destination $backup
        } catch {
            Stop-Helper "could not move $configFile to ${backup}: $($_.Exception.Message)"
        }
        "Moved $configFile to $backup."
    }
    try {
        Write-NewFile $configFile (Get-Configuration)
    } catch {
        $old = if ($backup) { "; the old one is $backup" } else { '' }
        Stop-Helper "could not create ${configFile}: $($_.Exception.Message)$old"
    }
    "Created $configFile."
}

Invoke-Main -Unexpected $args
