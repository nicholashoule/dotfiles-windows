# Contributor Guide

Conventions for changing this repository, for people and coding agents alike.
[README.md](README.md) describes what the configuration does; this file says how
to change it without breaking its guarantees.

## Scope

- PowerShell 7 on Windows, and bash in its WSL distribution. Bash on Linux
  lives in `dotfiles-linux`, zsh on macOS in `dotfiles-macos`, and the manager
  in `homeskillet`. `home/wsl/` is the distribution's home, a fixed name
  homeskillet knows: it never links it on Windows, and `homeskillet wsl`
  links it inside the distribution, from a copy there, never across the
  boundary. Nothing here calls `wsl.exe` to manage WSL; that is homeskillet's
  job. Only what works in WSL goes in `home/wsl/`: nothing for a Linux desktop,
  such as GNOME settings, fonts, or a Linux VS Code.
- homeskillet is the mechanism and this repository the policy. Logic every
  dotfiles repository would need belongs in homeskillet: finding homes and
  Documents, linking, deciding whether a step is done, running steps, and
  validating a repository. What names a specific file, tool, version, or
  setting belongs here: the manifests, `tools.psd1`, and helpers that install
  one tool or change one Windows setting. When a helper here would need to
  find an environment or link files itself, ask for it in homeskillet instead.
- homeskillet's native Windows support is not in a release yet, so nothing here
  may depend on homeskillet running natively: every setup step's work also runs
  by hand from the clone, and the checks run from Linux or macOS with
  `--platform windows`. homeskillet's `docs/windows.md` describes its Windows
  behavior.
- Everything meant for the user's profile directory (`%USERPROFILE%`) lives under
  `home/`, outside `home/wsl/`, at the path it takes there, and homeskillet
  links it file by file; that includes the package list,
  `home/.config/winget/tools.psd1`. homeskillet merges two manifests, which
  never list files, and each declares `"platforms": ["windows"]`:
  `bootstrap.json` holds the setup steps that install tools, and
  `dotfiles.json` the ones that create files, such as the `init-*.ps1` steps. A
  step name appears in only one of them. Every step says how setup knows it is
  done, so none is offered every run: `creates` or `provides`, or, for a step
  that installs from a list, `inputs` naming the list and its helper, which
  homeskillet fingerprints. WSL's steps sit beside the others,
  named `wsl-` and with `"platforms": ["linux"]` of their own, and use files
  under `home/wsl/` alone. Repository tooling (`scripts/`, `tests/`, `.githooks/`,
  CI) stays outside `home/` and runs with Bash on Linux and macOS. Helper
  commands are called helpers, not scripts, and live in
  `home/.local/share/helpers/pwsh/`.
- Nothing goes under `home/Documents`. PowerShell reads the profile only from
  Documents, which OneDrive may redirect, so a path there relative to the home
  can be wrong. The profile lives in `home/.config/powershell/profile.ps1`, and
  the `profile` setup step (`init-profile.ps1`) writes a stub that loads it at
  `$PROFILE.CurrentUserAllHosts`, wherever Documents is. Put everything under
  `home/.config` or `home/.local`. Helpers and checks that touch the stub take
  its path with `-Path`, so tests never write the real profile.
- Never put a file under `home/` that tools write into, such as Scoop's
  `config.json` or `$PROFILE`: writes follow the link into this repository, and
  a tool that replaces the file turns the link into a copy. Create such a file
  once with a setup step and a helper that leaves an existing file alone unless
  asked (`-Force`), and then renames it to a backup first, as the `init-*.ps1`
  helpers do.
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
- Guard every tool with `Get-Command ... -ErrorAction Ignore`, so the profile
  stays silent when a tool is missing. Suppress every expected failure with
  `Ignore`, not `SilentlyContinue`, which hides the error but still records it
  in `$Error`; the checks load the profile twice, as `. $PROFILE` does in an
  open session, and fail on any error it records. Load what only an interactive
  console needs, such as PSReadLine settings and the prompt, only when
  `Get-Module PSReadLine` shows the console loaded it, and run generated code
  only when its generator succeeded (`$LASTEXITCODE -eq 0`).
- Remove the helper variables a snippet defines; the checks fail on any left
  behind. A snippet that runs a tool must survive the tool failing to start,
  and checks that load the profile point `APPDATA` and `LOCALAPPDATA` into the
  test home, so a tool the profile runs never changes the real settings.
- `aliases.ps1` holds short Unix-style and Git commands and `functions.ps1`
  general-purpose functions; commands for one tool live in that tool's file.
  Upgrade commands call `Update-WingetPackage` with the ID `tools.psd1` lists.
- Never put a credential in a snippet or `local.ps1`, and never assign one there,
  even empty, since an empty value deletes the variable. A command that saves one
  stores it where Windows or the tool keeps it, as `Set-GitHubToken` does.

## PowerShell Files

- Keep every `.ps1` and `.psd1` ASCII: Windows PowerShell 5.1 reads a script
  without a byte-order mark in the system's ANSI code page.
  `scripts/check-powershell.sh` enforces it.
- Every PowerShell file passes PSScriptAnalyzer with
  `scripts/PSScriptAnalyzerSettings.psd1`, which `scripts/check-powershell.sh`
  applies when the module is installed (`Install-PSResource PSScriptAnalyzer
  -Scope CurrentUser`) and CI always. Fix a finding rather than hide it. When
  the code is right, suppress the rule in place with a `SuppressMessageAttribute`
  whose `Justification` says why; exclude a rule in the settings only when it
  fits nothing in the repository, with a comment saying why.
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
  startup files or the saved PATH; a snippet puts what they install on PATH.
- Check the current state before changing anything, and leave alone what is
  already done; a setup step never upgrades what may be in use. Report briefly,
  a line per package or change, and show a tool's own output only when it
  failed.
- A helper that changes a Windows setting needing administrator rights, such as
  `enable-developer-mode.ps1` or `enable-wsl.ps1`, runs as the user, checks
  first, and elevates only the change, through a copy started with
  `Start-Process -Verb RunAs`: homeskillet refuses to run as administrator.
  Such changes stay out of the setup steps when they must happen before
  homeskillet runs or can need a restart.
- Installers that download verify what they run before running it: a checksum
  from the publisher's release list, or a valid Authenticode signature from
  the publisher. They check their arguments before any download, so the checks
  test them offline; checks never download.

## WSL Home (`home/wsl/`)

- Every file here is a byte-for-byte copy of the same path under
  `dotfiles-linux`'s `home/`, except those `WSL_OWN` in `tests/check.sh` lists:
  `.bash_profile`, without that repository's desktop terminal settings, the apt
  package list, and `install-apt-packages.sh`. Improve a copy in
  `dotfiles-linux` first, in its Linux terms, then copy it here; the checks
  compare every copy when that repository is cloned beside this one, and the
  themes with home/'s always. Keep `dotfiles-linux` and `dotfiles-macos` free
  of anything about Windows or WSL.
- The helpers in `home/wsl/.local/share/helpers/sh` run inside the
  distribution, as the user, from WSL's setup steps; they follow the
  PowerShell helpers' rules where those apply (header, `--help`, `--dry-run`,
  exit statuses, idempotent, verified downloads), the repository scripts' Bash
  style, run on Bash 3.2, and pass ShellCheck, which CI runs on every bash file
  here. They decide what is installed inside the distribution, never from
  Windows, and use `sudo` only when it can run without a password or can ask at
  a terminal, and otherwise say what is needed and fail rather than wait.
- Every file has LF line endings, which `.gitattributes` keeps: homeskillet
  copies the clone's bytes into WSL, where bash rejects a carriage return.

## Repository Scripts

- Scripts in `scripts/` and `tests/` start with `#!/usr/bin/env bash` and
  `set -euo pipefail`, declare global variables at the top, run from a `main`
  function, document every function, and clean temporary directories with a
  trap. They must pass ShellCheck without suppressions; CI runs it on Linux, and
  nothing runs it on Windows, where commits are made.

## Documentation

- The README describes every user-visible behavior: what each file under `home/`
  does, its defaults, how to override them (Customize), and how to recover
  (Troubleshooting). Update it in the same change as the behavior.
- Be robust but concise, and verify every claim against the code or by running
  it. Mark what has not been verified on Windows.
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
- A theme added to `home/.config/oh-my-posh/themes/` starts its top line with
  the date and time on a 12-hour clock (`time_format`
  `Mon Jan _2 03:04:05 PM MST 2006`), as every theme except the upstream
  `jandedobbeleer` does; the checks render each theme and enforce it when
  oh-my-posh is installed. Change a theme in all three repositories at once.
- Before finishing, run:

```sh
bash tests/check.sh /path/to/homeskillet
bash scripts/check-secrets.sh --all
```
