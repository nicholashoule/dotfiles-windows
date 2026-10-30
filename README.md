# dotfiles-windows

PowerShell dotfiles for Windows, and bash dotfiles for its WSL distribution,
managed by the separate `homeskillet` CLI. This repository holds the
configuration, its setup steps and helpers, and checks; the manager's Go source
lives in the `homeskillet` repository.

> **Requires** [homeskillet](https://github.com/nicholashoule/homeskillet)
> 0.2.0 or later; 0.3.0 adds `homeskillet update`, and 0.4.0
> `homeskillet prepare`, which the install steps run. Each passes the checks
> on Windows 11.

## What's Included

- **Shell:** a PowerShell 7 profile in `~\.config\powershell`, outside the
  Documents folder OneDrive may redirect, loaded by a one-line stub where
  PowerShell looks. It sets environment defaults and PATH, then loads one
  snippet per tool from `~\.config\powershell\profile.d`:
  PSReadLine, aliases, functions, .NET, GitHub, Go, GnuPG, homeskillet,
  OpenSSH, and the prompt.
  Telemetry is off wherever a tool allows it, and every snippet stays silent
  when its tool is missing.
- **Prompt:** Oh My Posh themes, identical to those in `dotfiles-linux` and
  `dotfiles-macos`, with the date and time at the left; `bubblesextra` by
  default.
- **Terminal:** a Windows Terminal fragment that starts PowerShell without its
  banner, in the Nerd Font the setup steps install.
- **Tools:** `tools.psd1`, the winget packages for this machine, installed by
  a setup step and upgraded by `install-tools.ps1`.
- **WSL:** `home/wsl/`, the home of the WSL distribution: bash with one snippet
  per tool, the same Oh My Posh prompt, Git defaults, tmux, and vim, taken from
  `dotfiles-linux` where they work in WSL, and setup steps that install apt
  packages such as `make`, Oh My Posh, a .NET SDK, and Go there (see
  [WSL](#wsl)).
- **Helpers and setup steps:** the profile stub, a commented `local.ps1` for
  this machine's overrides, Scoop's configuration, the winget packages, the
  Meslo Nerd Font, and per-user .NET SDK and Go toolchains; and for a new
  machine, Developer Mode and WSL.
- **Safety:** a pre-commit hook, CI, and `.gitignore` rules that keep secrets
  and personal details out of this public repository, plus regression checks.

## Install

On a new machine, in Windows PowerShell, in this order:

1. **homeskillet**, which also gets the machine ready. From a folder of your
   own, such as Downloads, paste the commands under
   [Installing](https://github.com/nicholashoule/homeskillet/blob/main/docs/windows.md#installing)
   in homeskillet's Windows guide. They download its latest release and, only
   if it matches the release's `SHA256SUMS`, run its `prepare`, then its
   `install`. `prepare` offers what is missing, each fix shown and run only
   once you answer `y`: Settings, for you to turn on Developer Mode, which
   links need; winget, when it is missing; and Git and PowerShell 7, through
   winget. `install` runs once `prepare` reports `ready`. On Windows 11 with
   all of these in place, the commands reported `ready` and changed nothing;
   the offers on a new machine are not yet verified here.

   Then delete the two downloaded files and open a new terminal. If
   homeskillet says `~\.local\bin` is not on your Path, add it to your user
   Path first. Later, `homeskillet update` installs new releases.

2. **The clone**. Use your fork's URL if you have one (see
   [Customize](#customize)), and keep the clone under your profile directory
   and outside OneDrive, since the links point into it. The last line turns on
   the pre-commit hook, which keeps secrets out of your commits:

   ```powershell
   git clone https://github.com/OWNER/dotfiles-windows.git $HOME\projects\dotfiles-windows
   Set-Location $HOME\projects\dotfiles-windows
   git config core.hooksPath .githooks
   ```

3. **Link and set up**, from the clone:

   ```powershell
   homeskillet check .   # report any problem in the manifests or files
   homeskillet link .    # link every file under home/
   homeskillet setup .   # review the setup steps and run the ones you approve
   ```

   Setup installs PowerShell 7 first, unless `prepare` did, then the tools,
   font, and toolchains, and creates the profile stub (see
   [Setup Steps](#setup-steps)). Then open a new PowerShell 7 terminal, which
   loads the profile.

4. **WSL**, optionally, in PowerShell 7, from the clone (see [WSL](#wsl)):

   ```powershell
   enable-wsl.ps1             # turn on WSL and install Ubuntu; restart if it asks
   wsl                        # once, to create your Linux user; then exit
   homeskillet wsl install    # homeskillet's Linux build in the distribution
   homeskillet wsl link .     # link home/wsl/ into its home
   homeskillet wsl setup .    # review the wsl- steps and run the ones you approve
   ```

Without homeskillet, install Git with
`winget install --id Git.Git --exact --source winget`, clone as above, and link
or copy the files by hand: each file under `home/` belongs at the same path under
your profile directory (`%USERPROFILE%`), and links need Developer Mode
(Settings, System, For developers). The setup steps in
[bootstrap.json](bootstrap.json), then [dotfiles.json](dotfiles.json), run as
written, from the clone, in PowerShell 7.

### Documents and OneDrive

PowerShell reads your profile only from `Documents\PowerShell`
(`$PROFILE.CurrentUserAllHosts` shows the exact path), and when OneDrive backs
up Documents, Windows redirects that folder into OneDrive. So nothing under
`home/` goes in Documents: the profile lives in `~\.config\powershell`, and the
`profile` setup step writes a stub where PowerShell looks, wherever Documents
is, that loads it. The stub is a created file, not a link, and loads nothing on
a machine without these dotfiles, such as another PC OneDrive copies it to.

The stub works whether or not OneDrive redirects Documents. To keep Documents
out of OneDrive altogether, including the modules PowerShell installs for you
there, turn off its backup in OneDrive's settings (Sync and backup, Manage back
up). Files OneDrive already backed up stay in the OneDrive folder; move back
what you need, then run the `profile` step again for the new Documents.

### The Host Profile

PowerShell runs the stub, and with it this repository's profile, in every host
before the host's own profile, `$PROFILE` (`Microsoft.PowerShell_profile.ps1`
in the console). `$PROFILE` stays a local file that nothing here links:
installers write to it, and Coreutils for Windows updates its block there by
replacing the whole file, which would turn a link into a copy.

When moving from an existing profile, anything `$PROFILE` still does that this
repository now does runs twice. Remove those parts from `$PROFILE`, keep only
what installers manage there, such as the block between the
`DO NOT MODIFY -- coreutils` markers, and move your own settings to `local.ps1`.
An existing `profile.ps1` in Documents is left alone: move what you need from it
to `local.ps1`, then run `init-profile.ps1 -Force`, which backs it up first.

## Setup Steps

The setup steps live in two manifests, which homeskillet merges, both declaring
`"platforms": ["windows"]` for every file and step: [bootstrap.json](bootstrap.json)
installs the tools, and [dotfiles.json](dotfiles.json) creates the files that
tools write into, beside the links. Neither lists files, so every file under
`home/` is linked, but `home/wsl/`, which is for WSL. homeskillet offers
`bootstrap.json`'s steps first, in order:

| Step | Manifest | Runs | Done when |
| --- | --- | --- | --- |
| `powershell` | `bootstrap.json` | `winget install` for PowerShell 7 | `pwsh` is on PATH |
| `winget-tools` | `bootstrap.json` | `install-tools.ps1 -NoUpgrade` on the clone's `tools.psd1`: installs what is missing | it has succeeded with `tools.psd1` and `install-tools.ps1` as they are; a change to either offers it again |
| `meslo-nerd-font` | `bootstrap.json` | `oh-my-posh font install Meslo` | MesloLGM Nerd Font is in your per-user fonts folder |
| `dotnet-sdk` | `bootstrap.json` | `install-dotnet.ps1`: the latest LTS .NET SDK into `~\.dotnet` | `~\.dotnet\dotnet.exe` exists |
| `go` | `bootstrap.json` | `install-golang.ps1`: the newest patch of the Go release one behind the latest into `~\.local\share\go` | `go` is on PATH |
| `profile` | `dotfiles.json` | `init-profile.ps1` | `{documents}\PowerShell\profile.ps1` exists, in Documents wherever it is |
| `local` | `dotfiles.json` | `init-local.ps1` | `~\.config\powershell\profile.d\local.ps1` exists |
| `scoop-config` | `dotfiles.json` | `init-scoop-config.ps1` | `~\.config\scoop\config.json` exists |

The steps named `wsl-` are for WSL instead, with `"platforms": ["linux"]` of
their own: `homeskillet setup` on Windows skips them, and
`homeskillet wsl setup .` offers them in the distribution (see [WSL](#wsl)).

PowerShell 7 comes first because the helpers run in it, through
`pwsh -NoProfile -File`, which its default execution policy allows for local
scripts. winget saves the PATH entries it adds, which only new processes read,
so before each step homeskillet adds them to the step's PATH: a step can run
what an earlier step installed in the same run, such as `pwsh` right after the
`powershell` step. That first run on a new machine is not yet verified here; if
a step cannot find a program, open a new terminal and run setup again.
`homeskillet setup . --dry-run` lists
every step and whether it is done.

The `profile` step's done check, `{documents}/PowerShell/profile.ps1`, names
Documents wherever OneDrive moves it: homeskillet resolves `{documents}`
through Windows' known folders, and to `Documents` under the home given with
`--home`. On Windows 11 with Documents in OneDrive,
`homeskillet setup . --dry-run` found the stub there and reported the step
done. The `go` step is done when any `go` is on PATH,
such as one from Go's own installer; run `install-golang.ps1` yourself to add
the per-user toolchain anyway.

The `winget-tools` step only installs what is missing, so rerunning setup never
upgrades a package in use, which some installers, such as Git's, refuse to do.
Upgrade on purpose with `install-tools.ps1`, which upgrades by default, or one
package with commands such as `update-pwsh` and `update-omp`.

The steps that install from a list, `winget-tools` and `wsl-apt-packages`,
name the list and its helper as `inputs`: homeskillet records them when the
step succeeds and counts the step done until one of them changes, so adding a
package to the list offers the step again. After uninstalling a listed package
by hand, name the step to run it anyway: `homeskillet setup . winget-tools`.
homeskillet keeps that record in its data directory, so with a new data
directory the step is offered again.

The font step installs every Meslo face for the current user, without
elevation; running it on Windows 11 with Oh My Posh 31.9 wrote the file the
step checks and registered MesloLGM Nerd Font, the face the Windows Terminal
fragment selects.

## Helpers

The helpers in `~\.local\share\helpers\pwsh` are on PATH in every session, so
run them by name; setup steps call them by their path in the clone, since a new
machine has no profile yet. Each takes `-Help`, and returns 0 on success, 1 on
failure, and 2 for a usage error.

- **`init-profile.ps1 [-Path FILE] [-DryRun] [-Force]`** creates the stub
  PowerShell runs as your profile, `$PROFILE.CurrentUserAllHosts` (or `FILE`),
  wherever Documents is. It dot-sources `~\.config\powershell\profile.ps1` when
  that exists. Where PowerShell already reads that file itself, as on Linux and
  macOS, it writes nothing.
- **`init-local.ps1 [-DryRun] [-Force]`** creates the starter `local.ps1`, with
  commented examples of the overrides the snippets support.
- **`init-scoop-config.ps1 [-DryRun] [-Force]`** creates Scoop's
  `config.json`, in `%XDG_CONFIG_HOME%\scoop` when that is set, as Scoop reads
  it. It names the Scoop-Core fork's `master` as the repository and branch Scoop
  updates itself from, and extracts MSI packages with lessmsi. Scoop-Core, the
  fork itself, reads the branch and the lessmsi setting but not `scoop_repo`,
  which is upstream Scoop's.
- **`install-tools.ps1 [-Path FILE] [-NoUpgrade] [-DryRun]`** installs every
  package `~\.config\winget\tools.psd1` (or `FILE`) lists that is missing, and
  upgrades the ones that are outdated, with
  `winget install --id ID --exact --source winget`. It first asks winget once
  which are installed (`winget export`); `-NoUpgrade`, which the setup step
  uses, leaves those alone without running winget for them, so a rerun changes
  nothing that is already there. It prints one line per package, such as
  `Git ... upgraded`, `uv ... installed`, or `Oh My Posh ... up to date`, and
  shows winget's own output only for a package that failed. A package whose
  installer cannot upgrade it, such as MSYS2, which updates itself
  (`pacman -Syu`), counts as done. Every package is tried, and the helper fails
  if any did. `-DryRun` prints the commands and needs no winget.
- **`install-dotnet.ps1 [RELEASE | VERSION] [DOTNET-INSTALL OPTION...]`** runs
  Microsoft's [dotnet-install script](https://learn.microsoft.com/dotnet/core/tools/dotnet-install-script)
  into `~\.dotnet` (or `DOTNET_INSTALL_DIR`): the latest LTS SDK, or `LTS`,
  `STS`, a release such as `10.0` (or `10`), a feature band such as `10.0.1xx`,
  or an exact version such as `10.0.100`. Other options pass through, such as
  `-Runtime aspnetcore` or `-DryRun`. It downloads the script to a file and runs
  it only when Microsoft's Authenticode signature on it is valid, and keeps a
  copy in the install directory. The zip the script downloads must match a
  SHA-512 that Microsoft's release list publishes for the version installed;
  otherwise the helper removes what that run added and fails. It prints one
  line, such as `Installing the .NET SDK (LTS) into C:\Users\you\.dotnet ...
  installed 10.0.403; the download matches the SHA-512 in Microsoft's release
  list`, and shows the script's own output only when it failed, or with
  `-Verbose` or `-DryRun`. There, "Either downloaded or local package size can
  not be measured. One of them may be corrupted." only means the download
  server did not report the file's size, so the script could not compare it.
- **`install-golang.ps1 [-Latest | VERSION] [-DryRun]`** installs Go from
  go.dev into `~\.local\share\go` (or `GO_INSTALL_DIR`), as `install-go.sh`
  does on macOS: by default the newest patch of the release one behind the
  latest (go1.26.10 while go1.27 is current), the latest with `-Latest` or
  `--latest`, or a version such as `1.26.10`. Only stable releases count,
  ordered by version number. Rerun it to move to a newer patch of that release,
  such as go1.26.11, once go.dev lists one; a toolchain already at it, or at a
  newer version, is left alone, and only a `VERSION` you give moves to an older
  one. The zip must match the SHA-256 in go.dev's release list before it is
  unpacked, and an older toolchain is replaced only after the new one runs.
  `-DryRun` reports what it would install.

- **`enable-developer-mode.ps1 [-DryRun]`** turns on Windows' Developer Mode,
  which lets you create links without administrator rights, as homeskillet
  does to install itself and link files. It sets the registry value Microsoft
  documents for it, in a copy of itself started as administrator, which Windows
  asks you to approve; homeskillet refuses to run as administrator, so only
  that write is elevated. Developer Mode also lets you install apps from any
  source; turn it off in Settings, under For developers.
- **`enable-wsl.ps1 [-Distribution NAME | -NoDistribution] [-DryRun]`** turns
  on the Windows Subsystem for Linux with `wsl --install --no-distribution`, as
  administrator after the Windows prompt, then installs a distribution as you:
  Ubuntu unless `-Distribution` names another from `wsl --list --online`, or
  none with `-NoDistribution`. It does not start it; run `wsl` afterward to
  create its user. It checks first, without administrator rights: WSL counts as
  on when `wsl --version` runs and the Virtual Machine Platform feature is not
  off, and what is on is left alone. While part of WSL is on and Windows waits
  for a restart, it says to restart rather than asking to turn WSL on again;
  run it again afterward to install the distribution. The restart path has not
  run on Windows yet, since WSL was already on where it was written.

The setup steps do not run these two: Developer Mode must be on before
homeskillet can link anything, and turning on WSL can need a restart. The bash
helpers WSL's steps run are under [WSL](#wsl).

Neither installer changes your saved PATH: `dotnet.ps1` and `golang.ps1` put
their toolchains first on PATH in PowerShell. Their download and install paths
are not yet verified on Windows; argument handling and dry runs are.

The init helpers create files that tools or you write to, which a link would
carry into this repository, or that belong where OneDrive may sync, so they
create each once and never link it. An
existing file is left alone; `-Force` renames it to `NAME.bak.DATE-TIME` first,
and `-DryRun` only reports what would happen. The home is `HOME` when it is set,
as homeskillet sets it for steps, and PowerShell's `$HOME` otherwise.

## Layout

```text
home/                                   linked into %USERPROFILE%, file by file
  .config/powershell/profile.ps1        the profile: environment, PATH, snippets
  .config/powershell/profile.d/         one snippet per tool
  .config/winget/tools.psd1             the winget packages
  .config/oh-my-posh/themes/            Oh My Posh themes
  .local/share/helpers/pwsh/            helpers, which setup steps run
  AppData/Local/Microsoft/Windows Terminal/Fragments/
                                        the Windows Terminal fragment
  wsl/                                  linked into the WSL home instead, never on Windows
    .bashrc, .bash_profile, .bashrc.d/  bash, with one snippet per tool
    .config/apt/packages                the apt packages for the distribution
    .config/oh-my-posh/themes/          the same Oh My Posh themes
    .local/share/helpers/sh/            bash helpers, which WSL's setup steps run
bootstrap.json                          platforms and the setup steps that install tools
dotfiles.json                           platforms and the setup steps that create files
scripts/                                repository tooling: checks, lint settings, secret scan
tests/check.sh                          regression checks
```

homeskillet links every file under `home/`, skipping `.DS_Store`, `Thumbs.db`,
`desktop.ini`, and `.git`. Names must be ones Windows can create: no device
names such as `CON` or `nul.txt`, no names ending in a dot or space, none of
`<>:"|?*\`, and no two paths that differ only in case. homeskillet checks these
rules on any system.

## The Profile

[profile.ps1](home/.config/powershell/profile.ps1) runs in every PowerShell 7
host, loaded by the stub in Documents, in this order:

1. **Environment:** `POWERSHELL_UPDATECHECK=Off`,
   `POWERSHELL_TELEMETRY_OPTOUT=1`, and `DO_NOT_TRACK=1`, each unless already
   set. pwsh reads its own two as it starts, so from the profile they reach only
   the processes a session starts; set them as user environment variables to
   cover every session.
2. **PATH:** the machine and user PATH entries the session lacks are appended,
   so a terminal opened before a tool was installed still finds it; inherited
   entries keep their order. Then `~\.local\bin`, where homeskillet and other
   installers put commands, and the helpers directory are appended.
3. **Snippets:** every `*.ps1` in `~\.config\powershell\profile.d`, in
   alphabetical order, including the unmanaged `local.ps1`.

### Snippets

| File | What it does |
| --- | --- |
| `00-psreadline.ps1` | In interactive consoles: Windows key bindings, history saved when the session exits, predictions from history and plugins as a list (inline in windows smaller than 50 columns by 5 rows), a menu of every completion on Tab, and syntax colors. It runs first because setting the edit mode resets key bindings that later files add. |
| `aliases.ps1` | `ls [-a] [PATH]`, `la`, `ll`, and `env` as on Unix (`-a`, `-la`, or `-al` includes hidden items; `-l` is accepted), and `gs` and `gitcm` for `git status` and `git commit` |
| `functions.ps1` | `hist PATTERN` searches this session's history by regular expression, `edit-last` opens the last command in VS Code, `Update-WingetPackage ID` upgrades one winget package by its exact ID, and `update-pwsh` (`Update-PowerShell`) upgrades PowerShell 7 with it |
| `dotnet.ps1` | `DOTNET_CLI_TELEMETRY_OPTOUT=1` and `DOTNET_NOLOGO=1` unless set; a `~\.dotnet` (or `DOTNET_INSTALL_DIR`) SDK from `install-dotnet.ps1` first on PATH, with `DOTNET_ROOT`, and its global tools appended; in interactive sessions, `dotnet` completion on Tab |
| `github.ps1` | `set-gh-token` (`Set-GitHubToken`) saves a GitHub token as `GITHUB_TOKEN`; see [GitHub Token](#github-token) |
| `golang.ps1` | A toolchain from `install-golang.ps1` first on PATH; `GOBIN`, or the first `GOPATH` entry's `bin`, appended; Go's telemetry turned off with `go telemetry off`, which Go saves |
| `gnupg.ps1` | `new-gpg-key` and `gpg-key-1y`, `-5y`, `-10y` create an Ed25519 signing key for Git's author identity variables; `gpg-keyid` and `gpg-keyid-short` list secret key IDs; `gpg-pub` and `gpg-pub-copy` print or copy public keys; `git-sign-key` makes Git sign commits, globally or with `-Local`, and takes `gpg-keyid` output from the pipeline |
| `homeskillet.ps1` | In interactive sessions on PowerShell 7.3 or later: homeskillet's Tab completion, which it writes itself (`homeskillet completion pwsh`), so it matches the installed version |
| `oh-my-posh.ps1` | In interactive sessions: the Oh My Posh prompt, when it is installed, with the theme named by `OHMYPOSH_THEME` (`bubblesextra` by default): the date and time on the left with a 12-hour clock (`Sun Oct 25 03:51:28 AM PDT 2026`), and the path, Git, language versions, and battery on the right, on a line of their own when the terminal is too narrow for both. `update-omp` (`Update-OhMyPosh`) upgrades Oh My Posh with winget; open a new terminal afterward |
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

### GitHub Token

Builds that download dependencies from private GitHub repositories, such as a
Makefile, read `GITHUB_TOKEN`, a personal access token with access to those
repositories. `set-gh-token` asks for it without echoing it and saves it in your
user environment variables, for this session and every program started
afterward; terminals already open keep their old value until restarted. An
empty answer changes nothing, and `Set-GitHubToken -Remove` deletes it. Run it
again to replace the token.

Windows keeps user environment variables unencrypted in the registry and passes
them to every program you start, so give the token only the access the builds
need, such as a fine-grained token with read-only contents access to those
repositories. Keep it out of `local.ps1`, which is a plain file, and never set
it to `''` there: that removes it from every session. The GitHub CLI reads
`GITHUB_TOKEN` ahead of the login `gh auth login` stores, so while it is set, gh
acts with the token's access (see `gh help environment`).

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

## WSL

`home/wsl/` is the home of your WSL distribution. homeskillet links it there,
from inside the distribution, and never on Windows; it never links across the
Windows and WSL boundary. From the clone, on Windows:

```powershell
homeskillet wsl install       # homeskillet's Linux build in the distribution, once per version
homeskillet wsl link .        # link home/wsl/ into the distribution's home
homeskillet wsl setup .       # offer the wsl- setup steps there
homeskillet wsl status .      # what is linked, and whether the copy is current
```

Each acts in WSL's default distribution, or the one `--distribution NAME`
names. The others run homeskillet's Linux build there, which must be the
version that runs on Windows, so run `homeskillet wsl install` again after
`homeskillet update`. homeskillet copies the clone into the distribution, under
`~/.local/share/homeskillet/mirrors/`, and links from the copy, since WSL shows
files on a Windows drive as writable by everyone; edit the clone on Windows and
run `homeskillet wsl link .` again to bring changes across. Ubuntu comes with
its own `~/.bashrc` and `~/.bash_logout`, which the first link reports as
conflicts and leaves alone; `homeskillet wsl link . --force` moves them into
homeskillet's `backups/` first. Then open a new WSL shell.

What `home/wsl/` holds is taken from `dotfiles-linux`, byte for byte, where it
works in WSL; the checks compare each copy when that repository is cloned
beside this one:

- **Shell:** `.bashrc`, `.bash_logout`, and snippets in `~/.bashrc.d` for
  aliases, functions, history, the Oh My Posh prompt, Go, .NET, Python with uv,
  homeskillet, AWS, Google Cloud, kubectl, OpenTofu, and Terraform, each silent
  when its tool is missing. `.bash_profile` is this repository's own:
  `dotfiles-linux`'s without its Ptyxis and GNOME Terminal settings, since
  Windows Terminal draws WSL's text, in the Nerd Font the Windows side installs.
- **Tools:** Git's defaults in `~/.config/git/config`, tmux, vim, `.inputrc`,
  `.curlrc`, `.hushlogin`, and the same Oh My Posh themes as Windows.
  `.hushlogin` also stops Ubuntu's once-a-day welcome message, which
  `/etc/profile.d/update-motd.sh` shows and records in `~/.motd_shown`; that
  stamp is Ubuntu's, not this repository's, and can be deleted.
- **Helpers** in `~/.local/share/helpers/sh`: `init-gitconfig.sh`,
  `init-local.sh`, `install-oh-my-posh.sh`, `install-dotnet.sh`, and
  `install-go.sh`, as `dotfiles-linux` documents them, and this repository's
  `install-apt-packages.sh [--dry-run] LIST`, which installs the packages a list
  names that dpkg does not report installed, with `apt-get` through `sudo`.

Left out are `dotfiles-linux`'s VS Code snippet and installer, since WSL uses
Windows' VS Code through its WSL extension, and its font step. The WSL steps:

| Step | Manifest | Runs | Done when |
| --- | --- | --- | --- |
| `wsl-apt-packages` | `bootstrap.json` | `install-apt-packages.sh` on `~/.config/apt/packages`: the missing packages, with `sudo` | it has succeeded with the list and `install-apt-packages.sh` as they are; a change to either offers it again |
| `wsl-oh-my-posh` | `bootstrap.json` | `install-oh-my-posh.sh`: Oh My Posh's latest release, checked against its checksums, into `~/.local/bin` | `oh-my-posh` is on PATH |
| `wsl-dotnet-sdk` | `bootstrap.json` | `install-dotnet.sh`: the latest LTS .NET SDK into `~/.dotnet` | `~/.dotnet/dotnet` exists |
| `wsl-go` | `bootstrap.json` | `install-go.sh`: the newest patch of the Go release one behind the latest into `~/.local/share/go` | `~/.local/share/go/bin/go` exists, so an older `go` from apt does not count |
| `wsl-gitconfig` | `dotfiles.json` | `init-gitconfig.sh`: a starter `~/.gitconfig` for identity, signing, and credentials | `~/.gitconfig` exists |
| `wsl-local` | `dotfiles.json` | `init-local.sh`: a commented `~/.bashrc.d/local.sh` for this distribution's settings | `~/.bashrc.d/local.sh` exists |

`sudo` asks for your Linux password only at a terminal, so run
`homeskillet wsl setup .` without `--yes`; unattended, `install-apt-packages.sh`
says what it needs and fails rather than wait. `homeskillet wsl link` and
`setup` ran in Ubuntu 24.04 under WSL 2: every file linked, the shells loaded
silently, and the Oh My Posh, .NET, and Go steps installed in a temporary home.
`install-apt-packages.sh` has run only as a dry run and with every listed
package installed already, so installing through `sudo` is not yet verified.
The checks run linking and setup acting for Linux in a temporary home.

## Customize

- **Your own copy:** fork this repository and clone the fork. Nothing in it is
  tied to one machine, user name, or path: the helpers find the home and
  Documents as they run. Change `CODEOWNERS`, the account GitHub asks to review
  pull requests, to yours; keep `LICENSE`'s copyright notice, as the MIT
  License asks; and keep what belongs to one machine in `local.ps1`, which is
  never linked.
- **This machine:** put settings in `~\.config\powershell\profile.d\local.ps1`.
  It loads after the snippets whose names sort before it, such as
  `00-psreadline.ps1`, so it can replace what they set, and before
  `oh-my-posh.ps1`, which reads its settings.
- **Prompt theme:** set `OHMYPOSH_THEME`, in `local.ps1` or your user
  environment variables, to the name of a theme in
  `~\.config\oh-my-posh\themes` (without `.omp.json`) or the path to any theme
  file. Every bundled theme except `jandedobbeleer` starts with the date and
  time at the left. The clock format is the `time_format` of a theme's `time`
  segment, a Go time layout; change it in the theme files themselves, which
  every machine and the sister repositories share.
- **Environment defaults:** set `POWERSHELL_UPDATECHECK`,
  `POWERSHELL_TELEMETRY_OPTOUT`, or `DO_NOT_TRACK` yourself, and the profile
  keeps your value.
- **Packages:** add an entry to `tools.psd1` with the package's ID from
  `winget show`, which `--exact` matches case and all. Its header shows the PATH
  edits that Make and MSYS2's gcc need, since neither puts its command on PATH.
- **WSL packages:** add a line to `home/wsl/.config/apt/packages` with the
  package's name as `apt` knows it; `homeskillet wsl setup .` installs it when
  missing. Settings for the distribution alone go in its
  `~/.bashrc.d/local.sh`, which the `wsl-local` step creates.
- **Toolchains:** set `DOTNET_INSTALL_DIR` or `GO_INSTALL_DIR` to install
  elsewhere; `dotnet.ps1` and `golang.ps1` follow them too. Set `GOPATH`, `GOBIN`,
  and other Go settings with `go env -w`, which Go saves outside this
  repository.

## Troubleshooting

- **The prompt shows boxes or question marks:** the terminal font is not a Nerd
  Font. Run the `meslo-nerd-font` step, then select `MesloLGM Nerd Font` in the
  terminal's settings; the Windows Terminal fragment does this for its
  PowerShell profile.
- **No prompt theme:** check `oh-my-posh version`, and that `OHMYPOSH_THEME`
  names a theme that exists in `~\.config\oh-my-posh\themes`. The prompt loads
  only in interactive sessions.
- **The profile does not load:** run `init-profile.ps1`. It says whether
  `$PROFILE.CurrentUserAllHosts` is the stub or another file, which `-Force`
  backs up and replaces. The stub loads nothing until
  `~\.config\powershell\profile.ps1` exists.
- **Something runs twice:** `$PROFILE` still holds an old copy of the profile;
  see [The Host Profile](#the-host-profile).
- **A change to the profile does not show:** run `. $PROFILE.CurrentUserAllHosts`
  at the prompt, or open a new terminal. A function cannot reload it, because
  dot-sourcing inside a function keeps the definitions in that function's scope.
- **A new session starts slowly:** time the profile at the prompt with
  `Measure-Command { . $PROFILE.CurrentUserAllHosts }`, then move snippets out
  of `profile.d` one at a time to find the slow one. The prompt runs
  `oh-my-posh init` once per interactive session.
- **homeskillet cannot create a link, or install itself:** Developer Mode is
  off. Turn it on in Settings under For developers, which `homeskillet prepare`
  opens for you, or with `enable-developer-mode.ps1`.
- **`homeskillet` is not found:** it is in `~\.local\bin`. The profile adds that
  folder in PowerShell; for other programs, add it to your user Path in
  Settings (search for environment variables) and open a new terminal.
- **`install-tools.ps1` fails on a package:** the package's line shows winget's
  exit code, which `winget error CODE` explains, and winget's own output,
  including the installer's log path. Under `homeskillet setup`, everything
  between the step's prompt and its exit status is the step's own output. Git
  for Windows refuses to upgrade while any program runs from its folder, and
  under winget it cancels rather than asks: close Git Bash and programs started
  from it, stop the GnuPG agents Git's own `gpg` starts with
  `& "$env:ProgramFiles\Git\usr\bin\gpgconf.exe" --kill all`, and run
  `install-tools.ps1` again. The log lists the programs it found.
- **`wsl-apt-packages` says a package needs sudo:** run
  `homeskillet wsl setup .` without `--yes`, in a terminal, so `sudo` can ask
  for your Linux password.
- **`homeskillet wsl link .` reports conflicts:** Ubuntu's own `~/.bashrc` and
  `~/.bash_logout` are in the way; move what you need from them to
  `~/.bashrc.d/local.sh`, then run `homeskillet wsl link . --force`, which
  backs them up first.
- **A change in `home/wsl/` does not show in WSL:** links there lead into
  homeskillet's copy of the clone; run `homeskillet wsl link .` to update it,
  then open a new WSL shell.
- **`go` is not found in WSL:** `install-go.sh` links it into `~/.local/bin`,
  which `.bashrc` puts on PATH; open a new WSL shell.
- **A program a step installed is not found:** winget adds programs to PATH for
  new processes only. Open a new terminal; the profile also picks up PATH
  entries saved since the terminal started.
- **`Add-SshKey` says the agent is not running:** set the service to start at
  boot, as shown under [Snippets](#snippets).
- **A program outside PowerShell runs another `go` or `dotnet`:** the per-user
  toolchains lead PATH only in PowerShell, so programs started from the Start
  menu find what your saved PATH lists, such as Go's installer's
  `C:\Program Files\Go\bin`. Start them from PowerShell, point them at the
  toolchain, or uninstall the other one (`winget uninstall --id GoLang.Go`).
  `install-golang.ps1` names the other `go` when it finds one.
- **A build does not see `GITHUB_TOKEN`:** the terminal started before
  `set-gh-token` ran; open a new one.
- **`gh auth login` says `GITHUB_TOKEN` is being used for authentication:** gh
  uses the token instead of its own login. Run `Set-GitHubToken -Remove` to go
  back to gh's login, or `Remove-Item Env:GITHUB_TOKEN` for this session only.
- **A commit is blocked:** the hook prints each problem as `file:line: reason`,
  without the secret. Remove the secret, or for a reviewed false positive add a
  `secret-scan: allow` comment or a `!path` exception to `.gitignore`.
  `git commit --no-verify` skips the hook, but CI still runs the scan.

## Secrets

This repository is public. [.gitignore](.gitignore) ignores credential, key,
history, and environment files anywhere, including under `home/`. The pre-commit
hook, [.githooks/pre-commit](.githooks/pre-commit), runs
[scripts/check-secrets.sh](scripts/check-secrets.sh) on what each commit adds,
and CI runs it on every tracked file. Tokens the profile's commands save, such
as `GITHUB_TOKEN`, go to your user environment variables, never to a file here.
Turn the hook on once per clone:

```sh
git config core.hooksPath .githooks
```

## Checks

The checks run with Bash on Linux and macOS, and in Git Bash on Windows; given
the homeskillet binary for the system they run on, they also check what it
links and offers for Windows and for WSL. They lint PowerShell with
[PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)
when it is installed, so install it once, in PowerShell 7:

```powershell
Install-PSResource PSScriptAnalyzer -Scope CurrentUser
```

```sh
bash tests/check.sh                               # PowerShell, profile, helpers, and JSON
bash tests/check.sh "$(command -v homeskillet)"   # also check, link, status, unlink, and setup --dry-run
bash scripts/check-secrets.sh --all
```

When `pwsh` is installed, `tests/check.sh` parses every PowerShell file with
PowerShell's own parser and lints it with PSScriptAnalyzer under
[scripts/PSScriptAnalyzerSettings.psd1](scripts/PSScriptAnalyzerSettings.psd1);
point VS Code's `powershell.scriptAnalysis.settingsPath` at that file to see the
same findings in the editor. It loads the profile and its
snippets, through the stub `init-profile.ps1` writes, in a new session whose
home holds a copy of `home/` and whose PATH is empty, before and after
`init-local.ps1` adds `local.ps1`, requiring them to
print nothing, leave no variables behind, and define their commands. It runs
the update commands against a stand-in winget and, off Windows, where nothing
reaches the user environment, `Set-GitHubToken` against stand-in answers. It
loads the profile with stand-ins for the installers' toolchains to check PATH,
and points `APPDATA` into the temporary home, so tools the profile runs, such
as `go telemetry off`, never change your real settings. It runs each helper
in a temporary home, with `XDG_CONFIG_HOME` cleared and pwsh's own cache and
modules kept outside it, so a helper never writes your real configuration;
checks that `init-scoop-config.ps1` follows `XDG_CONFIG_HOME` when it is set;
checks that `install-tools.ps1 -DryRun` installs
every package `tools.psd1` lists, and runs it against a stand-in winget to
check its one-line report and that `-NoUpgrade` leaves installed packages
alone. It checks that the toolchain installers reject bad arguments before
downloading anything, how `install-dotnet.ps1` finds what an install added
and the SHA-512s a release list publishes for it, and how `enable-wsl.ps1`
reads WSL's state, including a pending restart. For `home/wsl/`, it requires
LF line endings, every bash file to parse, and the login shell to load
silently from a copy with only the base system's commands; it runs the bash
helpers as on any Linux: `install-go.sh` against a local release list, and
`install-apt-packages.sh` against stand-ins for `dpkg-query`, `apt-get`, and
`sudo`, so nothing is installed. It requires `home/wsl/`'s themes to match
Windows', and with `dotfiles-linux` and `dotfiles-macos` cloned beside this
repository, the themes to match theirs and every copy in `home/wsl/` to match
`dotfiles-linux`'s. It parses every JSON file and checks the two manifests:
each declares only Windows and lists no files, no step is in both, every
`dotfiles.json` step creates a file, every step has `creates`, `provides`, or
`inputs`, so none is offered every run, every file under `home/` a step uses
or lists as an input exists, inputs are under `home/`, and the `wsl-` steps
alone are for Linux and use `home/wsl/`; a copy that breaks each rule about done
checks and inputs must fail with exactly those problems. From a local
release list, given with `GO_RELEASE_LIST`, it checks which Go
`install-golang.ps1 -DryRun` picks: the release before the latest by default,
the latest with `--latest`, and a newer patch on a rerun. When oh-my-posh is
installed, it renders every theme except `jandedobbeleer`, wide and narrow,
and requires the date and time to lead the top line. It requires each
PowerShell file to be ASCII either way, since Windows PowerShell 5.1 misreads
anything else. Given a homeskillet
binary, it confirms nothing applies on macOS, then acts for Windows with
`--platform windows`: it links every file under `home/` but `home/wsl/` into a
temporary home, checks and unlinks them, and lists the setup steps without
running any, the Windows ones alone. Acting for Linux, it links `home/wsl/`
alone into another temporary home and lists the `wsl-` steps alone, as
`homeskillet wsl` does inside the distribution, with no WSL needed. It
requires `homeskillet check` to find both manifests and every file valid, every
step from both manifests, `bootstrap.json`'s first, and the `profile` step to
be done once the stub is in the temporary home's Documents. A homeskillet older
than 0.2.0 lacks some of these and fails the checks at the first one.

GitHub Actions runs the checks on Ubuntu on every push and pull request, with
homeskillet's Linux release, checked against its `SHA256SUMS`, and fails if
PSScriptAnalyzer did not lint every PowerShell file. Raise `HOMESKILLET_VERSION`
in [checks.yml](.github/workflows/checks.yml) when homeskillet releases a new
version. It also runs ShellCheck on the Bash tooling; nothing runs ShellCheck
on Windows.

[.pre-commit-config.yaml](.pre-commit-config.yaml) adds optional checks for
[pre-commit](https://pre-commit.com), such as YAML and JSON syntax, whitespace,
executable bits, and private keys. They complement `.githooks/pre-commit` and
do not replace it. Because `core.hooksPath` is set, `pre-commit install`
refuses to install, so run them on demand:

```sh
pre-commit run --all-files  # every check on every tracked file
pre-commit autoupdate       # refresh the pinned hook versions
```

## Contributing

[AGENTS.md](AGENTS.md) lists the conventions for changes and the checks to run
before finishing.

## License and Credits

Released under the [MIT License](LICENSE). The prompt themes in
[home/.config/oh-my-posh/themes/](home/.config/oh-my-posh/themes/) come from
[Oh My Posh](https://github.com/JanDeDobbeleer/oh-my-posh), also released under
the MIT License, and are identical to those in `dotfiles-linux` and
`dotfiles-macos`. Every theme except `jandedobbeleer` starts its top line with
the date and time on a 12-hour clock (`Sun Oct 25 03:51:28 AM PDT 2026`):
`bubbles` and `bubblesextra` add it at the left and move the right side of that
line to a line of its own when both do not fit (`"overflow": "break"`), and
`emodipt` shows the full date in its bracketed clock instead of only the time,
and the full path instead of `..` for each parent folder. `jandedobbeleer`,
which keeps its clock on the right, is the upstream file unchanged.
