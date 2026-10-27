#!/usr/bin/env bash
# Install the Debian or Ubuntu packages a list names that are missing, with apt.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-apt-packages.sh [--dry-run] LIST
#
# The wsl-apt-packages setup step runs it inside WSL with
# ~/.config/apt/packages, which homeskillet links from home/wsl/. LIST names
# one package per line; blank lines and text after # are ignored. A package dpkg reports installed is left alone, so nothing runs
# when all of them are; otherwise apt-get refreshes its index and installs the
# missing ones, which needs root, through sudo. sudo asks for your password
# only at a terminal: run unattended, without sudo's password cached, the
# helper says what it needs and fails rather than wait. It prints one line for
# what was installed already and one for what it installed. --dry-run reports
# what it would install and changes nothing.
# Exit status: 0 when every package is installed, 1 on failure, 2 for usage errors.
# Runs on Debian and Ubuntu, with Bash 3.2 or later.
# https://manpages.debian.org/apt-get
set -euo pipefail

# Global variables
# Debian's rule for package names: lowercase letters, digits, and + - . after
# the first character.
readonly NAME_RE='^[a-z0-9][a-z0-9+.-]+$'

# die prints an error message and exits with status 1.
die() {
    printf 'install-apt-packages.sh: %s\n' "$1" >&2
    exit 1
}

# usage prints how to run the helper.
usage() {
    printf 'Usage: install-apt-packages.sh [--dry-run] LIST\n'
    printf 'Installs the packages LIST names, one per line, that are missing, with apt and sudo.\n'
}

# read_list LIST prints each package LIST names, and fails, naming it, on a
# line that is not a package name.
read_list() {
    local line name
    while IFS= read -r line || [[ -n $line ]]; do
        name=${line%%#*}
        name=${name//[[:space:]]/}
        [[ -n $name ]] || continue
        if [[ ! $name =~ $NAME_RE ]]; then
            printf 'install-apt-packages.sh: %s names %s, which is not a package name\n' "$1" "$name" >&2
            return 1
        fi
        printf '%s\n' "$name"
    done <"$1"
}

# is_installed PACKAGE succeeds when dpkg reports PACKAGE installed.
is_installed() {
    [[ $(dpkg-query -W -f="\${Status}" "$1" 2>/dev/null) == 'install ok installed' ]]
}

# as_root COMMAND... runs COMMAND as root: directly when this runs as root, and
# otherwise through sudo, which may ask for a password only at a terminal.
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# can_sudo succeeds when sudo runs without a password, or can ask for one at a
# terminal and gets it.
can_sudo() {
    [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null || { [[ -t 0 ]] && sudo -v; }
}

# main reads the list, installs what is missing, and checks it installed.
main() {
    local dry_run=false list='' names package
    local -a present=() missing=() failed=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                usage
                return 0
                ;;
            --dry-run) dry_run=true ;;
            -*)
                printf 'install-apt-packages.sh: unexpected option %s\n' "$1" >&2
                usage >&2
                return 2
                ;;
            *)
                if [[ -n $list ]]; then
                    printf 'install-apt-packages.sh: one LIST only, not %s too\n' "$1" >&2
                    usage >&2
                    return 2
                fi
                list=$1
                ;;
        esac
        shift
    done
    if [[ -z $list ]]; then
        usage >&2
        return 2
    fi
    [[ -f $list ]] || die "$list is missing"
    if ! command -v dpkg-query >/dev/null || ! command -v apt-get >/dev/null; then
        die "apt is not available; this helper is for Debian and Ubuntu"
    fi
    names=$(read_list "$list") || exit 1
    while IFS= read -r package; do
        if [[ -z $package ]]; then
            continue
        elif is_installed "$package"; then
            present+=("$package")
        else
            missing+=("$package")
        fi
    done <<<"$names"
    if [[ ${#present[@]} -gt 0 ]]; then
        printf 'Already installed with apt: %s\n' "${present[*]}"
    fi
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi
    if [[ $dry_run == true ]]; then
        printf 'Would install with apt: %s\n' "${missing[*]}"
        return 0
    fi
    can_sudo || die "installing ${missing[*]} needs sudo, which can ask for your password only at a terminal; run it at one (homeskillet setup without --yes)"
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq || die "apt-get update failed"
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" ||
        die "apt-get install ${missing[*]} failed"
    for package in "${missing[@]}"; do
        is_installed "$package" || failed+=("$package")
    done
    [[ ${#failed[@]} -eq 0 ]] || die "apt-get finished, but ${failed[*]} is not installed"
    printf 'Installed with apt: %s\n' "${missing[*]}"
}
# Execute the main function with all command-line arguments.
main "$@"
