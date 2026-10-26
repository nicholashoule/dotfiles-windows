#!/usr/bin/env bash
# Regression checks for the PowerShell files and, optionally, the manager.
#
# Usage: bash tests/check.sh [MANAGER]
#
# homeskillet does not run on Windows yet, so these checks run on Linux or macOS,
# as CI does on Ubuntu. When pwsh is installed, they parse every PowerShell file,
# load the profile and its snippets as a machine without its tools would, run
# the helpers in a temporary home, and parse every JSON file. Passing a built
# homeskillet binary as MANAGER also links, checks, and
# unlinks every file under home/ in a temporary home, acting for Windows with
# --platform windows, and lists the setup steps without running them.
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
readonly PROFILE="$REPO/home/Documents/PowerShell/profile.ps1"
# The commands the README documents for the profile.
readonly -a PROFILE_COMMANDS=(
    ls la ll env hist edit-last gs gitcm Update-WingetPackage
    Update-PowerShell update-pwsh Update-OhMyPosh update-omp
    Set-GitHubToken set-gh-token New-GpgSigningKey new-gpg-key gpg-key-1y gpg-key-5y gpg-key-10y
    Get-GpgPublicKey gpg-pub Copy-GpgPublicKey gpg-pub-copy
    Get-GpgKeyId gpg-keyid Get-GpgKeyIdShort gpg-keyid-short
    Set-GitGpgSigningKey git-sign-key Add-SshKey
)
# PROFILE_CHECK dot-sources CHECK_PROFILE and prints each variable it leaves
# behind and each command in CHECK_COMMANDS it does not define. Paths and names
# pass through the environment, which keeps them out of the command text.
# Automatic variables that loops and native commands set are not the profile's.
PROFILE_CHECK=''
IFS= read -r -d '' PROFILE_CHECK <<'POWERSHELL' || true
$before = (Get-Variable).Name
. $env:CHECK_PROFILE
$after = (Get-Variable).Name
$ignored = @($before) + 'before', 'foreach', 'LASTEXITCODE', 'Matches'
$problems = @(
    $after | Where-Object { $_ -notin $ignored } |
        ForEach-Object { "it leaves the variable `$$_ behind" }
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
readonly HELPERS="$REPO/home/.local/share/helpers/pwsh"
readonly TOOLS="$REPO/home/.config/winget/tools.psd1"
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
# and keeps its output in MANAGER_OUTPUT; a nonzero exit fails with that output.
manage() {
    local home=$1 command=$2 status=0
    shift 2
    MANAGER_OUTPUT=$("$MANAGER" "$command" --repo "$REPO" --home "$home" --platform windows "$@" 2>&1) ||
        status=$?
    if [[ $status -ne 0 ]]; then
        fail "homeskillet $command${*:+ $*}" "exit status $status: $MANAGER_OUTPUT"
    fi
}

# check_powershell parses every PowerShell file in the repository and requires
# it to be ASCII (see scripts/check-powershell.sh).
check_powershell() {
    local path output status=0
    local -a files=()
    while IFS= read -r -d '' path; do
        files+=("$(native_path "$path")")
    done < <(find "$REPO" -name .git -prune -o -type f \( -name '*.ps1' -o -name '*.psm1' -o -name '*.psd1' \) -print0)
    [[ ${#files[@]} -gt 0 ]] || fail "PowerShell" "no PowerShell files found"
    output=$(bash "$REPO/scripts/check-powershell.sh" "${files[@]}" 2>&1) || status=$?
    case $status in
        0) pass "PowerShell files parse and are ASCII" ;;
        3) skip "PowerShell syntax" "pwsh is not installed; the files are ASCII" ;;
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

# load_profile HOME EMPTY_PATH [CHECK] runs CHECK, PROFILE_CHECK by default, in a
# new pwsh with HOME as the home and EMPTY_PATH as PATH, so no real tool runs,
# printing the problems it finds and failing if any. pwsh's $HOME comes from
# USERPROFILE on Windows and from HOME elsewhere.
load_profile() {
    HOME=$1 USERPROFILE=$(native_path "$1") PATH=$2 CHECK_PROFILE=$PROFILE \
        CHECK_COMMANDS="${PROFILE_COMMANDS[*]}" \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "${3:-$PROFILE_CHECK}" 2>&1
}

# check_profile loads the profile in a new pwsh whose home holds a copy of home/,
# with its snippets, and whose PATH is an empty directory, as on a machine
# without the tools they use. It requires the profile to print nothing, leave no
# variables behind, and define its documented commands, before and after
# init-local.ps1 adds the starter local.ps1.
check_profile() {
    local home empty output status=0
    if [[ -z $PWSH ]]; then
        skip "profile" "pwsh is not installed"
        return
    fi
    home=$(new_home)
    empty=$(new_home)
    cp -R "$REPO/home/." "$home/"
    output=$(load_profile "$home" "$empty") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "profile" "exit status $status: $output"
    run_helper "$home" init-local.ps1
    [[ $HELPER_STATUS -eq 0 ]] || fail "profile, init-local.ps1" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    output=$(load_profile "$home" "$empty") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "profile with local.ps1" "exit status $status: $output"
    pass "the profile and its snippets load silently without their tools and define their commands"
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
    output=$(load_profile "$home" "$empty" "$COMMANDS_CHECK") || status=$?
    [[ $status -eq 0 && -z $output ]] || fail "commands" "exit status $status: $output"
    pass "the update commands run an exact winget upgrade; off Windows, Set-GitHubToken saves and removes the token"
}

# check_init_helper NAME FILE checks a helper that creates FILE, relative to the
# home, once: a dry run and a bad argument create nothing, a run creates it, the
# next leaves it alone, and -Force backs it up before replacing it.
check_init_helper() {
    local name=$1 file=$2 home
    local -a backups=()
    home=$(new_home)
    run_helper "$home" "$name" -DryRun
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == 'Would create '* && ! -e $home/$file ]] ||
        fail "$name -DryRun" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" -Bogus
    [[ $HELPER_STATUS -eq 2 && ! -e $home/$file ]] ||
        fail "$name, usage" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name"
    # A final newline: $(...) drops it, so the last byte reads as empty.
    [[ $HELPER_STATUS -eq 0 && -f $home/$file && -z $(tail -c 1 "$home/$file") ]] ||
        fail "$name, create" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name"
    [[ $HELPER_STATUS -eq 0 && $HELPER_OUTPUT == *'leaving it unchanged'* ]] ||
        fail "$name, existing file" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    run_helper "$home" "$name" -Force
    backups=("$home/$file".bak.*)
    [[ $HELPER_STATUS -eq 0 && -f $home/$file && ${#backups[@]} -eq 1 && -f ${backups[0]} ]] ||
        fail "$name -Force" "exit status $HELPER_STATUS: $HELPER_OUTPUT"
    pass "$name creates $file once, and -Force backs it up first"
}

# check_helpers checks every init helper, and that what each creates parses.
check_helpers() {
    local home output status=0
    if [[ -z $PWSH ]]; then
        skip "helpers" "pwsh is not installed"
        return
    fi
    check_init_helper init-local.ps1 .config/powershell/profile.d/local.ps1
    check_init_helper init-scoop-config.ps1 .config/scoop/config.json

    home=$(new_home)
    run_helper "$home" init-local.ps1
    run_helper "$home" init-scoop-config.ps1
    output=$(bash "$REPO/scripts/check-powershell.sh" \
        "$(native_path "$home/.config/powershell/profile.d/local.ps1")" 2>&1) ||
        fail "init-local.ps1, starter" "$output"
    output=$(JSON_FILES=$(native_path "$home/.config/scoop/config.json") \
        "$PWSH" -NoLogo -NoProfile -NonInteractive -Command "$JSON_CHECK" 2>&1) || status=$?
    [[ $status -eq 0 ]] || fail "init-scoop-config.ps1, configuration" "$output"
    pass "the starter local.ps1 and the Scoop configuration parse"
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

# check_install_tools checks that install-tools.ps1 -DryRun prints an exact
# winget install for every package tools.psd1 lists, without needing winget, and
# that a missing list and a bad argument fail.
check_install_tools() {
    local home id ids
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
    pass "install-tools.ps1 -DryRun installs every package tools.psd1 lists"
}

# check_manager_platform checks that the manifest targets Windows only: acting
# for the detected platform, Linux or macOS, nothing applies, which homeskillet
# reports as an error naming the manifest's platforms.
check_manager_platform() {
    local home output status=0
    home=$(new_home)
    output=$("$MANAGER" status --repo "$REPO" --home "$home" 2>&1) || status=$?
    [[ $status -ne 0 && $output == *windows* ]] ||
        fail "platforms" "expected nothing to apply off Windows, got status $status: $output"
    pass "the manifest targets Windows only"
}

# check_manager_integration links, relinks, checks, and unlinks every file under
# home/ in an empty home, then dry-runs the setup steps.
check_manager_integration() {
    local home setup_home path state
    local -a paths=()
    home=$(new_home)
    # The expected links are every file under home/, found the way homeskillet
    # discovers them (skipping .DS_Store, Thumbs.db, desktop.ini, and .git, in
    # any case), so nothing here lists them.
    while IFS= read -r -d '' path; do
        paths+=("${path#"$REPO/home/"}")
    done < <(find "$REPO/home" -iname .git -prune -o \( -type f -o -type l \) \
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
    pass "link links every file under home/ and is idempotent"

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
    check_helpers
    check_install_tools
    check_json
    printf 'PowerShell and JSON checks passed.\n'

    if [[ -n $MANAGER ]]; then
        check_manager_platform
        check_manager_integration
        printf 'Manager integration checks passed.\n'
    fi
}
# Execute the main function with all command-line arguments.
main "$@"
