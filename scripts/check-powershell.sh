#!/usr/bin/env bash
# Checks PowerShell files for syntax errors and for characters other than ASCII.
#
# Usage: bash scripts/check-powershell.sh FILE...
#
# Syntax is checked by PowerShell's own parser, so pwsh must be installed
# (https://learn.microsoft.com/powershell/scripting/install/installing-powershell);
# it runs on Linux and macOS too. ASCII is required because Windows PowerShell 5.1
# reads a script without a byte-order mark in the system's ANSI code page, which
# garbles every other character.
# Exit status: 0 clean, 1 findings, 2 usage error, 3 pwsh is not installed.
set -euo pipefail
# CDPATH can redirect cd to another directory and make it print the path.
unset CDPATH

# Global variables
# PARSER reads the files to check from PS_FILES, one per line, and prints each
# syntax error as FILE:LINE: MESSAGE. Passing the names through the environment
# keeps them out of the command text, where pwsh would interpret them.
PARSER=''
IFS= read -r -d '' PARSER <<'POWERSHELL' || true
$failed = $false
foreach ($path in $env:PS_FILES -split "`n") {
    if (-not $path) { continue }
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
    foreach ($e in $errors) {
        "{0}:{1}: {2}" -f $path, $e.Extent.StartLineNumber, $e.Message
        $failed = $true
    }
}
if ($failed) { exit 1 }
POWERSHELL
readonly PARSER
FINDINGS=0

# usage prints how to run the script.
usage() {
    printf 'Usage: bash scripts/check-powershell.sh FILE...\n'
}

# check_ascii reports each line of FILE holding a byte outside printable ASCII,
# tabs, and line endings, by line number only.
check_ascii() {
    local file=$1 line
    while IFS= read -r line; do
        printf '%s:%s: a character other than ASCII\n' "$file" "$line"
        FINDINGS=1
    done < <(LC_ALL=C grep -n '[^[:print:][:space:]]' -- "$file" | cut -d: -f1 || true)
}

# main checks every FILE for ASCII, then parses them all with one pwsh process.
main() {
    local file status=0
    if [[ $# -eq 0 || ${1-} == -h || ${1-} == --help ]]; then
        usage
        [[ $# -gt 0 ]] || exit 2
        return 0
    fi
    for file in "$@"; do
        [[ -f $file ]] || {
            printf 'check-powershell.sh: no such file: %s\n' "$file" >&2
            exit 2
        }
        [[ $file != *$'\n'* ]] || {
            printf 'check-powershell.sh: file names cannot contain newlines\n' >&2
            exit 2
        }
        check_ascii "$file"
    done
    # Without pwsh, ASCII findings still fail; only the syntax check is skipped.
    if ! command -v pwsh >/dev/null; then
        printf 'check-powershell.sh: pwsh is not installed, so syntax was not checked\n' >&2
        [[ $FINDINGS -eq 0 ]] || exit 1
        exit 3
    fi
    PS_FILES=$(printf '%s\n' "$@") pwsh -NoLogo -NoProfile -NonInteractive -Command "$PARSER" || status=1
    if [[ $FINDINGS -ne 0 || $status -ne 0 ]]; then
        exit 1
    fi
}
# Execute the main function with all command-line arguments.
main "$@"
