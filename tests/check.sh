#!/usr/bin/env bash
# Regression checks for the PowerShell files and, optionally, the manager.
#
# Usage: bash tests/check.sh [MANAGER]
#
# They run with Bash on Linux and macOS, as CI does on Ubuntu, and in Git Bash
# on Windows. When pwsh is installed, they parse every PowerShell file, and lint
# it when PSScriptAnalyzer is installed, load the profile and its snippets as a
# machine without its tools would, run the helpers in a temporary home, and
# parse every JSON file. Passing homeskillet as MANAGER, the build for the
# system the checks run on, also links, checks, and unlinks every file under
# home/ in a temporary home, acting for Windows with --platform windows, and
# lists the setup steps without running them.
# Exit status: 0 when all checks pass, 1 when a check fails, 2 for usage errors.

# POSIX syntax until bash is confirmed, so `sh tests/check.sh` fails clearly.
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'check.sh: run with bash: bash tests/check.sh\n' >&2
    exit 2
fi
set -euo pipefail
# CDPATH can redirect cd to another directory and make it print the path.
unset CDPATH

# Global variables
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly REPO
# The profile stub init-profile.ps1 writes, relative to a test home: in
# Documents, as on a machine whose Documents OneDrive does not redirect. The
# checks always give the helper this path with -Path, so they never touch the
# real profile, which on Windows is wherever Documents is.
readonly STUB=Documents/PowerShell/profile.ps1
# The commands the README documents for the profile.
readonly -a PROFILE_COMMANDS=(
    ls la ll env hist edit-last gs gitcm Update-WingetPackage
    Update-PowerShell update-pwsh Update-OhMyPosh update-omp
    Set-GitHubToken set-gh-token New-GpgSigningKey new-gpg-key gpg-key-1y gpg-key-5y gpg-key-10y
    Get-GpgPublicKey gpg-pub Copy-GpgPublicKey gpg-pub-copy
    Get-GpgKeyId gpg-keyid Get-GpgKeyIdShort gpg-keyid-short
    Set-GitGpgSigningKey git-sign-key Add-SshKey
)
# PROFILE_CHECK dot-sources CHECK_PROFILE twice, as `. $PROFILE` reloads it in
# an open session, and prints each variable it leaves behind, each error it
# records in $Error, even one it hides, and each command in CHECK_COMMANDS it
# does not define. Paths and names pass through the environment, which keeps
# them out of the command text. Automatic variables that loops and native
# commands set are not the profile's.
PROFILE_CHECK=''
IFS= read -r -d '' PROFILE_CHECK <<'POWERSHELL' || true
$before = (Get-Variable).Name
$Error.Clear()
. $env:CHECK_PROFILE
. $env:CHECK_PROFILE
$after = (Get-Variable).Name
$ignored = @($before) + 'before', 'foreach', 'LASTEXITCODE', 'Matches'
$problems = @(
    $after | Where-Object { $_ -notin $ignored } |
        ForEach-Object { "it leaves the variable `$$_ behind" }
    $Error | ForEach-Object { "it records an error: $($_.InvocationInfo.PositionMessage -replace '\s+', ' ')" }
    $env:CHECK_COMMANDS -split ' ' | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) } |
        ForEach-Object { "it does not define $_" }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly PROFILE_CHECK
# COMMANDS_CHECK dot-sources CHECK_PROFILE and runs its commands against
# stand-ins, printing each that misbehaves: the update commands must run an exact
# winget upgrade of their package. Off Windows, where .NET does not save user
# environment variables, Set-GitHubToken must ignore an empty answer, save a
# trimmed one in the session, and remove it; on Windows it would change the real
# user environment, so it is not run there.
COMMANDS_CHECK=''
IFS= read -r -d '' COMMANDS_CHECK <<'POWERSHELL' || true
. $env:CHECK_PROFILE
function winget { "winget $args" }
$updates = @{ 'Update-PowerShell' = 'Microsoft.PowerShell'; 'Update-OhMyPosh' = 'JanDeDobbeleer.OhMyPosh' }
$problems = @(
    foreach ($update in $updates.GetEnumerator()) {
        $output = "$(& $update.Key)"
        if ($output -notlike "winget upgrade --id $($update.Value) --exact --source winget *") {
            "$($update.Key) ran: $output"
        }
    }
    if (-not $IsWindows) {
        $env:GITHUB_TOKEN = 'old'
        function Read-Host { [securestring]::new() }
        $null = Set-GitHubToken 3>$null
        if ($env:GITHUB_TOKEN -ne 'old') { 'Set-GitHubToken changed GITHUB_TOKEN on an empty answer' }
        function Read-Host { ConvertTo-SecureString ' new ' -AsPlainText -Force }
        $null = Set-GitHubToken
        if ($env:GITHUB_TOKEN -ne 'new') { 'Set-GitHubToken did not save the trimmed answer' }
        $null = Set-GitHubToken -Remove
        if ($env:GITHUB_TOKEN) { 'Set-GitHubToken -Remove left GITHUB_TOKEN set' }
    }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly COMMANDS_CHECK
# TOOLCHAIN_CHECK dot-sources CHECK_PROFILE in a home holding stand-ins for a
# .NET SDK and a Go toolchain from the installers, and prints each way the PATH
# and environment differ from what dotnet.ps1 and golang.ps1 promise. The
# stand-in go.exe is empty, so on Windows it also shows that a go that does not
# run leaves the profile silent.
TOOLCHAIN_CHECK=''
IFS= read -r -d '' TOOLCHAIN_CHECK <<'POWERSHELL' || true
. $env:CHECK_PROFILE
$entries = @($env:PATH -split [System.IO.Path]::PathSeparator)
$dotnet = Join-Path $HOME '.dotnet'
$goBin = Join-Path $HOME '.local/share/go/bin'
$problems = @(
    if ((@($entries | Select-Object -First 2) -join '|') -ne "$goBin|$dotnet") {
        "PATH does not start with $goBin and $dotnet`: $env:PATH"
    }
    if ($entries -notcontains (Join-Path $dotnet 'tools')) { "PATH lacks $(Join-Path $dotnet 'tools')" }
    if ($entries -notcontains (Join-Path $HOME '.local/bin')) { "PATH lacks $(Join-Path $HOME '.local/bin')" }
    if ($env:DOTNET_ROOT -ne $dotnet) { "DOTNET_ROOT is '$env:DOTNET_ROOT', not $dotnet" }
    if ($env:DOTNET_CLI_TELEMETRY_OPTOUT -ne '1' -or $env:DOTNET_NOLOGO -ne '1') {
        '.NET telemetry or its first-run banner is on'
    }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly TOOLCHAIN_CHECK
# DOTNET_DIR_CHECK dot-sources CHECK_PROFILE and prints the PATH and DOTNET_ROOT
# unless dotnet.ps1 used the SDK in DOTNET_INSTALL_DIR.
DOTNET_DIR_CHECK=''
IFS= read -r -d '' DOTNET_DIR_CHECK <<'POWERSHELL' || true
. $env:CHECK_PROFILE
if ($env:DOTNET_ROOT -ne $env:DOTNET_INSTALL_DIR -or
    ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $env:DOTNET_INSTALL_DIR) {
    "DOTNET_ROOT is '$env:DOTNET_ROOT' and PATH is $env:PATH"
    exit 1
}
POWERSHELL
readonly DOTNET_DIR_CHECK
# JSON_CHECK prints each file in JSON_FILES, one per line, that is not valid JSON.
JSON_CHECK=''
IFS= read -r -d '' JSON_CHECK <<'POWERSHELL' || true
$failed = $false
foreach ($path in $env:JSON_FILES -split "`n") {
    if (-not $path) { continue }
    if (-not (Test-Json -Json (Get-Content -LiteralPath $path -Raw) -ErrorAction SilentlyContinue)) {
        "{0}: not valid JSON" -f $path
        $failed = $true
    }
}
if ($failed) { exit 1 }
POWERSHELL
readonly JSON_CHECK
# WINGET_STANDIN stands in for winget when install-tools.ps1 runs. `export`
# writes the IDs in CHECK_WINGET_INSTALLED as installed, in the shape of
# winget's export file. `install` prints a line naming the package after --id,
# and exits with the status CHECK_WINGET_STATUS, in ID=STATUS lines, gives it.
WINGET_STANDIN=''
IFS= read -r -d '' WINGET_STANDIN <<'POWERSHELL' || true
if ($args[0] -eq 'export') {
    $packages = @($env:CHECK_WINGET_INSTALLED -split ' ' | ForEach-Object { @{ PackageIdentifier = $_ } })
    @{ Sources = @(@{ Packages = $packages }) } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $args[[array]::IndexOf($args, '--output') + 1]
    exit 0
}
$id = $args[[array]::IndexOf($args, '--id') + 1]
"winget output for $id"
exit [int](ConvertFrom-StringData $env:CHECK_WINGET_STATUS)[$id]
POWERSHELL
readonly WINGET_STANDIN
# The stand-in's packages and statuses: installed or upgraded (0), already
# current (0x8A15002B), already installed (0x8A150061), not upgradable by winget
# (0x8A150114), and an installer that failed (0x8A150006). All but the first
# and the already-installed one are installed already.
readonly WINGET_STATUS='Example.New=0
Example.Upgraded=0
Example.Current=-1978335189
Example.Kept=-1978335135
Example.SelfUpdating=-1978334956
Example.Broken=-1978335226'
readonly WINGET_INSTALLED='Example.Upgraded Example.Current Example.SelfUpdating Example.Broken'
# WSL_STATE_CHECK dot-sources the enable-wsl.ps1 in CHECK_HELPER, which then
# only defines its functions, and prints each case where Get-WslState decides
# wrongly. Each case gives whether the package runs, the Virtual Machine
# Platform and WSL features ($null when Windows does not say), whether a restart
# is pending, and the expected state.
WSL_STATE_CHECK=''
IFS= read -r -d '' WSL_STATE_CHECK <<'POWERSHELL' || true
. $env:CHECK_HELPER
$cases = @(
    @($true, $true, $true, $false, 'on'),
    @($true, $null, $null, $false, 'on'),
    @($true, $true, $true, $true, 'on'),
    @($true, $false, $true, $false, 'off'),
    @($true, $false, $true, $true, 'restart'),
    @($false, $true, $null, $true, 'restart'),
    @($false, $null, $true, $true, 'restart'),
    @($false, $null, $null, $true, 'off'),
    @($false, $false, $false, $false, 'off')
)
$problems = @(
    foreach ($case in $cases) {
        $state = Get-WslState -Package $case[0] -Platform $case[1] -Subsystem $case[2] -RestartPending $case[3]
        if ($state -ne $case[4]) {
            "Get-WslState package=$($case[0]) platform=$($case[1]) subsystem=$($case[2]) restart=$($case[3]) is $state, not $($case[4])"
        }
    }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly WSL_STATE_CHECK
# DOTNET_CHECK dot-sources the install-dotnet.ps1 in CHECK_HELPER, which then
# only defines its functions, and prints each way they misread a release list
# in Microsoft's shape, or the .NET directory CHECK_DIR, which holds sdk/10.0.403
# and shared/Microsoft.NETCore.App/10.0.7.
DOTNET_CHECK=''
IFS= read -r -d '' DOTNET_CHECK <<'POWERSHELL' || true
. $env:CHECK_HELPER
$metadata = @'
{"releases": [
  {"sdk": {"version": "10.0.403", "files": [{"hash": "aa"}]},
   "sdks": [{"version": "10.0.403", "files": [{"hash": "aa"}, {"hash": "bb"}]},
            {"version": "10.0.300", "files": [{"hash": "dd"}]}],
   "runtime": {"version": "10.0.7", "files": [{"hash": "cc"}]},
   "aspnetcore-runtime": null}
]}
'@ | ConvertFrom-Json
$problems = @(
    $hashes = (@(Get-PublishedHash -Metadata $metadata -Version '10.0.403', '10.0.7') | Sort-Object -Unique) -join ','
    if ($hashes -ne 'aa,bb,cc') { "Get-PublishedHash for 10.0.403 and 10.0.7 printed $hashes, not aa,bb,cc" }
    if (@(Get-PublishedHash -Metadata $metadata -Version '9.0.100').Count) {
        'Get-PublishedHash printed hashes for a version the list does not have'
    }
    $found = (@(Get-InstalledVersion $env:CHECK_DIR) | Sort-Object) -join ','
    if ($found -ne 'Microsoft.NETCore.App/10.0.7,sdk/10.0.403') { "Get-InstalledVersion found $found" }
    if (@(Get-InstalledVersion (Join-Path $env:CHECK_DIR 'missing')).Count) {
        'Get-InstalledVersion found versions in a directory that does not exist'
    }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly DOTNET_CHECK
# MANIFEST_CHECK prints each way the manifests in CHECK_REPO break the rules
# AGENTS.md gives them: each declares only Windows and lists no files, no step
# name is in both, each dotfiles.json step creates a file, every step says how
# setup knows it is done (creates, provides, or inputs), and every file under
# home/ that a step runs or passes exists, as does each input, which is under
# home/. A WSL step names "linux" alone in its own platforms, starts its name
# with wsl-, and uses files under home/wsl alone; every other step takes the
# Windows default and uses none of them.
MANIFEST_CHECK=''
IFS= read -r -d '' MANIFEST_CHECK <<'POWERSHELL' || true
$names = @()
$problems = @(
    foreach ($file in 'bootstrap.json', 'dotfiles.json') {
        $manifest = Get-Content -LiteralPath (Join-Path $env:CHECK_REPO $file) -Raw | ConvertFrom-Json
        if ((@($manifest.platforms) -join ',') -ne 'windows') { "$file does not declare platforms [""windows""] alone" }
        if ($manifest.PSObject.Properties.Name -contains 'files') { "$file lists files; every file under home/ is linked" }
        foreach ($step in @($manifest.setup)) {
            if ($names -contains $step.name) { "$file lists the $($step.name) step, which is listed already" }
            $names += $step.name
            if ($file -eq 'dotfiles.json' -and -not $step.creates) { "dotfiles.json's $($step.name) step creates no file" }
            if (-not ($step.creates -or $step.provides -or $step.inputs)) {
                "the $($step.name) step has no creates, provides, or inputs, so setup offers it every run"
            }
            $own = @($step.platforms) -join ','
            $wsl = $own -eq 'linux'
            if ($own -and -not $wsl) { "the $($step.name) step's platforms are $own, not linux alone" }
            if ($wsl -ne ($step.name -like 'wsl-*')) { "the $($step.name) step's name does not say whether it is for WSL" }
            $inputs = @($step.inputs | Where-Object { $null -ne $_ })
            foreach ($path in $inputs) {
                if ($path -notlike 'home/*') { "the $($step.name) step's input $path is not under home/" }
            }
            foreach ($word in @($step.run | ForEach-Object { $_ }) + $inputs) {
                if ($word -like 'home/*' -and -not (Test-Path -LiteralPath (Join-Path $env:CHECK_REPO $word) -PathType Leaf)) {
                    "the $($step.name) step uses $word, which does not exist"
                }
                if ($word -like 'home/*' -and ($word -like 'home/wsl/*') -ne $wsl) {
                    "the $($step.name) step is for $(if ($wsl) { 'WSL' } else { 'Windows' }) but uses $word"
                }
            }
        }
    }
)
$problems
if ($problems) { exit 1 }
POWERSHELL
readonly MANIFEST_CHECK
readonly HELPERS="$REPO/home/.local/share/helpers/pwsh"
# The WSL distribution's home, which homeskillet links there and never on
# Windows, and its bash helpers.
readonly WSL_HOME="$REPO/home/wsl"
readonly WSL_HELPERS="$WSL_HOME/.local/share/helpers/sh"
# The files in home/wsl that differ from dotfiles-linux's home/ on purpose; every
# other file there is a copy of dotfiles-linux's, byte for byte.
readonly -a WSL_OWN=(.bash_profile .config/apt/packages .local/share/helpers/sh/install-apt-packages.sh)
readonly TOOLS="$REPO/home/.config/winget/tools.psd1"
# The oldest homeskillet the README supports: the first release with check,
# bootstrap.json, inputs, {documents}, and home/wsl.
readonly MANAGER_MINIMUM=0.2.0
PWSH=''
HELPER_OUTPUT=''
HELPER_STATUS=0
MANAGER=''
MANAGER_OUTPUT=''
TEST_ROOT=''

# usage prints how to run the checks.
usage() {
    printf 'Usage: bash tests/check.sh [MANAGER]\n'
    printf 'Runs the PowerShell checks; with a homeskillet binary as MANAGER, also\n'
    printf 'links, checks, and unlinks every file under home/ in a temporary home.\n'
}

# die prints an error message and exits with status 2.
die() {
    printf 'check.sh: %s\n' "$1" >&2
    exit 2
}

# pass prints a success message for the given test name.
pass() {
    printf 'ok   %s\n' "$1"
}

# skip reports a check that cannot run here, such as one needing an absent tool.
skip() {
    printf 'skip %s: %s\n' "$1" "$2"
}

# fail prints a failure message for the given test name and reason, then exits.
fail() {
    printf 'FAIL %s: %s\n' "$1" "$2" >&2
    exit 1
}

# cleanup removes the temporary test root directory if it exists.
cleanup() {
    if [[ -n $TEST_ROOT && -d $TEST_ROOT ]]; then
        rm -rf -- "$TEST_ROOT"
    fi
}

# setup checks the required commands and creates a temporary test root.
setup() {
    local cmd
    for cmd in cut find grep ls mktemp readlink; do
        command -v "$cmd" >/dev/null || die "missing required command: $cmd"
    done
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-check.XXXXXX")
    # The pwsh checks run it by its path, since some give it an empty PATH.
    PWSH=$(command -v pwsh) || PWSH=''
}

# native_path PATH prints PATH as pwsh can open it: on Git Bash for Windows, a
# Windows path, since Git Bash converts single path arguments for Windows
# programs but not paths inside a list; elsewhere, PATH unchanged.
native_path() {
    if command -v cygpath >/dev/null; then
        cygpath -m -- "$1"
    else
        printf '%s\n' "$1"
    fi
}

# new_home prints a new empty directory to use as HOME.
new_home() {
    mktemp -d "$TEST_ROOT/home.XXXXXX"
}

# manage HOME COMMAND [OPTION...]
# Runs a manager command for this repository against HOME, acting for Windows,
# or for MANAGER_PLATFORM when that is set, and keeps its output in
# MANAGER_OUTPUT; a nonzero exit fails with that output.
manage() {
    local home=$1 command=$2 status=0
    shift 2
    MANAGER_OUTPUT=$("$MANAGER" "$command" --repo "$REPO" --home "$home" \
        --platform "${MANAGER_PLATFORM:-windows}" "$@" 2>&1) || status=$?
    if [[ $status -ne 0 ]]; then
        fail "homeskillet $command${*:+ $*}" "exit status $status: $MANAGER_OUTPUT"
    fi
}

# check_powershell parses and lints every PowerShell file in the repository and
# requires it to be ASCII (see scripts/check-powershell.sh).
check_powershell() {
    local path output status=0
    local -a files=()
    while IFS= read -r -d '' path; do
        files+=("$(native_path "$path")")
    done < <(find "$REPO" -name .git -prune -o -type f \( -name '*.ps1' -o -name '*.psm1' -o -name '*.psd1' \) -print0)
    [[ ${#files[@]} -gt 0 ]] || fail "PowerShell" "no PowerShell files found"
    output=$(bash "$REPO/scripts/check-powershell.sh" "${files[@]}" 2>&1) || status=$?
    case $status in
        0) pass "PowerShell files are ASCII, parse, and pass PSScriptAnalyzer" ;;
        3) skip "PowerShell syntax" "pwsh is not installed; the files are ASCII" ;;
        4) skip "PSScriptAnalyzer" "it is not installed; the PowerShell files are ASCII and parse" ;;
        *) fail "PowerShell" "$output" ;;
    esac
}

# run_helper HOME NAME [ARGUMENT...]
# Runs the helper NAME with HOME as the home, keeping its output in
# HELPER_OUTPUT and its exit status in HELPER_STATUS.
run_helper() {
    local home=$1 name=$2
    shift 2
    HELPER_STATUS=0
    HELPER_OUTPUT=$(HOME=$home "$PWSH" -NoLogo -NoProfile -NonInteractive -File "$HELPERS/$name" "$@" 2>&1) ||
        HELPER_STATUS=$?
}

# install_stub HOME writes the profile stub into HOME with init-profile.ps1, as
# the profile setup step does, and fails if it cannot.
install_stub() {
    run_helper "$1" init-profile.ps1 -Path "$(native_path "$1/$STUB")"
    [[ $HELPER_STATUS -eq 0 && -f $1/$STUB ]] ||
        fail "init-profile.ps1" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
}

# load_profile HOME EMPTY_PATH [CHECK] runs CHECK, PROFILE_CHECK by default, on
# the profile stub in HOME, which loads the profile, in a new pwsh with HOME as
# the home and EMPTY_PATH as PATH, so no real tool runs, printing the problems
# it finds and failing if any. pwsh's $HOME comes from USERPROFILE on Windows
# and from HOME elsewhere. On Windows the profile adds the saved PATH, so real
# tools can run; APPDATA and LOCALAPPDATA point into HOME too, so what they save,
# such as golang.ps1's `go telemetry off`, never changes the real settings.
load_profile() {
    HOME=$1 USERPROFILE=$(native_path "$1") PATH=$2 CHECK_PROFILE=$(native_path "$1/$STUB") \
        APPDATA=$(native_path "$1/AppData/Roaming") LOCALAPPDATA=$(native_path "$1/AppData/Local") \
        CHECK_COMMANDS="${PROFILE_COMMANDS[*]}" \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "${3:-$PROFILE_CHECK}" 2>&1
}

# check_profile loads the profile, through its stub, in a new pwsh whose home
# holds a copy of home/, with its snippets, and whose PATH is an empty
# directory, as on a machine without the tools they use. It requires the
# profile to print nothing, leave no variables behind, and define its
# documented commands, before and after init-local.ps1 adds the starter
# local.ps1.
check_profile() {
    local home empty output status=0
    if [[ -z $PWSH ]]; then
        skip "profile" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    empty=$(new_home)
    cp -R "$REPO/home/." "$home/"
    install_stub "$home"
    output=$(load_profile "$home" "$empty") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "profile" "exit status $status: $output"
    run_helper "$home" init-local.ps1
    [[ $HELPER_STATUS -eq 0 ]] || fail "profile, init-local.ps1" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    output=$(load_profile "$home" "$empty") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "profile with local.ps1" "exit status $status: $output"
    pass "the profile stub loads the profile and its snippets silently without their tools, defining their commands"
}

# check_commands runs the profile's commands against stand-ins (see
# COMMANDS_CHECK), in a home holding a copy of home/ and with an empty PATH.
check_commands() {
    local home empty output status=0
    if [[ -z $PWSH ]]; then
        skip "commands" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    empty=$(new_home)
    cp -R "$REPO/home/." "$home/"
    install_stub "$home"
    output=$(load_profile "$home" "$empty" "$COMMANDS_CHECK") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "commands" "exit status $status: $output"
    pass "the update commands run an exact winget upgrade; off Windows, Set-GitHubToken saves and removes the token"
}

# check_toolchains loads the profile in a home holding stand-ins for what
# install-dotnet.ps1 and install-golang.ps1 install (see TOOLCHAIN_CHECK), with
# an empty PATH.
check_toolchains() {
    local home empty output status=0
    if [[ -z $PWSH ]]; then
        skip "toolchains" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    empty=$(new_home)
    cp -R "$REPO/home/." "$home/"
    install_stub "$home"
    mkdir -p "$home/.dotnet/tools" "$home/.local/share/go/bin" "$home/.local/bin"
    : >"$home/.dotnet/dotnet.exe"
    : >"$home/.local/share/go/bin/go.exe"
    output=$(load_profile "$home" "$empty" "$TOOLCHAIN_CHECK") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "toolchains" "exit status $status: $output"
    # An SDK installed with DOTNET_INSTALL_DIR is the one dotnet.ps1 uses.
    mkdir -p "$home/sdk"
    : >"$home/sdk/dotnet.exe"
    output=$(DOTNET_INSTALL_DIR=$(native_path "$home/sdk") \
        load_profile "$home" "$empty" "$DOTNET_DIR_CHECK") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "toolchains, DOTNET_INSTALL_DIR" "exit status $status: $output"
    pass "dotnet.ps1 and golang.ps1 put the installers' toolchains first on PATH, quietly"
}

# check_installers checks that the helpers that download or change Windows
# settings print their usage for -Help, and reject bad arguments with status 2
# before they download, change, or create anything.
check_installers() {
    local home name call
    local -a words=()
    if [[ -z $PWSH ]]; then
        skip "installers" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    for name in install-golang.ps1 install-dotnet.ps1 enable-developer-mode.ps1 enable-wsl.ps1; do
        run_helper "$home" "$name" -Help
        [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Usage: '* ]] ||
            fail "$name -Help" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    done
    for call in 'install-golang.ps1 -Bogus' 'install-golang.ps1 1.x' 'install-golang.ps1 -Latest 1.26.10' \
        'install-dotnet.ps1 10.x' 'install-dotnet.ps1 10 -Channel 9.0' 'install-dotnet.ps1 -InstallDir' \
        'enable-developer-mode.ps1 -Bogus' 'enable-wsl.ps1 -Bogus' 'enable-wsl.ps1 -Distribution bad!name' \
        'enable-wsl.ps1 -Distribution Debian -NoDistribution' 'init-profile.ps1 stray -DryRun'; do
        read -ra words <<<"$call"
        run_helper "$home" "${words[@]}"
        [[ $HELPER_STATUS -eq 2 && -z $(ls -A "$home") ]] ||
            fail "$call" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    done
    pass "the installers and the Developer Mode and WSL helpers reject bad arguments before changing anything"
}

# expect_linux_go HOME LIST VERSION|MESSAGE [ARGUMENT...] runs install-go.sh
# --dry-run with HOME as the home and LIST as Go's release list, and fails
# unless it would install VERSION, or, for text that is not a version, prints
# that text.
expect_linux_go() {
    local home=$1 list=$2 expected=$3 output status=0
    shift 3
    output=$(HOME=$home GO_RELEASE_LIST=$list bash "$WSL_HELPERS/install-go.sh" --dry-run "$@" 2>&1) || status=$?
    if [[ $expected =~ ^go[0-9.]+$ ]]; then
        [[ $status -eq 0 && $output == "Would install $expected from https://go.dev/dl/$expected.linux-"* ]] ||
            fail "install-go.sh --dry-run $*" "expected $expected; exit status $status: $output"
    else
        [[ $status -eq 0 && $output == *"$expected"* ]] ||
            fail "install-go.sh --dry-run $*" "expected '$expected'; exit status $status: $output"
    fi
}

# check_wsl_helpers checks the bash helpers in home/wsl, which the WSL setup
# steps run there and which run here as on any Linux, without installing
# anything: their usage and arguments, which Go install-go.sh picks from a
# local release list, and what install-apt-packages.sh does against stand-ins
# for dpkg-query, apt-get, and sudo, whether packages are installed, missing
# with sudo refused, or missing with sudo allowed.
check_wsl_helpers() {
    local home bin list packages helper output status
    local sh_dir=$WSL_HELPERS
    # Root needs no sudo, so the apt checks that expect sudo cannot run as root.
    if [[ $EUID -eq 0 ]]; then
        skip "WSL helpers" "the checks run as root"
        return
    fi
    home=$(new_home)
    bin=$(new_home)
    for helper in install-go.sh install-apt-packages.sh; do
        bash -n "$sh_dir/$helper" || fail "$helper" "it does not parse"
        if grep -q $'\r' "$sh_dir/$helper"; then fail "$helper" "it has CRLF line endings, which bash in WSL rejects"; fi
        output=$(bash "$sh_dir/$helper" --help 2>&1) || fail "$helper --help" "$output"
        [[ $output == Usage:* ]] || fail "$helper --help" "$output"
        status=0
        output=$(bash "$sh_dir/$helper" --bogus 2>&1) || status=$?
        [[ $status -eq 2 ]] || fail "$helper --bogus" "exit status $status: $output"
    done

    list="$TEST_ROOT/go-releases-linux.json"
    go_release_list "$list" go1.26.9 go1.28rc1 go1.27.2 go1.26.10 go1.27.3
    expect_linux_go "$home" "$list" go1.26.10
    expect_linux_go "$home" "$list" go1.27.3 --latest
    expect_linux_go "$home" "$list" go1.27.2 1.27.2
    mkdir -p "$home/.local/share/go/bin"
    printf 'go1.26.10\n' >"$home/.local/share/go/VERSION"
    printf '#!/bin/sh\necho go1.26.10\n' >"$home/.local/share/go/bin/go"
    chmod +x "$home/.local/share/go/bin/go"
    expect_linux_go "$home" "$list" 'go1.26.10 is already installed'
    printf '#!/bin/sh\necho go1.27.3\n' >"$home/.local/share/go/bin/go"
    expect_linux_go "$home" "$list" 'is newer than go1.26.10; left alone'
    expect_linux_go "$home" "$list" go1.26.10 1.26.10
    pass "install-go.sh picks the newest patch of the release before the latest, and leaves a newer Go alone"

    # Stand-ins: dpkg-query reports a package installed when CHECK_DPKG lists
    # it, apt-get logs its arguments and records what it installs there, and
    # sudo runs its command only when CHECK_SUDO is allow.
    cat >"$bin/dpkg-query" <<'SH'
#!/bin/sh
grep -qx "$3" "$CHECK_DPKG" 2>/dev/null || exit 1
printf 'install ok installed'
SH
    cat >"$bin/apt-get" <<'SH'
#!/bin/sh
echo "$*" >>"$CHECK_APT_LOG"
[ "$1" = install ] || exit 0
for p in "$@"; do
    case $p in -* | install) ;; *) echo "$p" >>"$CHECK_DPKG" ;; esac
done
SH
    cat >"$bin/sudo" <<'SH'
#!/bin/sh
[ "$CHECK_SUDO" = allow ] || exit 1
[ "$1" != -n ] || shift
[ "$1" != -v ] || exit 0
exec "$@"
SH
    chmod +x "$bin/dpkg-query" "$bin/apt-get" "$bin/sudo"
    packages="$home/apt-packages"
    printf '# a comment\n\nmake  # after a name\n' >"$packages"
    printf 'make\n' >"$home/dpkg"
    run_apt "$bin" "$home" "$packages"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Already installed with apt: make' && ! -e $home/apt.log ]] ||
        fail "install-apt-packages.sh, installed" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    : >"$home/dpkg"
    run_apt "$bin" "$home" --dry-run "$packages"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Would install with apt: make' && ! -e $home/apt.log ]] ||
        fail "install-apt-packages.sh --dry-run" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    CHECK_SUDO=deny run_apt "$bin" "$home" "$packages"
    [[ $HELPER_STATUS -eq 1 && $HELPER_OUTPUT == *'needs sudo'* && ! -e $home/apt.log ]] ||
        fail "install-apt-packages.sh, sudo refused" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    CHECK_SUDO=allow run_apt "$bin" "$home" "$packages"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Installed with apt: make' &&
        $(<"$home/apt.log") == *'install -y'*' make'* ]] ||
        fail "install-apt-packages.sh, sudo allowed" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    printf 'Make!\n' >"$packages"
    run_apt "$bin" "$home" "$packages"
    [[ $HELPER_STATUS -eq 1 && $HELPER_OUTPUT == *'not a package name'* ]] ||
        fail "install-apt-packages.sh, bad name" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    pass "install-apt-packages.sh installs only missing packages, and only when sudo can run"
}

# run_apt BIN HOME [ARGUMENT...] runs install-apt-packages.sh with the
# stand-ins in BIN first on PATH and their state in HOME, keeping its output in
# HELPER_OUTPUT and its exit status in HELPER_STATUS. Its input is empty, so
# sudo finds no terminal to ask for a password at.
run_apt() {
    local bin=$1 home=$2
    shift 2
    HELPER_STATUS=0
    HELPER_OUTPUT=$(PATH="$bin:$PATH" CHECK_DPKG="$home/dpkg" CHECK_APT_LOG="$home/apt.log" \
        bash "$WSL_HELPERS/install-apt-packages.sh" "$@" </dev/null 2>&1) ||
        HELPER_STATUS=$?
}

# check_wsl_state checks how enable-wsl.ps1 reads WSL's state (see
# WSL_STATE_CHECK): on only when the package runs and its platform is not off,
# and waiting for a restart, rather than off, when part of WSL is on and Windows
# needs one, so the helper does not ask to turn WSL on twice.
check_wsl_state() {
    local output status=0
    if [[ -z $PWSH ]]; then
        skip "enable-wsl.ps1 state" "pwsh is not installed"
        return
    fi
    output=$(CHECK_HELPER=$(native_path "$HELPERS/enable-wsl.ps1") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$WSL_STATE_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "enable-wsl.ps1 state" "exit status $status: $output"
    pass "enable-wsl.ps1 turns WSL on only when it is off, and asks for a restart when one is pending"
}

# check_dotnet_hash checks the functions install-dotnet.ps1 uses to find what an
# install added and the SHA-512s Microsoft publishes for it (see DOTNET_CHECK),
# without downloading anything.
check_dotnet_hash() {
    local dir output status=0
    if [[ -z $PWSH ]]; then
        skip "install-dotnet.ps1 checksums" "pwsh is not installed"
        return
    fi
    dir=$(new_home)
    mkdir -p "$dir/sdk/10.0.403" "$dir/shared/Microsoft.NETCore.App/10.0.7"
    output=$(CHECK_HELPER=$(native_path "$HELPERS/install-dotnet.ps1") CHECK_DIR=$(native_path "$dir") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$DOTNET_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "install-dotnet.ps1 checksums" "exit status $status: $output"
    pass "install-dotnet.ps1 finds what an install added and the SHA-512s Microsoft publishes for it"
}

# go_release_list FILE VERSION... writes a release list in go.dev's JSON form
# to FILE: each VERSION, stable unless it is a release candidate, with a
# Windows zip for every CPU Go builds for.
go_release_list() {
    local file=$1 version arch stable release_sep='' file_sep
    shift
    {
        printf '['
        for version in "$@"; do
            stable=true
            [[ $version != *rc* ]] || stable=false
            printf '%s{"version": "%s", "stable": %s, "files": [' "$release_sep" "$version" "$stable"
            file_sep=''
            for arch in amd64 arm64 386; do
                printf '%s{"filename": "%s.windows-%s.zip", "os": "windows", "arch": "%s", "kind": "archive", "sha256": "%064d"}' \
                    "$file_sep" "$version" "$arch" "$arch" 0
                file_sep=', '
                printf '%s{"filename": "%s.linux-%s.tar.gz", "os": "linux", "arch": "%s", "kind": "archive", "sha256": "%064d"}' \
                    "$file_sep" "$version" "$arch" "$arch" 0
            done
            printf ']}'
            release_sep=', '
        done
        printf ']\n'
    } >"$file"
}

# expect_go HOME LIST VERSION [ARGUMENT...] runs install-golang.ps1 -DryRun with
# HOME as the home and LIST as Go's release list, and fails unless it would
# install VERSION.
expect_go() {
    local home=$1 list=$2 version=$3
    shift 3
    GO_RELEASE_LIST=$(native_path "$list") run_helper "$home" install-golang.ps1 -DryRun "$@"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == "Would install $version from https://go.dev/dl/$version.windows-"* ]] ||
        fail "install-golang.ps1 -DryRun $*" "expected $version; exit status $HELPER_STATUS: $HELPER_OUTPUT"
}

# check_go_versions checks which Go install-golang.ps1 picks, from a local
# release list out of version order and with a release candidate: by default
# the newest patch of the release before the latest, with -Latest or --latest
# the newest patch of the latest, or the version given. A rerun leaves a
# toolchain already at that version alone, and moves to a newer patch once the
# list has one.
check_go_versions() {
    local home list
    if [[ -z $PWSH ]]; then
        skip "install-golang.ps1 versions" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    list="$TEST_ROOT/go-releases.json"
    go_release_list "$list" go1.26.9 go1.28rc1 go1.27.2 go1.26.10 go1.27.3
    expect_go "$home" "$list" go1.26.10
    expect_go "$home" "$list" go1.27.3 -Latest
    expect_go "$home" "$list" go1.27.3 --latest
    expect_go "$home" "$list" go1.27.2 1.27.2

    mkdir -p "$home/.local/share/go/bin"
    printf 'go1.26.10\ntime 2026-01-01T00:00:00Z\n' >"$home/.local/share/go/VERSION"
    : >"$home/.local/share/go/bin/go.exe"
    GO_RELEASE_LIST=$(native_path "$list") run_helper "$home" install-golang.ps1
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'go1.26.10 is already installed'* ]] ||
        fail "install-golang.ps1, installed" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    go_release_list "$list" go1.26.9 go1.28rc1 go1.27.2 go1.26.10 go1.27.3 go1.26.11
    expect_go "$home" "$list" go1.26.11

    # A newer toolchain, as from -Latest, stays unless a version is given.
    printf 'go1.27.3\n' >"$home/.local/share/go/VERSION"
    GO_RELEASE_LIST=$(native_path "$list") run_helper "$home" install-golang.ps1
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'go1.27.3 in '*'is newer than go1.26.11'* ]] ||
        fail "install-golang.ps1, newer installed" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    expect_go "$home" "$list" go1.26.11 1.26.11
    pass "install-golang.ps1 picks the newest patch of the release before the latest, or the latest with --latest"
}

# check_init_helper HOME NAME FILE [ARGUMENT...] checks a helper that creates
# FILE, relative to HOME, once, giving it each ARGUMENT on every run: a dry run
# and a bad argument create nothing, a run creates it, the next leaves it alone,
# and -Force backs it up before replacing it.
check_init_helper() {
    local home=$1 name=$2 file=$3
    local -a backups=()
    shift 3
    run_helper "$home" "$name" -DryRun "$@"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Would create '* && ! -e $home/$file ]] ||
        fail "$name -DryRun" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" -Bogus "$@"
    [[ $HELPER_STATUS -eq 2 && ! -e $home/$file ]] ||
        fail "$name, usage" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" "$@"
    # A final newline: $(...) drops it, so the last byte reads as empty.
    [[ $HELPER_STATUS -eq 0 && -f $home/$file && -z $(tail -c 1 "$home/$file") ]] ||
        fail "$name, create" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" "$@"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == *'leaving it unchanged'* ]] ||
        fail "$name, existing file" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" -Force "$@"
    backups=("$home/$file".bak.*)
    [[ $HELPER_STATUS -eq 0 && -f $home/$file && ${#backups[@]} -eq 1 && -f ${backups[0]} ]] ||
        fail "$name -Force" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    pass "$name creates $file once, and -Force backs it up first"
}

# check_helpers checks every init helper, and that what each creates parses;
# the PowerShell files are also linted when PSScriptAnalyzer is installed.
check_helpers() {
    local home output status=0 lint=0
    if [[ -z $PWSH ]]; then
        skip "helpers" "pwsh is not installed"
        return
    fi
    check_init_helper "$(new_home)" init-local.ps1 .config/powershell/profile.d/local.ps1
    check_init_helper "$(new_home)" init-scoop-config.ps1 .config/scoop/config.json
    home=$(new_home)
    check_init_helper "$home" init-profile.ps1 "$STUB" -Path "$(native_path "$home/$STUB")"

    # Where PowerShell runs the dotfiles' profile itself, as on Linux and macOS,
    # init-profile.ps1 writes nothing: a stub there would load itself forever.
    home=$(new_home)
    run_helper "$home" init-profile.ps1 -Path "$(native_path "$home/.config/powershell/profile.ps1")"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == *'no stub is needed'* &&
        ! -e $home/.config/powershell/profile.ps1 ]] ||
        fail "init-profile.ps1, the profile itself" "exit status $HELPER_STATUS: $HELPER_OUTPUT"

    home=$(new_home)
    run_helper "$home" init-local.ps1
    run_helper "$home" init-scoop-config.ps1
    install_stub "$home"
    output=$(bash "$REPO/scripts/check-powershell.sh" \
        "$(native_path "$home/.config/powershell/profile.d/local.ps1")" \
        "$(native_path "$home/$STUB")" 2>&1) || lint=$?
    [[ $lint -eq 0 || $lint -eq 4 ]] || fail "init-local.ps1 and init-profile.ps1, what they write" "$output"
    output=$(JSON_FILES=$(native_path "$home/.config/scoop/config.json") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$JSON_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 ]] || fail "init-scoop-config.ps1, configuration" "$output"
    pass "the starter local.ps1, the profile stub, and the Scoop configuration parse"
}

# render_prompt THEME HOME DIR WIDTH prints the prompt that oh-my-posh renders for
# PowerShell from the theme file THEME with HOME for the directory DIR at WIDTH
# columns, without colors (--plain), and returns its status. env -i keeps out a
# live Oh My Posh session, whose cached config would otherwise be rendered in
# place of --config; on Windows, oh-my-posh still gets the system directory and
# a temporary directory, and HOME's AppData for its cache.
render_prompt() {
    env -i HOME="$2" USERPROFILE="$(native_path "$2")" PATH="$PATH" \
        LOCALAPPDATA="$(native_path "$2/AppData/Local")" APPDATA="$(native_path "$2/AppData/Roaming")" \
        SYSTEMROOT="${SYSTEMROOT:-}" TEMP="${TEMP:-/tmp}" TMP="${TMP:-/tmp}" \
        LANG=en_US.UTF-8 TERM=xterm-256color \
        oh-my-posh print primary --config "$(native_path "$1")" --shell pwsh --plain \
        --pwd "$(native_path "$3")" --terminal-width "$4" 2>&1
}

# leads_with_clock LINE succeeds when LINE starts with the date and time in the
# style of GNU date with a 12-hour clock, preceded only by glyphs, brackets, and
# spaces. Matching a regular expression across Nerd Font glyphs depends on the
# locale, which Git Bash leaves unset, so it cuts off what comes before the
# weekday and month and matches only the ASCII text from there.
leads_with_clock() {
    local clock='^[A-Z][a-z]{2} [A-Z][a-z]{2} [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2} (AM|PM) [^ ]+ [0-9]{4}'
    local prefix=${1%%[A-Z][a-z][a-z] [A-Z][a-z][a-z] *}
    [[ $prefix != *[A-Za-z0-9]* && ${1#"$prefix"} =~ $clock ]]
}

# Every theme except jandedobbeleer, which stays identical to upstream, starts its
# top line with the date and time (see leads_with_clock) and shows the directory
# on that line; a theme with a right-aligned part moves that part to a line of
# its own when the terminal is too narrow for both. Runs when oh-my-posh is
# installed. A template error would print in place of the time (with a stray %
# or none at all).
check_prompt_themes() {
    local home dir theme name output status top
    if ! command -v oh-my-posh >/dev/null; then
        skip "oh-my-posh themes render" "oh-my-posh is not installed"
        return
    fi
    home=$(new_home)
    dir="$home/prompt-dir"
    mkdir "$dir"
    for theme in "$REPO"/home/.config/oh-my-posh/themes/*.omp.json; do
        name=${theme##*/}
        name=${name%.omp.json}
        [[ $name != jandedobbeleer ]] || continue
        status=0
        output=$(render_prompt "$theme" "$home" "$dir" 120) || status=$?
        top=${output%%$'\n'*}
        if [[ $status -ne 0 || $output == *'%'* || $top != *prompt-dir* ]] || ! leads_with_clock "$top"; then
            fail "$name theme" "the clock does not lead the top line (exit status $status): $output"
        fi
        if grep -q '"alignment": "right"' "$theme"; then
            status=0
            output=$(render_prompt "$theme" "$home" "$dir" 50) || status=$?
            top=${output%%$'\n'*}
            if [[ $status -ne 0 || $top == *prompt-dir* || $output != *prompt-dir* ]] || ! leads_with_clock "$top"; then
                fail "$name theme, narrow terminal" "exit status $status: $output"
            fi
        fi
        pass "$name theme starts its top line with the date and time"
    done
}

# check_json requires every JSON file in the repository, such as the manifest,
# the themes, and the Windows Terminal fragment, to be valid JSON.
check_json() {
    local path output status=0
    local -a files=()
    if [[ -z $PWSH ]]; then
        skip "JSON" "pwsh is not installed"
        return
    fi
    while IFS= read -r -d '' path; do
        files+=("$(native_path "$path")")
    done < <(find "$REPO" -name .git -prune -o -type f -name '*.json' -print0)
    [[ ${#files[@]} -gt 0 ]] || fail "JSON" "no JSON files found"
    output=$(JSON_FILES=$(printf '%s\n' "${files[@]}") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$JSON_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 ]] || fail "JSON" "$output"
    pass "JSON files parse"
}

# check_sister_files requires the files kept identical to match: home/wsl's
# Oh My Posh themes always match home/'s. When the sister repositories are
# cloned beside this one, the themes also match dotfiles-linux's and
# dotfiles-macos', and every file in home/wsl but those in WSL_OWN matches
# dotfiles-linux's home/. CI has only this repository, so that part skips.
check_sister_files() {
    local sister file theme path own checked=0
    for theme in "$REPO"/home/.config/oh-my-posh/themes/*.omp.json; do
        cmp -s "$theme" "$WSL_HOME/.config/oh-my-posh/themes/${theme##*/}" ||
            fail "sister files" "home/wsl's ${theme##*/} differs from home/'s"
    done
    for theme in "$WSL_HOME"/.config/oh-my-posh/themes/*.omp.json; do
        [[ -f $REPO/home/.config/oh-my-posh/themes/${theme##*/} ]] ||
            fail "sister files" "home/wsl has ${theme##*/}, which home/ lacks"
    done
    for sister in dotfiles-linux dotfiles-macos; do
        [[ -d $REPO/../$sister/home ]] || continue
        for theme in "$REPO"/home/.config/oh-my-posh/themes/*.omp.json; do
            file="$REPO/../$sister/home/.config/oh-my-posh/themes/${theme##*/}"
            [[ -f $file ]] || fail "sister files" "$sister has no ${theme##*/}"
            cmp -s "$theme" "$file" || fail "sister files" "${theme##*/} differs from $sister's"
        done
        checked=$((checked + 1))
    done
    if [[ -d $REPO/../dotfiles-linux/home ]]; then
        while IFS= read -r -d '' file; do
            path=${file#"$WSL_HOME/"}
            for own in "${WSL_OWN[@]}"; do
                [[ $path != "$own" ]] || continue 2
            done
            [[ -f $REPO/../dotfiles-linux/home/$path ]] || fail "sister files" "dotfiles-linux has no home/$path"
            cmp -s "$file" "$REPO/../dotfiles-linux/home/$path" ||
                fail "sister files" "home/wsl/$path differs from dotfiles-linux's home/$path"
        done < <(find "$WSL_HOME" -type f -print0)
    fi
    if [[ $checked -eq 0 ]]; then
        skip "sister files" "home/wsl's themes match home/'s; dotfiles-linux and dotfiles-macos are not cloned beside this repository"
        return
    fi
    pass "home/wsl matches dotfiles-linux but for its own files, and the themes match everywhere"
}

# check_wsl_home checks the files homeskillet links into the WSL home: every
# bash file parses and every file has LF line endings, which bash in WSL needs;
# and the login shell's files, .bash_profile then .bashrc and its snippets,
# load silently from a copy of home/wsl with only the base system's commands.
check_wsl_home() {
    local file home output status=0
    while IFS= read -r -d '' file; do
        if grep -q $'\r' "$file"; then fail "home/wsl" "${file#"$REPO/"} has CRLF line endings"; fi
        case $file in
            *.sh | */.bashrc | */.bash_profile | */.bash_logout)
                bash -n "$file" || fail "home/wsl" "${file#"$REPO/"} does not parse"
                ;;
        esac
    done < <(find "$WSL_HOME" -type f -print0)
    home=$(new_home)
    cp -R "$WSL_HOME/." "$home/"
    output=$(env -i HOME="$home" PATH=/usr/bin:/bin bash -c '. "$HOME/.bash_profile"' 2>&1) || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "home/wsl login shell" "exit status $status: $output"
    pass "home/wsl's bash files parse with LF endings, and its login shell loads silently"
}

# check_manifests checks bootstrap.json and dotfiles.json against the rules
# AGENTS.md gives them (see MANIFEST_CHECK), without a manager, then checks
# that a copy whose bootstrap.json breaks each rule about done checks and
# inputs once is caught, with exactly those problems.
check_manifests() {
    local output status=0 repo expected
    if [[ -z $PWSH ]]; then
        skip "manifests" "pwsh is not installed"
        return
    fi
    output=$(CHECK_REPO=$(native_path "$REPO") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$MANIFEST_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "manifests" "exit status $status: $output"
    pass "bootstrap.json installs tools and dotfiles.json creates files, each for Windows, sharing no step"

    repo=$(mktemp -d "$TEST_ROOT/manifests.XXXXXX")
    cp -R "$REPO/home" "$REPO/dotfiles.json" "$repo/"
    cat >"$repo/bootstrap.json" <<'JSON'
{
  "platforms": ["windows"],
  "setup": [
    { "name": "always", "run": ["pwsh", "-File", "home/.local/share/helpers/pwsh/install-tools.ps1"] },
    { "name": "outside", "run": ["pwsh"], "inputs": ["scripts/check-secrets.sh"] },
    { "name": "missing", "run": ["pwsh"], "inputs": ["home/.config/winget/missing.psd1"] },
    { "name": "wsl-crossed", "run": ["bash"], "platforms": ["linux"], "inputs": ["home/.config/winget/tools.psd1"] }
  ]
}
JSON
    expected="the always step has no creates, provides, or inputs, so setup offers it every run
the outside step's input scripts/check-secrets.sh is not under home/
the missing step uses home/.config/winget/missing.psd1, which does not exist
the wsl-crossed step is for WSL but uses home/.config/winget/tools.psd1"
    status=0
    output=$(CHECK_REPO=$(native_path "$repo") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$MANIFEST_CHECK" 2>&1) || status=$?
    output=${output//$'\r'/}
    [[ $status -eq 1 && $output == "$expected" ]] ||
        fail "manifests, broken copy" "exit status $status: $output"
    pass "every step says how setup knows it is done, and its inputs are files under its own part of home/"
}

# step_names MANIFEST PLATFORM prints the name of each setup step MANIFEST lists
# for PLATFORM, windows or linux, one per line: a step that names "linux" in
# its own platforms is for Linux, and every other one takes the manifests'
# Windows default. Each step's entry ends at its closing brace.
step_names() {
    awk -v platform="$2" '
        BEGIN { RS = "}" }
        match($0, /"name": *"[^"]*"/) {
            name = substr($0, RSTART, RLENGTH)
            sub(/^"name": *"/, "", name)
            sub(/"$/, "", name)
            linux = ($0 ~ /"platforms": *\["linux"\]/)
            if ((platform == "linux") == linux) print name
        }' "$1"
}

# check_install_tools checks that install-tools.ps1 -DryRun prints an exact
# winget install for every package tools.psd1 lists, without needing winget, and
# that a missing list and a bad argument fail. Against a stand-in winget (see
# WINGET_STANDIN), alone on PATH, it requires one line per package saying what
# happened, winget's output only for the package that failed, and failure for
# that package alone; with -NoUpgrade, installed packages share one line and
# winget never runs for them, so the failing one is not tried.
check_install_tools() {
    local home bin list id ids line
    if [[ -z $PWSH ]]; then
        skip "install-tools.ps1" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    ids=$(CHECK_TOOLS=$TOOLS "$PWSH" -NoLogo -NoProfile -NonInteractive \
        -Command '(Import-PowerShellDataFile -LiteralPath $env:CHECK_TOOLS).WingetPackages.Id') ||
        fail "tools.psd1" "$ids"
    [[ -n $ids ]] || fail "tools.psd1" "it lists no packages"
    run_helper "$home" install-tools.ps1 -DryRun -Path "$TOOLS"
    [[ $HELPER_STATUS -eq 0 ]] || fail "install-tools.ps1 -DryRun" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    while IFS= read -r id; do
        id=${id%$'\r'}
        [[ $HELPER_OUTPUT == *"winget install --id $id --exact --source winget "* ]] ||
            fail "install-tools.ps1 -DryRun" "no winget install for $id: $HELPER_OUTPUT"
    done <<<"$ids"
    run_helper "$home" install-tools.ps1 -DryRun
    [[ $HELPER_STATUS -eq 1 && $HELPER_OUTPUT == *missing* ]] ||
        fail "install-tools.ps1, missing list" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" install-tools.ps1 -Bogus
    [[ $HELPER_STATUS -eq 2 ]] || fail "install-tools.ps1, usage" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" install-tools.ps1 stray -DryRun
    [[ $HELPER_STATUS -eq 2 ]] || fail "install-tools.ps1, stray word" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    pass "install-tools.ps1 -DryRun installs every package tools.psd1 lists"

    bin=$(new_home)
    printf '%s' "$WINGET_STANDIN" >"$bin/winget.ps1"
    list=$home/tools.psd1
    {
        printf '@{ WingetPackages = @(\n'
        while IFS== read -r id _; do
            printf "    @{ Id = '%s'; Name = '%s' }\n" "$id" "$id"
        done <<<"$WINGET_STATUS"
        printf ') }\n'
    } >"$list"
    PATH=$bin CHECK_WINGET_STATUS=$WINGET_STATUS CHECK_WINGET_INSTALLED=$WINGET_INSTALLED \
        run_helper "$home" install-tools.ps1 -Path "$(native_path "$list")"
    [[ $HELPER_STATUS -eq 1 ]] || fail "install-tools.ps1, a failed installer" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    for line in 'Example.New ... installed' 'Example.Upgraded ... upgraded' 'Example.Current ... up to date' \
        'Example.Kept ... already installed' 'Example.SelfUpdating ... installed; winget cannot upgrade it' \
        'Example.Broken ... failed, exit 0x8A150006' '    winget output for Example.Broken' \
        'Open a new terminal' 'failed: Example.Broken (exit 0x8A150006); '; do
        [[ $HELPER_OUTPUT == *"$line"* ]] || fail "install-tools.ps1, its report" "no '$line' in: $HELPER_OUTPUT"
    done
    [[ $HELPER_OUTPUT != *"winget output for Example.New"* ]] ||
        fail "install-tools.ps1, its report" "it shows winget's output for a package that installed: $HELPER_OUTPUT"
    PATH=$bin CHECK_WINGET_STATUS=$WINGET_STATUS CHECK_WINGET_INSTALLED=$WINGET_INSTALLED \
        run_helper "$home" install-tools.ps1 -Path "$(native_path "$list")" -NoUpgrade
    [[ $HELPER_STATUS -eq 0 &&
        $HELPER_OUTPUT == *"Already installed: Example.Upgraded, Example.Current, Example.SelfUpdating, Example.Broken"* &&
        $HELPER_OUTPUT == *'Example.New ... installed'* ]] ||
        fail "install-tools.ps1 -NoUpgrade" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    pass "install-tools.ps1 reports each package in one line, and -NoUpgrade runs winget only for missing ones"
}

# check_manager_platform checks that nothing applies on macOS, which homeskillet
# reports as an error naming the platforms that do: Windows, through the
# manifests, and Linux, through home/wsl and the WSL steps.
check_manager_platform() {
    local home output status=0
    home=$(new_home)
    output=$("$MANAGER" status --repo "$REPO" --home "$home" --platform darwin 2>&1) || status=$?
    [[ $status -ne 0 && $output == *windows* ]] ||
        fail "platforms" "expected nothing to apply on macOS, got status $status: $output"
    pass "nothing applies on macOS"
}

# check_manager_check runs the manager's own validation of both manifests and
# every file, for every platform: `homeskillet check` prints valid<TAB>REPO and
# exits 0, or one issue<TAB>TEXT line per problem and exits 1. A homeskillet
# without the command is older than MANAGER_MINIMUM, which the failure names.
check_manager_check() {
    local output status=0
    output=$("$MANAGER" check "$REPO" 2>&1) || status=$?
    if [[ $status -ne 0 && $output == *'unknown command "check"'* ]]; then
        fail "homeskillet check" "this homeskillet has no check command; the checks need $MANAGER_MINIMUM or later"
    fi
    [[ $status -eq 0 && $output == valid$'\t'* ]] || fail "homeskillet check" "exit status $status: $output"
    pass "homeskillet check finds both manifests and every file valid for every platform"
}

# check_manager_integration links, relinks, checks, and unlinks every file under
# home/ but home/wsl in an empty home, acting for Windows, then dry-runs the
# setup steps, which must be the Windows ones alone.
check_manager_integration() {
    local home setup_home path state name first before_bootstrap before_dotfiles count=0 listed=0
    local -a paths=()
    home=$(new_home)
    # The expected links are every file under home/ but home/wsl, found the way
    # homeskillet discovers them (skipping .DS_Store, Thumbs.db, desktop.ini,
    # and .git, in any case), so nothing here lists them.
    while IFS= read -r -d '' path; do
        paths+=("${path#"$REPO/home/"}")
    done < <(find "$REPO/home" \( -iname .git -o -path "$WSL_HOME" \) -prune -o \( -type f -o -type l \) \
        ! -iname .DS_Store ! -iname Thumbs.db ! -iname desktop.ini -print0)
    [[ ${#paths[@]} -gt 0 ]] || fail "link" "no files found under $REPO/home"

    manage "$home" link --dry-run
    [[ -z $(ls -A "$home") ]] || fail "link --dry-run" "it changed the test home"
    pass "link --dry-run changes nothing"

    manage "$home" link
    manage "$home" link
    for path in "${paths[@]}"; do
        [[ -L $home/$path && $(readlink "$home/$path") == "$REPO/home/$path" ]] ||
            fail "link" "$path does not link to $REPO/home/$path"
    done
    [[ ! -e $home/wsl ]] ||
        fail "link" "it linked home/wsl into the Windows home; the checks need homeskillet $MANAGER_MINIMUM or later"
    pass "link links every file under home/ but home/wsl, and is idempotent"

    manage "$home" status
    while IFS=$'\t' read -r state _; do
        [[ $state == linked ]] || fail "status" "unexpected state '$state'"
    done <<<"$MANAGER_OUTPUT"
    pass "status reports every file linked"

    manage "$home" unlink
    for path in "${paths[@]}"; do
        [[ ! -e $home/$path && ! -L $home/$path ]] || fail "unlink" "$path remains"
    done
    pass "unlink removes every link"

    # unlink leaves parent directories behind, so the dry run gets a fresh home.
    setup_home=$(new_home)
    manage "$setup_home" setup --dry-run
    [[ -n $MANAGER_OUTPUT ]] || fail "setup --dry-run" "no steps listed"
    [[ -z $(ls -A "$setup_home") ]] || fail "setup --dry-run" "it changed the test home"
    pass "setup --dry-run lists the steps and changes nothing"

    # The manager offers every step of bootstrap.json, then dotfiles.json's; one
    # older than MANAGER_MINIMUM reads only dotfiles.json and offers none of
    # bootstrap.json's. The WSL steps are for Linux, so none is offered here.
    while IFS= read -r name; do
        [[ $MANAGER_OUTPUT == *$'\t'"$name"$'\t'* ]] ||
            fail "setup --dry-run" "dotfiles.json's $name step is not listed: $MANAGER_OUTPUT"
    done < <(step_names "$REPO/dotfiles.json" windows)
    while IFS= read -r name; do
        [[ $MANAGER_OUTPUT != *$'\t'"$name"$'\t'* ]] ||
            fail "setup --dry-run" "the Linux step $name is offered for Windows: $MANAGER_OUTPUT"
    done < <(step_names "$REPO/bootstrap.json" linux; step_names "$REPO/dotfiles.json" linux)
    while IFS= read -r name; do
        count=$((count + 1))
        if [[ $MANAGER_OUTPUT == *$'\t'"$name"$'\t'* ]]; then
            listed=$((listed + 1))
        fi
    done < <(step_names "$REPO/bootstrap.json" windows)
    if [[ $listed -eq 0 ]]; then
        fail "setup --dry-run" "this homeskillet reads only dotfiles.json; the checks need $MANAGER_MINIMUM or later"
    elif [[ $listed -eq $count ]]; then
        first=$(step_names "$REPO/bootstrap.json" windows | head -n 1)
        before_bootstrap=${MANAGER_OUTPUT%%$'\t'"$first"$'\t'*}
        first=$(step_names "$REPO/dotfiles.json" windows | head -n 1)
        before_dotfiles=${MANAGER_OUTPUT%%$'\t'"$first"$'\t'*}
        [[ ${#before_bootstrap} -lt ${#before_dotfiles} ]] ||
            fail "setup --dry-run" "bootstrap.json's steps do not come first: $MANAGER_OUTPUT"
        pass "setup --dry-run offers bootstrap.json's steps, then dotfiles.json's"
    else
        fail "setup --dry-run" "only $listed of bootstrap.json's $count steps are listed: $MANAGER_OUTPUT"
    fi

    # The profile step is done once the stub exists in Documents: the manager
    # resolves {documents} in "creates" to the test home's Documents.
    [[ $MANAGER_OUTPUT == *$'pending\tprofile\t'* ]] ||
        fail "setup --dry-run, profile" "the profile step is not pending in an empty home: $MANAGER_OUTPUT"
    mkdir -p "$setup_home/${STUB%/*}"
    : >"$setup_home/$STUB"
    manage "$setup_home" setup --dry-run
    [[ $MANAGER_OUTPUT == *$'done\tprofile\t'* ]] ||
        fail "setup --dry-run, profile" \
            "the step is not done with the stub in Documents; the checks need homeskillet $MANAGER_MINIMUM or later: $MANAGER_OUTPUT"
    pass "the profile step is done once the stub is in Documents"
}

# check_manager_wsl links into an empty home acting for Linux, as `homeskillet
# wsl link` does inside the distribution: every file under home/wsl lands at
# the same path in the home, and nothing from the rest of home/. Then it
# dry-runs setup, which must offer the Linux steps alone, bootstrap.json's
# first.
check_manager_wsl() {
    local home setup_home path name first before_bootstrap before_dotfiles
    local -a paths=()
    while IFS= read -r -d '' path; do
        paths+=("${path#"$WSL_HOME/"}")
    done < <(find "$WSL_HOME" -type f -print0)
    home=$(new_home)
    MANAGER_PLATFORM=linux manage "$home" link
    [[ -L $home/.bashrc ]] ||
        fail "link, Linux" "it did not link home/wsl; the checks need homeskillet $MANAGER_MINIMUM or later"
    for path in "${paths[@]}"; do
        [[ -L $home/$path && $(readlink "$home/$path") == "$WSL_HOME/$path" ]] ||
            fail "link, Linux" "$path does not link to $WSL_HOME/$path"
    done
    [[ ! -e $home/wsl && ! -e $home/.config/powershell && ! -e $home/AppData ]] ||
        fail "link, Linux" "it linked files meant for Windows: $(ls -A "$home")"
    pass "acting for Linux, link links every file under home/wsl into the home, and nothing else"

    setup_home=$(new_home)
    MANAGER_PLATFORM=linux manage "$setup_home" setup --dry-run
    [[ -z $(ls -A "$setup_home") ]] || fail "setup --dry-run, Linux" "it changed the test home"
    while IFS= read -r name; do
        [[ $MANAGER_OUTPUT == *$'\t'"$name"$'\t'* ]] ||
            fail "setup --dry-run, Linux" "the Linux step $name is not listed: $MANAGER_OUTPUT"
    done < <(step_names "$REPO/bootstrap.json" linux; step_names "$REPO/dotfiles.json" linux)
    while IFS= read -r name; do
        [[ $MANAGER_OUTPUT != *$'\t'"$name"$'\t'* ]] ||
            fail "setup --dry-run, Linux" "the Windows step $name is offered for Linux: $MANAGER_OUTPUT"
    done < <(step_names "$REPO/bootstrap.json" windows; step_names "$REPO/dotfiles.json" windows)
    first=$(step_names "$REPO/bootstrap.json" linux | head -n 1)
    before_bootstrap=${MANAGER_OUTPUT%%$'\t'"$first"$'\t'*}
    first=$(step_names "$REPO/dotfiles.json" linux | head -n 1)
    before_dotfiles=${MANAGER_OUTPUT%%$'\t'"$first"$'\t'*}
    [[ ${#before_bootstrap} -lt ${#before_dotfiles} ]] ||
        fail "setup --dry-run, Linux" "bootstrap.json's Linux steps do not come first: $MANAGER_OUTPUT"
    pass "acting for Linux, setup --dry-run offers the WSL steps alone, bootstrap.json's first"
}

# main parses the arguments and runs the checks, then the manager checks when a
# manager is given.
main() {
    case $# in
        0) ;;
        1)
            if [[ $1 == -h || $1 == --help ]]; then
                usage
                return
            fi
            MANAGER=$(command -v -- "$1") || die "manager not found or not executable: $1"
            [[ -f $MANAGER && -x $MANAGER ]] || die "manager is not an executable file: $1"
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    setup

    check_powershell
    check_profile
    check_commands
    check_toolchains
    check_helpers
    check_install_tools
    check_installers
    check_wsl_state
    check_wsl_home
    check_wsl_helpers
    check_dotnet_hash
    check_go_versions
    check_prompt_themes
    check_json
    check_manifests
    check_sister_files
    printf 'PowerShell and JSON checks passed.\n'

    if [[ -n $MANAGER ]]; then
        check_manager_platform
        check_manager_check
        check_manager_integration
        check_manager_wsl
        printf 'Manager integration checks passed.\n'
    fi
}
# Execute the main function with all command-line arguments.
main "$@"
