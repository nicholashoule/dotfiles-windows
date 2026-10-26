# dotfiles-windows

PowerShell dotfiles for Windows, managed by the separate `homeskillet` CLI. This
repository holds the configuration, its setup steps and helpers, and checks; the
manager's Go source lives in the `homeskillet` repository.

> **Status:** homeskillet does not run on Windows yet; a Windows build only says
> so. Until it does, this repository is checked from Linux or macOS, and
> installing it on Windows is manual (see [Install](#install)). Inside WSL, use
> `dotfiles-linux` instead.

## What's Included

- **Shell:** a PowerShell 7 profile that sets environment defaults and PATH,
  then loads one snippet per tool from `~\.config\powershell\profile.d`:
  PSReadLine, aliases, functions, GnuPG, OpenSSH, and the prompt. Telemetry is
  off wherever a tool allows it, and every snippet stays silent when its tool is
  missing.
- **Prompt:** Oh My Posh themes, shared unchanged with `dotfiles-linux` and
  `dotfiles-macos`; `bubblesextra` by default.
- **Terminal:** a Windows Terminal fragment that starts PowerShell without its
  banner, in the Nerd Font the setup steps install.
- **Tools:** `tools.psd1`, the winget packages for this machine, installed and
  upgraded by a setup step.
- **Helpers and setup steps:** a commented `local.ps1` for this machine's
  overrides, Scoop's configuration, the winget packages, and the Meslo Nerd
  Font.
- **Safety:** a pre-commit hook, CI, and `.gitignore` rules that keep secrets
  and personal details out of this public repository, plus regression checks.

## Install

Once homeskillet runs on Windows, installing will match the other repositories:
from this clone, `homeskillet status --repo .`, `homeskillet link --repo .`, and
`homeskillet setup --repo .`. Until then, link or copy the files by hand: each
file under `home/` belongs at the same path under your profile directory
(`%USERPROFILE%`), and the setup steps in [dotfiles.json](dotfiles.json) run as
written, from the clone, in PowerShell 7.

If OneDrive backs up your Documents folder, Windows redirects it, and the
profile belongs under that folder instead: `$PROFILE.CurrentUserAllHosts` in
PowerShell shows the path PowerShell actually reads. Only `profile.ps1` lives in
Documents; everything else is under `~\.config` and `~\.local`, which OneDrive
leaves alone.

### The Host Profile

This repository owns `profile.ps1`, which PowerShell runs in every host before
the host's own profile, `$PROFILE` (`Microsoft.PowerShell_profile.ps1` in the
console). `$PROFILE` stays a local file that nothing here links: installers
write to it, and Coreutils for Windows updates its block there by replacing the
whole file, which would turn a link into a copy.

When moving from an existing profile, anything `$PROFILE` still does that this
repository now does runs twice. Remove those parts from `$PROFILE`, keep only
what installers manage there, such as the block between the
`DO NOT MODIFY -- coreutils` markers, and move your own settings to `local.ps1`.

## Setup Steps

[dotfiles.json](dotfiles.json) declares `"platforms": ["windows"]`, which applies
to every file and step, and the setup steps, in order:

| Step | Runs | Done when |
| --- | --- | --- |
| `powershell` | `winget install` for PowerShell 7 | `pwsh` is on PATH |
| `local` | `init-local.ps1` | `~\.config\powershell\profile.d\local.ps1` exists |
| `scoop-config` | `init-scoop-config.ps1` | `~\.config\scoop\config.json` exists |
| `winget-tools` | `install-tools.ps1` on the clone's `tools.psd1` | never; offered every run, and safe to repeat |
| `meslo-nerd-font` | `oh-my-posh font install Meslo` | MesloLGM Nerd Font is in your per-user fonts folder |

PowerShell 7 comes first because the helpers run in it, through
`pwsh -NoProfile -File`, which its default execution policy allows for local
scripts. winget adds programs to PATH for new processes only, so a first run
stops at the first step that needs a program installed earlier in the same run:
open a new terminal and run setup again. `homeskillet setup --dry-run` lists
every step and whether it is done.

The font step installs every Meslo face for the current user, without
elevation; running it on Windows 11 with Oh My Posh 31.9 wrote the file the
step checks and registered MesloLGM Nerd Font, the face the Windows Terminal
fragment selects.

## Helpers

The helpers in `~\.local\share\helpers\pwsh` are on PATH in every session, so
run them by name; setup steps call them by their path in the clone, since a new
machine has no profile yet. Each takes `-Help`, and returns 0 on success, 1 on
failure, and 2 for a usage error.

- **`init-local.ps1 [-DryRun] [-Force]`** creates the starter `local.ps1`, with
  commented examples of the overrides the snippets support.
- **`init-scoop-config.ps1 [-DryRun] [-Force]`** creates Scoop's
  `config.json`, in `%XDG_CONFIG_HOME%\scoop` when that is set, as Scoop reads
  it. It names the Scoop-Core fork's `master` as the repository and branch Scoop
  updates itself from, and extracts MSI packages with lessmsi. Scoop-Core, the
  fork itself, reads the branch and the lessmsi setting but not `scoop_repo`,
  which is upstream Scoop's.
- **`install-tools.ps1 [-Path FILE] [-NoUpgrade] [-DryRun]`** runs
  `winget install --id ID --exact --source winget` for every package
  `~\.config\winget\tools.psd1` (or `FILE`) lists, which installs what is
  missing and upgrades what is outdated. A package already up to date counts as
  done; every package is tried, and the helper fails if any did. `-DryRun`
  prints the commands and needs no winget.

The init helpers create files that tools or you write to, which a link would
carry into this repository, so they create each once and never link it. An
existing file is left alone; `-Force` renames it to `NAME.bak.DATE-TIME` first,
and `-DryRun` only reports what would happen. The home is `HOME` when it is set,
as homeskillet sets it for steps, and PowerShell's `$HOME` otherwise.

## Layout

```text
home/                                   linked into %USERPROFILE%, file by file
  Documents/PowerShell/profile.ps1      the profile: environment, PATH, snippets
  .config/powershell/profile.d/         one snippet per tool
  .config/winget/tools.psd1             the winget packages
  .config/oh-my-posh/themes/            Oh My Posh themes
  .local/share/helpers/pwsh/            helpers, which setup steps run
  AppData/Local/Microsoft/Windows Terminal/Fragments/
                                        the Windows Terminal fragment
dotfiles.json                           platforms and setup steps
scripts/                                repository tooling: checks and secret scan
tests/check.sh                          regression checks, run on Linux or macOS
```

homeskillet links every file under `home/`, skipping `.DS_Store`, `Thumbs.db`,
`desktop.ini`, and `.git`. Names must be ones Windows can create: no device
names such as `CON` or `nul.txt`, no names ending in a dot or space, none of
`<>:"|?*\`, and no two paths that differ only in case. homeskillet checks these
rules on any system.

## The Profile

[profile.ps1](home/Documents/PowerShell/profile.ps1) runs in every PowerShell 7
host, in this order:

1. **Environment:** `POWERSHELL_UPDATECHECK=Off`,
   `POWERSHELL_TELEMETRY_OPTOUT=1`, and `DO_NOT_TRACK=1`, each unless already
   set. pwsh reads its own two as it starts, so from the profile they reach only
   the processes a session starts; set them as user environment variables to
   cover every session.
2. **PATH:** the machine and user PATH entries the session lacks are appended,
   so a terminal opened before a tool was installed still finds it; inherited
   entries keep their order. The helpers directory is appended last.
3. **Snippets:** every `*.ps1` in `~\.config\powershell\profile.d`, in
   alphabetical order, including the unmanaged `local.ps1`.

### Snippets

| File | What it does |
| --- | --- |
| `00-psreadline.ps1` | In interactive consoles: Windows key bindings, history saved when the session exits, predictions from history and plugins as a list (inline in windows smaller than 50 columns by 5 rows), a menu of every completion on Tab, and syntax colors. It runs first because setting the edit mode resets key bindings that later files add. |
| `aliases.ps1` | `ls [-a] [PATH]`, `la`, `ll`, and `env` as on Unix (`-a`, `-la`, or `-al` includes hidden items; `-l` is accepted), and `gs` and `gitcm` for `git status` and `git commit` |
| `functions.ps1` | `hist PATTERN` searches this session's history by regular expression, `edit-last` opens the last command in VS Code, and `update-pwsh` (`Update-PowerShell`) upgrades PowerShell 7 with winget |
| `gnupg.ps1` | `new-gpg-key` and `gpg-key-1y`, `-5y`, `-10y` create an Ed25519 signing key for Git's author identity variables; `gpg-keyid` and `gpg-keyid-short` list secret key IDs; `gpg-pub` and `gpg-pub-copy` print or copy public keys; `git-sign-key` makes Git sign commits, globally or with `-Local`, and takes `gpg-keyid` output from the pipeline |
| `oh-my-posh.ps1` | In interactive sessions: the Oh My Posh prompt, when it is installed |
| `ssh.ps1` | `Add-SshKey [PATH]` adds keys to the OpenSSH agent unless it already holds one |
| `local.ps1` | Your machine's own settings, created by the `local` step and never linked |

When Coreutils for Windows' integration is in `$PROFILE`, lines typed at the
prompt run its `ls`, `la`, `env`, and other GNU commands instead; scripts still
get the functions above. `gp` and `gl` stay PowerShell's aliases for
`Get-ItemProperty` and `Get-Location`, which win over any function of that name.

`Add-SshKey` needs Windows' OpenSSH agent service, and Git for Windows needs
pointing at Windows' OpenSSH to use it. Run both once, the first from an
elevated shell:

```powershell
Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent
git config --global core.sshCommand C:/Windows/System32/OpenSSH/ssh.exe
```

## Windows Terminal

[powershell.json](<home/AppData/Local/Microsoft/Windows Terminal/Fragments/dotfiles-windows/powershell.json>)
is a [JSON fragment extension](https://learn.microsoft.com/windows/terminal/json-fragment-extensions).
It updates the PowerShell profile Windows Terminal generates for PowerShell 7,
named by its GUID, to run `pwsh.exe -NoLogo` in `MesloLGM Nerd Font`. It leaves
`settings.json`, which Windows Terminal rewrites itself, alone, and changes you
make in Windows Terminal's settings apply over it. Windows Terminal reads
fragments when it starts; remove the file to undo it. A fragment cannot choose
the default profile, so set that in Windows Terminal's startup settings. Not
yet verified on Windows.

## Customize

- **This machine:** put settings in `~\.config\powershell\profile.d\local.ps1`.
  It loads after `00-psreadline.ps1`, `aliases.ps1`, `functions.ps1`, and
  `gnupg.ps1`, so it can replace what they set, and before `oh-my-posh.ps1`,
  which reads its settings.
- **Prompt theme:** set `OHMYPOSH_THEME`, in `local.ps1` or your user
  environment variables, to the name of a theme in
  `~\.config\oh-my-posh\themes` (without `.omp.json`) or the path to any theme
  file.
- **Environment defaults:** set `POWERSHELL_UPDATECHECK`,
  `POWERSHELL_TELEMETRY_OPTOUT`, or `DO_NOT_TRACK` yourself, and the profile
  keeps your value.
- **Packages:** add an entry to `tools.psd1` with the package's ID from
  `winget show`, which `--exact` matches case and all. Its header shows the PATH
  edits that Make and MSYS2's gcc need, since neither puts its command on PATH.

## Troubleshooting

- **The prompt shows boxes or question marks:** the terminal font is not a Nerd
  Font. Run the `meslo-nerd-font` step, then select `MesloLGM Nerd Font` in the
  terminal's settings; the Windows Terminal fragment does this for its
  PowerShell profile.
- **No prompt theme:** check `oh-my-posh version`, and that `OHMYPOSH_THEME`
  names a theme that exists in `~\.config\oh-my-posh\themes`. The prompt loads
  only in interactive sessions.
- **Something runs twice:** `$PROFILE` still holds an old copy of the profile;
  see [The Host Profile](#the-host-profile).
- **A change to the profile does not show:** run `. $PROFILE.CurrentUserAllHosts`
  at the prompt, or open a new terminal. A function cannot reload it, because
  dot-sourcing inside a function keeps the definitions in that function's scope.
- **A new session starts slowly:** time the profile at the prompt with
  `Measure-Command { . $PROFILE.CurrentUserAllHosts }`, then move snippets out
  of `profile.d` one at a time to find the slow one. The prompt runs
  `oh-my-posh init` once per interactive session.
- **A program a step installed is not found:** winget adds programs to PATH for
  new processes only. Open a new terminal; the profile also picks up PATH
  entries saved since the terminal started.
- **`Add-SshKey` says the agent is not running:** set the service to start at
  boot, as shown under [Snippets](#snippets).
- **A commit is blocked:** the hook prints each problem as `file:line: reason`,
  without the secret. Remove the secret, or for a reviewed false positive add a
  `secret-scan: allow` comment or a `!path` exception to `.gitignore`.
  `git commit --no-verify` skips the hook, but CI still runs the scan.

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

homeskillet does not run on Windows yet, so the manager checks run on Linux or
macOS; the rest also run in Git Bash on Windows:

```sh
bash tests/check.sh                          # PowerShell, profile, helpers, and JSON
bash tests/check.sh /path/to/homeskillet     # also link, status, unlink, and setup --dry-run
shellcheck scripts/*.sh tests/check.sh .githooks/pre-commit
bash scripts/check-secrets.sh --all
```

When `pwsh` is installed, `tests/check.sh` parses every PowerShell file with
PowerShell's own parser. It loads the profile and its snippets in a new session
whose home holds a copy of `home/` and whose PATH is empty, before and after
`init-local.ps1` adds `local.ps1`, requiring them to print nothing, leave no
variables behind, and define their commands. It runs each init helper in a
temporary home, checks that `install-tools.ps1 -DryRun` installs every package
`tools.psd1` lists, and parses every JSON file. It requires each PowerShell file
to be ASCII either way, since Windows PowerShell 5.1 misreads anything else.
Given a homeskillet binary, it confirms the manifest targets Windows only, then
acts for Windows with `--platform windows`: it links every file under `home/`
into a temporary home, checks and unlinks them, and lists the setup steps
without running any. GitHub Actions runs the checks on Ubuntu on every push and
pull request.

[.pre-commit-config.yaml](.pre-commit-config.yaml) adds optional checks for
[pre-commit](https://pre-commit.com), such as YAML and JSON syntax, whitespace,
executable bits, and private keys, plus ShellCheck on the Bash tooling. They
complement `.githooks/pre-commit` and do not replace it. Because
`core.hooksPath` is set, `pre-commit install` refuses to install, so run them on
demand; the ShellCheck hook uses ShellCheck's Docker image, so without Docker,
skip it with `SKIP=shellcheck`:

```sh
pre-commit run --all-files  # every check on every tracked file
pre-commit autoupdate       # refresh the pinned hook versions
```

## Contributing

[AGENTS.md](AGENTS.md) lists the conventions for changes and the checks to run
before finishing.

## License and Credits

Released under the [MIT License](LICENSE). The prompt themes are unmodified
themes from [Oh My Posh](https://github.com/JanDeDobbeleer/oh-my-posh), also
released under the MIT License.
