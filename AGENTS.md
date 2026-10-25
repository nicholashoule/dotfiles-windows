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
  `home/`, which homeskillet links file by file. `dotfiles.json` declares
  `"platforms": ["windows"]` once and the setup steps; it never lists files.
  Repository tooling (`scripts/`, `tests/`, `.githooks/`, CI) stays outside
  `home/` and runs with Bash on Linux and macOS.
- The repository is public. Commit nothing machine-specific: no user names,
  absolute paths, email addresses, hostnames, tokens, or values copied from
  another project. Use placeholders such as `/path/to/homeskillet` and `$HOME`.
  Turn on the pre-commit hook in every clone (`git config core.hooksPath
  .githooks`); it and CI enforce part of this rule.

## PowerShell Files

- Keep every `.ps1` ASCII: Windows PowerShell 5.1 reads a script without a
  byte-order mark in the system's ANSI code page. `scripts/check-powershell.sh`
  enforces it.
- Start each file with a comment saying what it is for and linking the tool's
  documentation. Comments explain why, not only what.
- Guard every tool with `Get-Command ... -ErrorAction SilentlyContinue`, so the
  profile stays silent when a tool is missing, and run generated code only when
  its generator succeeded (`$LASTEXITCODE -eq 0`).
- Remove helper variables the profile defines, and let environment variables the
  user set first win over defaults.
- Names under `home/` must be ones Windows can create; homeskillet refuses device
  names such as `CON`, names ending in a dot or space, and two paths that differ
  only in case.

## Repository Scripts

- Scripts in `scripts/` and `tests/` start with `#!/usr/bin/env bash` and
  `set -euo pipefail`, declare global variables at the top, run from a `main`
  function, document every function, and clean temporary directories with a
  trap. They must pass ShellCheck without suppressions.

## Documentation

- The README describes every user-visible behavior: what each file under `home/`
  does, its defaults, how to override them, and how to recover. Update it in the
  same change as the behavior.
- Be robust but concise, and verify every claim against the code or by running
  it. Mark what cannot be verified until homeskillet runs on Windows.
- Never list or count files, steps, or entries; describe sets by rule, such as
  "every file under `home/`", so docs cannot go stale when files are added.
- Keep the sister repositories aligned: the Oh My Posh themes, `CODEOWNERS`, and
  Dependabot stay identical to theirs, `scripts/check-secrets.sh` to
  dotfiles-linux's, and the theme selection (`OHMYPOSH_THEME`) works the same.

## Every Change

- Add or update a check in `tests/check.sh` for every behavior change, and README
  coverage for every new file under `home/`.
- Before finishing, run:

```sh
bash tests/check.sh /path/to/homeskillet
shellcheck scripts/*.sh tests/check.sh .githooks/pre-commit
bash scripts/check-secrets.sh --all
```
