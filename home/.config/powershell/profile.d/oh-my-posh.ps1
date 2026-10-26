# Oh My Posh
# https://ohmyposh.dev/docs/installation/prompt
# Themes: https://ohmyposh.dev/docs/themes
# Font: set the terminal to a Nerd Font (the meslo-nerd-font setup step installs
# one, and the Windows Terminal fragment selects it).
# OHMYPOSH_THEME picks the theme, as on Linux and macOS: the name of a theme in
# ~\.config\oh-my-posh\themes (without .omp.json; bubblesextra by default) or a
# path to any theme file. Set it in local.ps1, which loads earlier, or in your
# user environment variables. A theme file that does not exist leaves the plain
# prompt. The prompt loads only in interactive sessions, where the console has
# loaded PSReadLine, so `pwsh -Command` skips its cost. The generated prompt runs
# only if `oh-my-posh init` produced it successfully.
if ((Get-Module PSReadLine) -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    $ohMyPoshTheme = if ($env:OHMYPOSH_THEME) { $env:OHMYPOSH_THEME } else { 'bubblesextra' }
    if ($ohMyPoshTheme -notmatch '[\\/]') {
        $ohMyPoshTheme = Join-Path $HOME ".config/oh-my-posh/themes/$ohMyPoshTheme.omp.json"
    }
    if (Test-Path -LiteralPath $ohMyPoshTheme -PathType Leaf) {
        $ohMyPoshInit = oh-my-posh init pwsh --config $ohMyPoshTheme
        if ($LASTEXITCODE -eq 0 -and $ohMyPoshInit) {
            $ohMyPoshInit | Out-String | Invoke-Expression
        }
    }
    Remove-Variable ohMyPoshTheme, ohMyPoshInit -ErrorAction SilentlyContinue
}

# Update-OhMyPosh (update-omp) upgrades Oh My Posh with winget, in every session.
# Open a new terminal afterward to load the new version's prompt.
# https://ohmyposh.dev/docs/installation/windows
function Update-OhMyPosh { Update-WingetPackage JanDeDobbeleer.OhMyPosh }
Set-Alias update-omp Update-OhMyPosh
