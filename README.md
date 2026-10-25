# dotfiles-windows

PowerShell dotfiles for Windows, managed by the separate `homeskillet` CLI. This
repository holds the configuration, its setup steps, and checks; the manager's
Go source lives in the `homeskillet` repository.

> **Status:** homeskillet does not run on Windows yet; a Windows build only says
> so. Until it does, this repository is a starting point that is checked from
> Linux or macOS, and installing it on Windows is manual (see
> [Install](#install)). Inside WSL, use `dotfiles-linux` instead.

## What's Included

- **Shell:** a PowerShell 7 profile that starts the Oh My Posh prompt when Oh My
  Posh is installed, and stays silent when it is not.
- **Prompt:** Oh My Posh themes, shared unchanged with `dotfiles-linux` and
  `dotfiles-macos`; `bubblesextra` by default.
- **Setup steps:** Oh My Posh through winget, and the MesloLGL Nerd Font for
  the prompt's glyphs.

## Install

Once homeskillet runs on Windows, installing will match the other repositories:
from this clone, `homeskillet status --repo .`, `homeskillet link --repo .`, and
`homeskillet setup --repo .`. Until then, link or copy the files by hand: each
file under `home/` belongs at the same path under your profile directory
(`%USERPROFILE%`), and the setup steps in [dotfiles.json](dotfiles.json) run as
written in PowerShell.

If your Documents folder is redirected, as OneDrive does by default, the
profile belongs under that folder instead: `$PROFILE` in PowerShell shows the
path PowerShell actually reads.

## Setup Steps

[dotfiles.json](dotfiles.json) declares `"platforms": ["windows"]`, which applies
to every file and step, and the setup steps:

| Step | Runs | Done when |
| --- | --- | --- |
| `oh-my-posh` | `winget install` for Oh My Posh | `oh-my-posh` is on PATH |
| `meslo-nerd-font` | `oh-my-posh font install Meslo` | the font is in your per-user fonts folder |

winget adds Oh My Posh to PATH for new processes only, so the font step needs a
new terminal after the first one. The font step's file name is not yet verified
on Windows; check it once homeskillet runs there.

## Layout

```text
home/                                   linked into %USERPROFILE%, file by file
  Documents/PowerShell/                 the PowerShell 7 profile
  .config/oh-my-posh/themes/            Oh My Posh themes
dotfiles.json                           platforms and setup steps
scripts/                                repository tooling: checks and secret scan
tests/check.sh                          regression checks, run on Linux or macOS
```

homeskillet links every file under `home/`, skipping `.DS_Store`, `Thumbs.db`,
`desktop.ini`, and `.git`. Names must be ones Windows can create: no device
names such as `CON` or `nul.txt`, no names ending in a dot or space, none of
`<>:"|?*\`, and no two paths that differ only in case. homeskillet checks these
rules on any system.

## Customize

Set `OHMYPOSH_THEME` before the profile runs, for example in your user
environment variables, to the name of a theme in `~\.config\oh-my-posh\themes`
(without `.omp.json`) or the path to any theme file.

## Secrets

This repository is public. [.gitignore](.gitignore) ignores credential, key,
history, and environment files anywhere, including under `home/`. The pre-commit
hook, [.githooks/pre-commit](.githooks/pre-commit), runs
[scripts/check-secrets.sh](scripts/check-secrets.sh) on what each commit adds,
and CI runs it on every tracked file. Turn the hook on once per clone:

```sh
git config core.hooksPath .githooks
```

## Checks

homeskillet does not run on Windows yet, so the checks run on Linux or macOS:

```sh
bash tests/check.sh                          # PowerShell syntax and ASCII
bash tests/check.sh /path/to/homeskillet     # also link, status, unlink, and setup --dry-run
shellcheck scripts/*.sh tests/check.sh .githooks/pre-commit
bash scripts/check-secrets.sh --all
```

`tests/check.sh` parses every PowerShell file with PowerShell's own parser when
`pwsh` is installed, and requires each to be ASCII, since Windows PowerShell 5.1
misreads anything else. Given a homeskillet binary, it confirms the manifest
targets Windows only, then acts for Windows with `--platform windows`: it links
every file under `home/` into a temporary home, checks and unlinks them, and
lists the setup steps without running any. GitHub Actions runs the checks on
Ubuntu on every push and pull request.

## Contributing

[AGENTS.md](AGENTS.md) lists the conventions for changes and the checks to run
before finishing.

## License and Credits

Released under the [MIT License](LICENSE). The prompt themes are unmodified
themes from [Oh My Posh](https://github.com/JanDeDobbeleer/oh-my-posh), also
released under the MIT License.
