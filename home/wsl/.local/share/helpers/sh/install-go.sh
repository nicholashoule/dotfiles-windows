#!/usr/bin/env bash
# Install a Go toolchain for the current user from go.dev.
# Author: Nicholas Houle (https://github.com/nicholashoule)
#
# Usage: install-go.sh [--latest | VERSION] [--dry-run]
#
# By default, installs the newest patch of the release one behind the latest:
# the older of the two releases Go supports (go1.26.10 while go1.27 is current).
# --latest installs the newest release, and VERSION (1.26.10 or go1.26.10)
# picks any release. Only stable releases count, ordered by version number
# whatever order the list is in, so release candidates and betas are skipped.
# The archive's SHA-256 comes from go.dev's release list and must match before
# anything is unpacked. The toolchain goes in ~/.local/share/go (or
# GO_INSTALL_DIR), replacing an older one only after the new one runs, and go
# and gofmt are linked into ~/.local/bin, which leads PATH, so this toolchain
# wins over a distribution's /usr/bin/go. Running it again moves to a newer
# patch once there is one; a toolchain already at that version, or at a newer
# one unless VERSION names another, is left alone, a directory there that is
# not a Go toolchain is never replaced, and a go or gofmt in ~/.local/bin that
# is not one of these links is left alone with a warning. Versions are read
# with GOTOOLCHAIN=local, so a go.mod where this runs cannot make go switch to,
# and download, another toolchain. golang.sh turns Go's telemetry off.
# GO_RELEASE_LIST names a local copy of the release list to read instead of
# go.dev's. --dry-run reports what it would install and changes nothing.
# Exit status: 0 on success, 1 on failure, 2 for usage errors.
# https://go.dev/doc/install
set -euo pipefail

# Global variables
readonly DL_URL='https://go.dev/dl'
readonly VERSION_RE='^(go)?[0-9]+\.[0-9]+(\.[0-9]+)?$'
readonly INSTALL_DIR=${GO_INSTALL_DIR:-$HOME/.local/share/go}
readonly BIN_DIR="$HOME/.local/bin"
TMP_DIR=''

# die prints an error message and exits with status 1.
die() {
    printf 'install-go.sh: %s\n' "$1" >&2
    exit 1
}

# usage prints how to run the helper.
usage() {
    printf 'Usage: install-go.sh [--latest | VERSION] [--dry-run]\n'
    printf 'Installs Go into %s, linked from %s: the newest patch of\n' "$INSTALL_DIR" "$BIN_DIR"
    printf 'the release one behind the latest, the latest with --latest, or VERSION (such as 1.26.10).\n'
}

# cleanup removes the temporary directory, and an old toolchain moved into it.
cleanup() {
    if [[ -n $TMP_DIR && -d $TMP_DIR ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}

# fetch URL FILE downloads URL to FILE over HTTPS only, failing on HTTP errors.
fetch() {
    curl --disable --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --retry 3 --output "$2" "$1"
}

# arch prints Go's name for this machine's CPU, or fails on one it has no Linux
# build for.
arch() {
    case $(uname -m) in
        x86_64 | amd64) printf 'amd64\n' ;;
        aarch64 | arm64) printf 'arm64\n' ;;
        armv6l | armv7l) printf 'armv6l\n' ;;
        i386 | i686) printf '386\n' ;;
        *) return 1 ;;
    esac
}

# pick_version LIST LATEST prints the newest patch of the release one behind
# the latest in go.dev's JSON LIST, or of the latest when LATEST is true, and
# fails when LIST names too few releases. Only stable versions such as go1.27.3
# count, and releases are ordered by number, not by their place in the list.
pick_version() {
    local wanted=1
    if [[ $2 == true ]]; then wanted=0; fi
    grep -o '"version": *"[^"]*"' "$1" | awk -v wanted="$wanted" '
        {
            v = $0
            sub(/^"version": *"/, "", v)
            sub(/"$/, "", v)
            if (v !~ /^go[0-9]+\.[0-9]+(\.[0-9]+)?$/) next
            n = split(substr(v, 3), part, ".")
            key = part[1] "." part[2]
            patch = (n > 2) ? part[3] + 0 : -1
            if (!(key in best) || patch > newest[key]) {
                best[key] = v
                newest[key] = patch
                major[key] = part[1] + 0
                minor[key] = part[2] + 0
            }
        }
        END {
            count = 0
            for (key in best) keys[++count] = key
            for (i = 2; i <= count; i++) {
                key = keys[i]
                for (j = i - 1; j > 0 && (major[keys[j]] < major[key] ||
                    (major[keys[j]] == major[key] && minor[keys[j]] < minor[key])); j--) {
                    keys[j + 1] = keys[j]
                }
                keys[j + 1] = key
            }
            if (count <= wanted) exit 1
            print best[keys[wanted + 1]]
        }'
}

# release_sum LIST FILE prints the SHA-256 that LIST gives FILE, or fails. Each
# file's entry ends at its closing brace, so the list reads the same whether it
# puts each field on its own line or not.
release_sum() {
    awk -v file="$2" '
        BEGIN { RS = "}" }
        {
            if (!match($0, /"filename"[ \t\r\n]*:[ \t\r\n]*"[^"]*"/)) next
            name = substr($0, RSTART, RLENGTH)
            sub(/^"filename"[ \t\r\n]*:[ \t\r\n]*"/, "", name)
            sub(/"$/, "", name)
            if (name != file || !match($0, /"sha256"[ \t\r\n]*:[ \t\r\n]*"[0-9a-f]+"/)) next
            sum = substr($0, RSTART, RLENGTH)
            sub(/^"sha256"[ \t\r\n]*:[ \t\r\n]*"/, "", sum)
            sub(/"$/, "", sum)
            if (length(sum) == 64) {
                print sum
                found = 1
                exit
            }
        }
        END { exit !found }' "$1"
}

# is_toolchain DIR succeeds when DIR holds a Go toolchain.
is_toolchain() {
    [[ -f $1/VERSION && -x $1/bin/go ]]
}

# go_version DIR prints the version the toolchain in DIR reports. GOTOOLCHAIN
# is local, so a go.mod in the current directory cannot make go switch to, and
# download, another toolchain.
go_version() {
    GOTOOLCHAIN=local "$1/bin/go" env GOVERSION 2>/dev/null
}

# is_newer A B succeeds when version A, such as go1.27.3, is newer than B.
is_newer() {
    awk -v a="${1#go}" -v b="${2#go}" 'BEGIN {
        split(a, x, ".")
        split(b, y, ".")
        for (i = 1; i <= 3; i++) {
            if (x[i] + 0 != y[i] + 0) exit !(x[i] + 0 > y[i] + 0)
        }
        exit 1
    }'
}

# link_tools links go and gofmt from BIN_DIR into INSTALL_DIR, replacing only
# links that already point into it or nowhere.
link_tools() {
    local tool link target
    mkdir -p -- "$BIN_DIR"
    for tool in go gofmt; do
        link="$BIN_DIR/$tool"
        if [[ -L $link ]]; then
            target=$(readlink -- "$link")
            if [[ $target != "$INSTALL_DIR/"* && -e $link ]]; then
                printf 'install-go.sh: left %s alone: it links to %s\n' "$link" "$target" >&2
                continue
            fi
        elif [[ -e $link ]]; then
            printf 'install-go.sh: left %s alone: it is not a link, and it shadows this toolchain\n' "$link" >&2
            continue
        fi
        ln -sfn -- "$INSTALL_DIR/bin/$tool" "$link"
    done
}

# main picks the version, downloads and checks the archive, unpacks it beside
# the install directory, swaps it in once it runs, and links the tools.
main() {
    local version='' latest=false dry_run=false named=false cpu list file expected actual tool installed=''
    local -a missing=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                usage
                return 0
                ;;
            --latest) latest=true ;;
            --dry-run) dry_run=true ;;
            *)
                if [[ $named == true || ! $1 =~ $VERSION_RE ]]; then
                    printf 'install-go.sh: %s is not --latest or a version such as 1.26.10\n' "$1" >&2
                    usage >&2
                    return 2
                fi
                version=go${1#go}
                named=true
                ;;
        esac
        shift
    done
    if [[ $latest == true && $named == true ]]; then
        printf 'install-go.sh: give --latest or a version, not both\n' >&2
        usage >&2
        return 2
    fi
    for tool in awk curl grep sha256sum tar uname; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "missing ${missing[*]}; install them with your package manager"
    cpu=$(arch) || die "Go has no Linux build for this CPU ($(uname -m))"
    if [[ -e $INSTALL_DIR ]] && ! is_toolchain "$INSTALL_DIR"; then
        die "$INSTALL_DIR is not a Go toolchain; move it or set GO_INSTALL_DIR"
    fi

    trap cleanup EXIT
    # Beside the install directory, so the final swap is a rename; a dry run
    # works in the temporary directory instead, and changes nothing here.
    if [[ $dry_run == true ]]; then
        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/install-go.XXXXXX")
    else
        mkdir -p -- "${INSTALL_DIR%/*}"
        TMP_DIR=$(mktemp -d "${INSTALL_DIR%/*}/.go-install.XXXXXX")
    fi
    list="$TMP_DIR/releases.json"
    if [[ -n ${GO_RELEASE_LIST-} ]]; then
        cp -- "$GO_RELEASE_LIST" "$list" || die "could not read $GO_RELEASE_LIST"
    elif [[ $named == true ]]; then
        fetch "$DL_URL/?mode=json&include=all" "$list" || die "could not download Go's release list"
    else
        fetch "$DL_URL/?mode=json" "$list" || die "could not download Go's release list"
    fi
    if [[ $named == false ]]; then
        version=$(pick_version "$list" "$latest") || die "Go's release list does not name two releases"
    fi
    if is_toolchain "$INSTALL_DIR"; then
        installed=$(go_version "$INSTALL_DIR") || installed=''
    fi
    if [[ $installed == "$version" ]]; then
        if [[ $dry_run == false ]]; then link_tools; fi
        printf '%s is already installed in %s.\n' "$version" "$INSTALL_DIR"
        return 0
    fi
    # A newer toolchain, as --latest installs, stays unless a version is named.
    if [[ $named == false && -n $installed ]] && is_newer "$installed" "$version"; then
        printf '%s in %s is newer than %s; left alone (name a version to change it).\n' \
            "$installed" "$INSTALL_DIR" "$version"
        return 0
    fi
    file="$version.linux-$cpu.tar.gz"
    expected=$(release_sum "$list" "$file") || die "Go's release list has no $file"
    if [[ $dry_run == true ]]; then
        printf 'Would install %s from %s/%s into %s.\n' "$version" "$DL_URL" "$file" "$INSTALL_DIR"
        return 0
    fi
    fetch "$DL_URL/$file" "$TMP_DIR/$file" || die "could not download $DL_URL/$file"
    actual=$(sha256sum <"$TMP_DIR/$file")
    [[ ${actual%% *} == "$expected" ]] || die "$file does not match its checksum; nothing was installed"
    tar -xzf "$TMP_DIR/$file" -C "$TMP_DIR"
    [[ $(go_version "$TMP_DIR/go") == "$version" ]] ||
        die "the unpacked go does not run as $version; nothing was installed"

    if [[ -e $INSTALL_DIR ]]; then
        mv -- "$INSTALL_DIR" "$TMP_DIR/old"
    fi
    if ! mv -- "$TMP_DIR/go" "$INSTALL_DIR"; then
        [[ ! -e $TMP_DIR/old ]] || mv -- "$TMP_DIR/old" "$INSTALL_DIR"
        die "could not move the new toolchain into $INSTALL_DIR"
    fi
    link_tools
    printf 'Installed %s in %s.\n' "$version" "$INSTALL_DIR"
}
# Execute the main function with all command-line arguments.
main "$@"
