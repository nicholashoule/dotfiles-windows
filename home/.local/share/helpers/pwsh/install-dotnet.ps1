# Install a .NET SDK for the current user with Microsoft's dotnet-install script.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-dotnet.ps1 [RELEASE | VERSION] [DOTNET-INSTALL OPTION...]
#
# Installs into $HOME\.dotnet (or DOTNET_INSTALL_DIR, or -InstallDir DIR). The
# optional first argument picks what to install, as a shorthand for
# dotnet-install's -Channel or -Version: LTS or STS, a release such as 10.0 (or
# just 10), a feature band such as 10.0.1xx, or an exact SDK version such as
# 10.0.100. Without it, that is the latest LTS SDK. Other options pass through,
# for example `-Runtime aspnetcore` or `-DryRun`. The script is downloaded to a
# file and runs only when it carries Microsoft's valid Authenticode signature; a
# copy stays in the install directory for later installs. The zip it downloads
# must match a SHA-512 in Microsoft's release list for that version, or what
# the run added is removed and the helper fails; dotnet-install itself compares
# only sizes, and since the download server does not report one, it always
# says the package may be corrupted. The helper prints what it installed in a
# line; dotnet-install's own output shows only when it failed, or with
# -Verbose or -DryRun. dotnet.ps1 puts
# $HOME\.dotnet first on PATH in PowerShell; dotnet-install changes PATH only for
# its own process, and nothing here changes your saved PATH. Unlike the macOS
# helper, this one does not add dotnet-core-uninstall. The home is HOME when it
# is set, as homeskillet sets it, and PowerShell's $HOME otherwise.
# Exit status: 0 on success, 1 on failure, 2 for usage errors.
# Runs on PowerShell 7 on Windows.
# https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script
# Invoke-Main reads -Help from the script scope, which the analyzer does not
# follow. Every other argument stays in $args, so options for dotnet-install
# pass through unchanged.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Invoke-Main reads the parameters')]
param([switch]$Help)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest's progress display slows downloads.
$ProgressPreference = 'SilentlyContinue'

$InstallUrl = 'https://dot.net/v1/dotnet-install.ps1'
# Microsoft's release list for a release such as 10.0 is at $MetadataUrl/10.0/releases.json.
$MetadataUrl = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata'
# The forms of the first argument: a major version becomes a release (10 is
# 10.0); LTS, STS, a release, or a feature band is a channel; the rest is an
# exact version, with a preview suffix allowed (10.0.100-rc.2.25502.107).
$MajorPattern = '^[0-9]+$'
$ChannelPattern = '^(LTS|STS|[0-9]+\.[0-9]+(\.[0-9]xx)?)$'
$VersionPattern = '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

# Stop-Helper MESSAGE prints an error message and exits with status 1.
function Stop-Helper {
    param([string]$Message)
    [Console]::Error.WriteLine("install-dotnet.ps1: $Message")
    exit 1
}

# Write-Usage prints the usage line and what the helper does.
function Write-Usage {
    'Usage: install-dotnet.ps1 [RELEASE | VERSION] [DOTNET-INSTALL OPTION...]'
    'Installs a .NET SDK into ~\.dotnet (or DOTNET_INSTALL_DIR): the latest LTS'
    'release unless RELEASE or VERSION says otherwise.'
    '  RELEASE  LTS, STS, a release such as 10.0 (or 10), or a feature band such as 10.0.1xx'
    '  VERSION  an exact SDK version, such as 10.0.100'
    'Other options pass through to dotnet-install.ps1, for example -DryRun:'
    '  https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script'
}

# Stop-Usage MESSAGE prints MESSAGE and the usage to stderr, and exits with
# status 2.
function Stop-Usage {
    param([string]$Message)
    [Console]::Error.WriteLine("install-dotnet.ps1: $Message")
    Write-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
}

# Get-InstalledVersion DIR prints each SDK and runtime in the .NET directory
# DIR, as sdk/VERSION or NAME/VERSION, such as Microsoft.NETCore.App/10.0.0.
function Get-InstalledVersion {
    param([string]$Directory)
    Get-ChildItem -LiteralPath (Join-Path $Directory 'sdk') -Directory -ErrorAction Ignore |
        ForEach-Object { "sdk/$($_.Name)" }
    foreach ($shared in Get-ChildItem -LiteralPath (Join-Path $Directory 'shared') -Directory -ErrorAction Ignore) {
        Get-ChildItem -LiteralPath $shared.FullName -Directory | ForEach-Object { "$($shared.Name)/$($_.Name)" }
    }
}

# Get-PublishedHash METADATA VERSION... prints the SHA-512 of every file
# Microsoft's release list METADATA publishes for an SDK or runtime of a
# VERSION, and nothing when it lists none of them.
function Get-PublishedHash {
    param([object]$Metadata, [string[]]$Version)
    foreach ($release in $Metadata.releases) {
        $products = @($release.sdks) + @($release.sdk, $release.runtime, $release.'aspnetcore-runtime', $release.windowsdesktop)
        foreach ($product in $products) {
            if ($product -and $Version -contains $product.version) { @($product.files).hash }
        }
    }
}

# Invoke-Main turns the optional release or version into dotnet-install's
# option, checks the other options, downloads the installer to a file, checks
# its signature, runs it in a new pwsh, and checks the zip it downloaded.
function Invoke-Main {
    param([object[]]$Arguments)
    if ($Help) {
        Write-Usage
        exit 0
    }
    $rest = @($Arguments | ForEach-Object { "$_" })
    $release = $null
    $selector = @()
    if ($rest.Count -and $rest[0] -notlike '-*') {
        $release = $rest[0]
        $rest = @($rest | Select-Object -Skip 1)
        if ($release -match $MajorPattern) {
            $selector = '-Channel', "$release.0"
        } elseif ($release -match $ChannelPattern) {
            $selector = '-Channel', $release
        } elseif ($release -match $VersionPattern) {
            $selector = '-Version', $release
        } else {
            Stop-Usage "$release is not a release or version"
        }
    }
    $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
    $installDir = if ($env:DOTNET_INSTALL_DIR) { $env:DOTNET_INSTALL_DIR } else { Join-Path $homeDir '.dotnet' }
    # A directory or zip path given to dotnet-install is used here too, and not
    # added a second time. PowerShell options ignore case, as -match does.
    $customDir = $false
    $zipPath = $null
    $keepZip = $false
    $dryRun = $false
    $verbose = $false
    $product = '.NET SDK'
    $what = if ($release) { $release } else { 'LTS' }
    for ($i = 0; $i -lt $rest.Count; $i++) {
        $value = if ($i + 1 -lt $rest.Count) { $rest[$i + 1] }
        if ($rest[$i] -match '^-DryRun$') {
            $dryRun = $true
        } elseif ($rest[$i] -match '^-Verbose$') {
            $verbose = $true
        } elseif ($rest[$i] -match '^-KeepZip$') {
            $keepZip = $true
        } elseif ($rest[$i] -match '^-InstallDir$') {
            if ($null -eq $value) { Stop-Usage '-InstallDir needs a directory' }
            $installDir = $value
            $customDir = $true
        } elseif ($rest[$i] -match '^-ZipPath$') {
            if ($null -eq $value) { Stop-Usage '-ZipPath needs a file' }
            $zipPath = $value
        } elseif ($rest[$i] -match '^-Runtime$' -and $null -ne $value) {
            $product = ".NET $value runtime"
        } elseif ($rest[$i] -match '^-(Channel|Version)$') {
            if ($release) { Stop-Usage "give $release or $($rest[$i]), not both" }
            if ($null -ne $value) { $what = $value }
        }
    }
    if (-not $IsWindows) {
        Stop-Helper 'this helper installs .NET on Windows'
    }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('dotnet-install.' + [System.IO.Path]::GetRandomFileName())
    $null = New-Item -ItemType Directory -Path $work
    # dotnet-install keeps the zip it downloads, so its SHA-512 can be checked,
    # and the helper removes it afterward unless -KeepZip asked for it. A zip
    # kept without -ZipPath goes to the temporary folder, and the result says where.
    $installerArgs = @($selector)
    if (-not $customDir) { $installerArgs += '-InstallDir', $installDir }
    if (-not $zipPath) {
        $zipFolder = if ($keepZip) { [System.IO.Path]::GetTempPath() } else { $work }
        $zipPath = Join-Path $zipFolder ('dotnet.' + [System.IO.Path]::GetRandomFileName() + '.zip')
        $installerArgs += '-ZipPath', $zipPath
    }
    if (-not $keepZip) { $installerArgs += '-KeepZip' }
    $installerArgs += $rest
    try {
        # A file, not a pipe into Invoke-Expression: a failed or cut-off download
        # stops here, and the signature covers every byte that runs.
        $installer = Join-Path $work 'dotnet-install.ps1'
        try {
            Invoke-WebRequest -Uri $InstallUrl -OutFile $installer
        } catch {
            Stop-Helper "could not download ${InstallUrl}: $($_.Exception.Message)"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or
            $signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
            Stop-Helper "the download from $InstallUrl is not signed by Microsoft ($($signature.Status)); nothing was installed"
        }
        # A new pwsh, so dotnet-install's options are parsed as its own. Its
        # output is kept for a failure unless -Verbose or -DryRun asks for it;
        # the line naming what is installed goes out first, so a long download
        # shows what it is for, and the result completes it.
        $pwsh = (Get-Process -Id $PID).Path
        $before = @(Get-InstalledVersion $installDir)
        $lines = @()
        if ($dryRun -or $verbose) {
            & $pwsh -NoLogo -NoProfile -File $installer @installerArgs
        } else {
            [Console]::Out.Write("Installing the $product ($what) into $installDir ... ")
            $lines = @(& $pwsh -NoLogo -NoProfile -File $installer @installerArgs 2>&1 | ForEach-Object { "$_" })
        }
        $status = $LASTEXITCODE
        if ($status -ne 0) {
            if (-not ($dryRun -or $verbose)) {
                [Console]::Out.WriteLine('failed')
                $lines | ForEach-Object { [Console]::Out.WriteLine("    $_") }
            }
            Stop-Helper "dotnet-install.ps1 failed with exit status $status"
        }
        # A dry run only prints what dotnet-install would download.
        if ($dryRun) { return }

        $added = @(Get-InstalledVersion $installDir | Where-Object { $before -notcontains $_ })
        $versions = @($added | ForEach-Object { Split-Path $_ -Leaf } | Select-Object -Unique)
        $sdks = @($added | Where-Object { $_ -like 'sdk/*' } | ForEach-Object { Split-Path $_ -Leaf })
        $result = if ($sdks) {
            "installed $($sdks -join ', ')"
        } elseif ($added) {
            "installed $(($added | ForEach-Object { $_ -replace '/', ' ' }) -join ', ')"
        } elseif (($lines -join "`n") -match "version '([^']+)' is already installed") {
            "$($Matches[1]) is already installed"
        } else {
            'nothing new to install'
        }
        # dotnet-install downloads nothing for what is installed already.
        if ($versions -and (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
            $channel = if ($versions[0] -match '^([0-9]+\.[0-9]+)\.') { $Matches[1] }
            try {
                $metadata = Invoke-RestMethod -Uri "$MetadataUrl/$channel/releases.json"
            } catch {
                if (-not $verbose) { [Console]::Out.WriteLine('failed') }
                Stop-Helper "$result, but could not read Microsoft's release list to check the download: $($_.Exception.Message)"
            }
            $published = @(Get-PublishedHash -Metadata $metadata -Version $versions)
            $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA512).Hash
            if (-not $published) {
                $result += "; Microsoft's release list does not list it, so the download was not checked"
            } elseif ($published -notcontains $hash) {
                if (-not $verbose) { [Console]::Out.WriteLine('failed') }
                foreach ($entry in $added) {
                    $path = if ($entry -like 'sdk/*') { Join-Path $installDir $entry } else { Join-Path $installDir "shared/$entry" }
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
                Stop-Helper ("the download of $($versions -join ', ') does not match the SHA-512 in Microsoft's " +
                    "release list, so what it added to $installDir was removed; run install-dotnet.ps1 again")
            } else {
                $result += "; the download matches the SHA-512 in Microsoft's release list"
            }
        }
        Copy-Item -LiteralPath $installer -Destination (Join-Path $installDir 'dotnet-install.ps1') -Force
        if ($keepZip -and (Test-Path -LiteralPath $zipPath -PathType Leaf)) { $result += "; the zip is $zipPath" }
        # With -Verbose, the result follows dotnet-install's output on its own line.
        if ($verbose) { $result = "install-dotnet.ps1: $result" }
        [Console]::Out.WriteLine($result)
        # dotnet-install's warnings matter even when the install succeeded.
        $lines | Where-Object { $_ -like 'WARNING:*' } | ForEach-Object { [Console]::Out.WriteLine("    $_") }
    } finally {
        if (-not $keepZip) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction Ignore }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Ignore
    }
}

# Dot-sourced, as the checks do to test its functions, it only defines them.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Arguments $args
}
