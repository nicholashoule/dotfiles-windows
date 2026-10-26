# Contributor Guide

Conventions for changing this repository, for people and coding agents alike.
[README.md](README.md) describes what the configuration does; this file says how
to change it without breaking its guarantees.

## Scope

- PowerShell 7 on Windows only. Bash on Linux lives in `dotfiles-linux`, zsh on
  macOS in `dotfiles-macos`, and the manager in `homeskillet`. Inside WSL, use
  `dotfiles-linux`.
- homeskillet does not run on Windows yet. Until it does, this repository is
  checked from Linux or macOS with `--platform windows`, and nothing here may
  depend on homeskillet running natively. homeskillet's `docs/windows.md` lists
  what native support still needs.
- Everything meant for the user's profile directory (`%USERPROFILE%`) lives under
  `home/`, at the path it takes there, and homeskillet links it file by file;
  that includes the package list, `home/.config/winget/tools.psd1`.
  `dotfiles.json` declares `"platforms": ["windows"]` once and the setup steps;
  it never lists files. Repository tooling (`scripts/`, `tests/`, `.githooks/`,
  CI) stays outside `home/` and runs with Bash on Linux and macOS. Helper
  commands are called helpers, not scripts, and live in
  `home/.local/share/helpers/pwsh/`.
- Only `profile.ps1` lives in Documents, which OneDrive may redirect; put
  everything else under `home/.config` or `home/.local`.
- Never put a file under `home/` that tools write into, such as Scoop's
  `config.json` or `$PROFILE`: writes follow the link into this repository, and
  a tool that replaces the file turns the link into a copy. Create such a file
  once with a setup step and a helper that leaves an existing file alone unless
  asked (`-Force`), and then renames it to a backup first, as `init-local.ps1`
  and `init-scoop-config.ps1` do.
- The repository is public. Commit nothing machine-specific: no user names,
  absolute paths, email addresses, hostnames, tokens, or values copied from
  another project. Use placeholders such as `/path/to/homeskillet` and `$HOME`.
  Turn on the pre-commit hook in every clone (`git config core.hooksPath
  .githooks`); it and CI enforce part of this rule.

## Profile Snippets (`home/.config/powershell/profile.d/*.ps1`)

- One tool per file, starting with a title line and a link to the tool's
  documentation. `profile.ps1` dot-sources them in alphabetical order;
  `00-psreadline.ps1` runs first because setting PSReadLine's edit mode resets
  every key binding, including ones later files add.
- Defaults let values set first win (`if (-not $env:NAME)`); always-on ones,
  such as telemetry opt-outs, are explained.
- Guard every tool with `Get-Command ... -ErrorAction SilentlyContinue`, so the
  profile stays silent when a tool is missing. Load what only an interactive
  console needs, such as PSReadLine settings and the prompt, only when
  `Get-Module PSReadLine` shows the console loaded it, and run generated code
  only when its generator succeeded (`$LASTEXITCODE -eq 0`).
- Remove the helper variables a snippet defines; the checks fail on any left
  behind.
- `aliases.ps1` holds short Unix-style and Git commands and `functions.ps1`
  general-purpose functions; commands for one tool live in that tool's file.

## PowerShell Files

- Keep every `.ps1` and `.psd1` ASCII: Windows PowerShell 5.1 reads a script
  without a byte-order mark in the system's ANSI code page.
  `scripts/check-powershell.sh` enforces it.
- Start each file with a comment saying what it is for and linking the tool's
  documentation. Comments explain why, not only what.
- Names under `home/` must be ones Windows can create; homeskillet refuses device
  names such as `CON`, names ending in a dot or space, and two paths that differ
  only in case.

## Helpers (`home/.local/share/helpers/pwsh/*.ps1`)

- Start with a comment saying what the helper does, an `# Author:` line under
  it, its usage, and its exit status; every function has a comment above it
  saying what it does.
- They run on PowerShell 7. Setup steps install it first and call helpers with
  `pwsh -NoLogo -NoProfile -File home/.local/share/helpers/pwsh/NAME.ps1`, by
  their repository path, because the helpers directory is not on PATH until a
  new session starts. Never weaken the execution policy to run them; pwsh's
  default runs local scripts.
- Take `-Help`, and `-DryRun` and `-Force` where they apply. Return 0 on
  success, 1 on failure with the error on stderr, and 2 for an unexpected
  argument.
- The home is `HOME` when it is set, as homeskillet sets it for steps, and
  PowerShell's `$HOME` otherwise. Installers are idempotent and never edit
  startup files.

## Repository Scripts

- Scripts in `scripts/` and `tests/` start with `#!/usr/bin/env bash` and
  `set -euo pipefail`, declare global variables at the top, run from a `main`
  function, document every function, and clean temporary directories with a
  trap. They must pass ShellCheck without suppressions.

## Documentation

- The README describes every user-visible behavior: what each file under `home/`
  does, its defaults, how to override them (Customize), and how to recover
  (Troubleshooting). Update it in the same change as the behavior.
- Be robust but concise, and verify every claim against the code or by running
  it. Mark what cannot be verified until homeskillet runs on Windows.
- Never list or count files, steps, or entries in prose; describe sets by rule,
  such as "every file under `home/`", so docs cannot go stale when files are
  added. Tables that describe each snippet or step are the exception, and change
  with them.
- Keep the sister repositories aligned: the Oh My Posh themes, `CODEOWNERS`, and
  Dependabot stay identical to theirs, `scripts/check-secrets.sh` to
  dotfiles-linux's, and the theme selection (`OHMYPOSH_THEME`) works the same.
  The structure mirrors dotfiles-macos (snippets, helpers, a local override
  file, a package list) except where PowerShell or Windows requires a
  difference.

## Every Change

- Add or update a check in `tests/check.sh` for every behavior change, and
  README coverage for every new file under `home/`.
- Before finishing, run:

```sh
bash tests/check.sh /path/to/homeskillet
shellcheck scripts/*.sh tests/check.sh .githooks/pre-commit
bash scripts/check-secrets.sh --all
```
