#!/usr/bin/env bash
# Checks PowerShell files for characters other than ASCII, syntax errors, and
# PSScriptAnalyzer findings.
#
# Usage: bash scripts/check-powershell.sh FILE...
#
# Syntax is checked by PowerShell's own parser, so pwsh must be installed
# (https://learn.microsoft.com/powershell/scripting/install/installing-powershell);
# it runs on Linux and macOS too. The files that parse are then linted by
# PSScriptAnalyzer (https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)
# with PSScriptAnalyzerSettings.psd1 beside this script, when the module is
# installed. ASCII is required because Windows PowerShell 5.1 reads a script
# without a byte-order mark in the system's ANSI code page, which garbles every
# other character.
# Exit status: 0 clean, 1 findings, 2 usage error, 3 pwsh is not installed (only
# ASCII was checked), 4 PSScriptAnalyzer is not installed (ASCII and syntax were).
set -euo pipefail
# CDPATH can redirect cd to another directory and make it print the path.
unset CDPATH

# Global variables
SETTINGS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/PSScriptAnalyzerSettings.psd1"
readonly SETTINGS
# CHECKER reads the files to check from PS_FILES, one per line, and prints each
# syntax error, then each PSScriptAnalyzer finding under the settings file
# PS_SETTINGS, as FILE:LINE: MESSAGE. Passing the names through the environment
# keeps them out of the command text, where pwsh would interpret them. It exits
# 1 on any finding, and otherwise 4 when PSScriptAnalyzer is not installed.
CHECKER=''
IFS= read -r -d '' CHECKER <<'POWERSHELL' || true
$failed = $false
$parsed = [System.Collections.Generic.List[string]]::new()
foreach ($path in $env:PS_FILES -split "`n") {
    if (-not $path) { continue }
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
    foreach ($e in $errors) {
        "{0}:{1}: {2}" -f $path, $e.Extent.StartLineNumber, $e.Message
        $failed = $true
    }
    if (-not $errors) { $parsed.Add($path) }
}
# Only files that parse: the analyzer would repeat the parser's errors.
$linted = [bool](Get-Module -ListAvailable PSScriptAnalyzer)
if ($linted) {
    foreach ($path in $parsed) {
        foreach ($finding in Invoke-ScriptAnalyzer -Path $path -Settings $env:PS_SETTINGS) {
            "{0}:{1}: {2} ({3})" -f $path, $finding.Line, $finding.Message, $finding.RuleName
            $failed = $true
        }
    }
}
if ($failed) { exit 1 }
if (-not $linted) { exit 4 }
POWERSHELL
readonly CHECKER
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

# main checks every FILE for ASCII, then parses and lints them all with one pwsh
# process.
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
    # Without pwsh, ASCII findings still fail; only syntax and linting are skipped.
    if ! command -v pwsh >/dev/null; then
        printf 'check-powershell.sh: pwsh is not installed, so syntax was not checked\n' >&2
        [[ $FINDINGS -eq 0 ]] || exit 1
        exit 3
    fi
    PS_FILES=$(printf '%s\n' "$@") PS_SETTINGS=$(native_path "$SETTINGS") \
        pwsh -NoLogo -NoProfile -NonInteractive -Command "$CHECKER" || status=$?
    if [[ $FINDINGS -ne 0 || ($status -ne 0 && $status -ne 4) ]]; then
        exit 1
    fi
    if [[ $status -eq 4 ]]; then
        printf 'check-powershell.sh: PSScriptAnalyzer is not installed, so the files were not linted;\n' >&2
        printf 'install it with: Install-PSResource PSScriptAnalyzer -Scope CurrentUser\n' >&2
        exit 4
    fi
}
# Execute the main function with all command-line arguments.
main "$@"
