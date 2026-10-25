#!/usr/bin/env bash
# Regression checks for the PowerShell files and, optionally, the manager.
#
# Usage: bash tests/check.sh [MANAGER]
#
# homeskillet does not run on Windows yet, so these checks run on Linux or macOS,
# as CI does on Ubuntu. They parse every PowerShell file with pwsh when it is
# installed. Passing a built homeskillet binary as MANAGER also links, checks, and
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
        files+=("$path")
    done < <(find "$REPO" -name .git -prune -o -type f \( -name '*.ps1' -o -name '*.psm1' -o -name '*.psd1' \) -print0)
    [[ ${#files[@]} -gt 0 ]] || fail "PowerShell" "no PowerShell files found"
    output=$(bash "$REPO/scripts/check-powershell.sh" "${files[@]}" 2>&1) || status=$?
    case $status in
        0) pass "PowerShell files parse and are ASCII" ;;
        3) skip "PowerShell syntax" "pwsh is not installed; the files are ASCII" ;;
        *) fail "PowerShell" "$output" ;;
    esac
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
    printf 'PowerShell checks passed.\n'

    if [[ -n $MANAGER ]]; then
        check_manager_platform
        check_manager_integration
        printf 'Manager integration checks passed.\n'
    fi
}
# Execute the main function with all command-line arguments.
main "$@"
