# Install a Go toolchain for the current user from go.dev.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-golang.ps1 [-Latest | VERSION] [-DryRun]
#
# By default, installs the newest patch of the release one behind the latest:
# the older of the two releases Go supports (go1.26.10 while go1.27 is current).
# -Latest (or --latest, as on macOS) installs the newest release, and VERSION
# (1.26.10 or go1.26.10) picks any release. Only stable releases count, ordered
# by version number, not by their place in the list. The zip's SHA-256 comes
# from go.dev's release list and must match before anything is unpacked. The
# toolchain goes in $HOME\.local\share\go (or GO_INSTALL_DIR), replacing an older
# one only after the new one runs. Running it again moves to a newer patch once
# there is one (go1.26.11 after go1.26.10); a toolchain already at that version,
# by its VERSION file, is left alone, as is a newer one unless VERSION names
# the older release, and a directory there that is not a Go toolchain is never
# replaced. -DryRun reports what would be installed, on any
# system, and downloads only the release list; GO_RELEASE_LIST names a file to
# read that list from instead, as the checks do. golang.ps1 puts this toolchain
# first on PATH in PowerShell and turns Go's telemetry off; nothing here changes
# your saved PATH. The home is HOME when it is set, as homeskillet sets it, and
# PowerShell's $HOME otherwise.
# Exit status: 0 on success, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7 on Windows.
# https://go.dev/doc/install
# Invoke-Main and the functions it calls read these from the script scope, which
# the analyzer does not follow.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
param([string]$Version, [switch]$Latest, [switch]$DryRun, [switch]$Help)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest's progress display slows large downloads.
$ProgressPreference = 'SilentlyContinue'

$DownloadUrl = 'https://go.dev/dl'
$VersionPattern = '^(go)?[0-9]+\.[0-9]+(\.[0-9]+)?$'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("install-golang.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: install-golang.ps1 [-Latest | VERSION] [-DryRun]'
    'Installs Go from go.dev into ~\.local\share\go (or GO_INSTALL_DIR): the newest'
    'patch of the release one behind the latest, the latest with -Latest (or'
    '--latest), or VERSION (such as 1.26.10). Rerun it to move to a newer patch.'
    '-DryRun reports what would be installed.'
}

# Stop-Usage MESSAGE prints MESSAGE and the usage to stderr, and exits with
# status 2.
function Stop-Usage {
    param([string]$Message)
    [Console]::Error.WriteLine("install-golang.ps1: $Message")
    Write-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
}

# Get-GoArch prints Go's name for this machine's CPU, or nothing for a CPU Go
# has no Windows build for.
function Get-GoArch {
    switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64' { 'amd64' }
        'Arm64' { 'arm64' }
        'X86' { '386' }
    }
}

# Test-Toolchain DIR reports whether DIR holds a Go toolchain.
function Test-Toolchain {
    param([string]$Dir)
    (Test-Path -LiteralPath (Join-Path $Dir 'VERSION') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $Dir 'bin/go.exe') -PathType Leaf)
}

# Get-ToolchainVersion DIR prints the version a toolchain's VERSION file names
# on its first line, such as go1.26.10.
function Get-ToolchainVersion {
    param([string]$Dir)
    "$(Get-Content -LiteralPath (Join-Path $Dir 'VERSION') -TotalCount 1)".Trim()
}

# Get-ReleaseKey VERSION prints the release VERSION belongs to, such as go1.26
# for go1.26.10.
function Get-ReleaseKey {
    param([string]$Version)
    $Version -replace '^(go[0-9]+\.[0-9]+).*$', '$1'
}

# Get-GoVersion DIR prints the version the go command in DIR reports, such as
# go1.26.10, or nothing when it does not run. GOTOOLCHAIN=local keeps it from
# switching to, and downloading, a toolchain that a go.mod in the current
# directory or the saved go env asks for, which would report that one instead.
function Get-GoVersion {
    param([string]$Dir)
    $savedToolchain = $env:GOTOOLCHAIN
    $env:GOTOOLCHAIN = 'local'
    try {
        $reported = & (Join-Path $Dir 'bin/go.exe') env GOVERSION 2>$null
        if ($LASTEXITCODE -eq 0) { "$reported".Trim() }
    } catch {
        return
    } finally {
        $env:GOTOOLCHAIN = $savedToolchain
    }
}

# ConvertTo-GoVersionNumber VERSION prints VERSION, such as go1.26.10, as a
# [version], or nothing when it is not a stable release's name.
function ConvertTo-GoVersionNumber {
    param([string]$Version)
    if ($Version -match '^go([0-9]+\.[0-9]+(\.[0-9]+)?)$') { [version]$Matches[1] }
}

# Get-OtherGo DIR prints the first go.exe on the saved machine and user PATH
# that is not in DIR, which programs started outside PowerShell would run first.
function Get-OtherGo {
    param([string]$Dir)
    $ours = [System.IO.Path]::GetFullPath($Dir).TrimEnd('\')
    $saved = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -split ';'
    foreach ($entry in $saved) {
        if (-not $entry) { continue }
        $candidate = Join-Path $entry 'go.exe'
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        if ([System.IO.Path]::GetFullPath($entry).TrimEnd('\') -ne $ours) { return $candidate }
        return
    }
}

# Invoke-Main checks the arguments, picks the version from go.dev's release
# list, downloads and checks the zip, unpacks it beside the install directory,
# and swaps it in once it runs.
function Invoke-Main {
    param([object[]]$Unexpected)
    if ($Help) {
        Write-Usage
        exit 0
    }
    if ($Unexpected.Count) {
        Stop-Usage "unexpected argument: $($Unexpected -join ' ')"
    }
    if ($Version -and $Version -notmatch $VersionPattern) {
        Stop-Usage "$Version is not a version such as 1.26.10"
    }
    if ($Version -and $Latest) {
        Stop-Usage 'give -Latest or a version, not both'
    }
    $arch = Get-GoArch
    if (-not $arch) {
        Stop-Helper "Go has no Windows build for this CPU ($([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture))"
    }
    $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
    $installDir = if ($env:GO_INSTALL_DIR) { $env:GO_INSTALL_DIR } else { Join-Path $homeDir '.local/share/go' }
    $installDir = [System.IO.Path]::GetFullPath($installDir)
    if ((Test-Path -LiteralPath $installDir) -and -not (Test-Toolchain $installDir)) {
        Stop-Helper "$installDir is not a Go toolchain; move it or set GO_INSTALL_DIR"
    }

    # Invoke-RestMethod and ConvertFrom-Json emit a JSON array as one object, so
    # it is assigned before @() makes it an array: @() around the call would nest
    # it in another.
    if ($env:GO_RELEASE_LIST) {
        try {
            $releases = Get-Content -LiteralPath $env:GO_RELEASE_LIST -Raw | ConvertFrom-Json
        } catch {
            Stop-Helper "could not read Go's release list from ${env:GO_RELEASE_LIST}: $($_.Exception.Message)"
        }
    } else {
        $listUrl = if ($Version) { "$DownloadUrl/?mode=json&include=all" } else { "$DownloadUrl/?mode=json" }
        try {
            $releases = Invoke-RestMethod -Uri $listUrl
        } catch {
            Stop-Helper "could not download Go's release list: $($_.Exception.Message)"
        }
    }
    $releases = @($releases)
    if ($Version) {
        $target = 'go' + ($Version -replace '^go', '')
    } else {
        # Stable releases by version number, newest first; the target is the
        # newest patch of the latest release, or of the release before it.
        $stable = @($releases | Where-Object stable | ForEach-Object version |
            Where-Object { $_ -match '^go[0-9]+\.[0-9]+(\.[0-9]+)?$' } |
            Sort-Object { ConvertTo-GoVersionNumber $_ } -Descending)
        $keys = @($stable | ForEach-Object { Get-ReleaseKey $_ } | Select-Object -Unique)
        if ($keys.Count -lt 2) { Stop-Helper "Go's release list does not name two stable releases" }
        $key = if ($Latest) { $keys[0] } else { $keys[1] }
        $target = $stable | Where-Object { (Get-ReleaseKey $_) -eq $key } | Select-Object -First 1
    }
    $release = $releases | Where-Object version -EQ $target | Select-Object -First 1
    if (-not $release) { Stop-Helper "Go's release list has no $target" }
    $archive = $release.files |
        Where-Object { $_.os -eq 'windows' -and $_.arch -eq $arch -and $_.kind -eq 'archive' } |
        Select-Object -First 1
    if (-not $archive -or $archive.sha256 -notmatch '^[0-9a-f]{64}$') {
        Stop-Helper "Go's release list has no Windows $arch zip for $target"
    }

    if (Test-Toolchain $installDir) {
        $installed = Get-ToolchainVersion $installDir
        if ($installed -eq $target) {
            "$target is already installed in $installDir."
            exit 0
        }
        # Only a version given by name moves to an older one, so a rerun, such as
        # the setup step's, never undoes an install with -Latest or VERSION.
        $installedNumber = ConvertTo-GoVersionNumber $installed
        if (-not $Version -and $installedNumber -and $installedNumber -gt (ConvertTo-GoVersionNumber $target)) {
            "$installed in $installDir is newer than $target; leaving it unchanged (give VERSION to install $target)."
            exit 0
        }
    }
    if ($DryRun) {
        "Would install $target from $DownloadUrl/$($archive.filename) into $installDir."
        exit 0
    }
    if (-not $IsWindows) {
        Stop-Helper 'this helper installs Go on Windows'
    }

    # Beside the install directory, so the final swap is a rename on one volume.
    $parent = Split-Path -Parent $installDir
    $null = New-Item -ItemType Directory -Path $parent -Force
    $work = Join-Path $parent ('.go-install.' + [System.IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType Directory -Path $work
    try {
        $zip = Join-Path $work $archive.filename
        try {
            Invoke-WebRequest -Uri "$DownloadUrl/$($archive.filename)" -OutFile $zip
        } catch {
            Stop-Helper "could not download $DownloadUrl/$($archive.filename): $($_.Exception.Message)"
        }
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $archive.sha256) {
            Stop-Helper "$($archive.filename) does not match its checksum; nothing was installed"
        }
        # ZipFile, not Expand-Archive, which is far slower on Go's thousands of files.
        Add-Type -AssemblyName System.IO.Compression.ZipFile
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $work)
        $unpacked = Join-Path $work 'go'
        if ((Get-GoVersion $unpacked) -ne $target) {
            Stop-Helper "the unpacked go does not run as $target; nothing was installed"
        }
        $old = Join-Path $work 'old'
        if (Test-Path -LiteralPath $installDir) {
            try {
                Move-Item -LiteralPath $installDir -Destination $old
            } catch {
                Stop-Helper "could not move the old toolchain aside, so nothing changed: $($_.Exception.Message)"
            }
        }
        try {
            Move-Item -LiteralPath $unpacked -Destination $installDir
        } catch {
            if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $installDir }
            Stop-Helper "could not move the new toolchain into ${installDir}: $($_.Exception.Message)"
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    "Installed $target in $installDir."
    $other = Get-OtherGo (Join-Path $installDir 'bin')
    if ($other) {
        "PowerShell runs this one first; programs started elsewhere find $other first."
    }
}

Invoke-Main -Unexpected $args
