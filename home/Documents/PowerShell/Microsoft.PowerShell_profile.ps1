# PowerShell 7 profile for the current user and host ($PROFILE): pwsh runs it at
# the start of every session that loads profiles.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
#
# homeskillet links it to ~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1.
# Keep this file ASCII: Windows PowerShell 5.1 reads a script without a byte-order
# mark in the system's ANSI code page, which garbles anything else.

# Oh My Posh
# https://ohmyposh.dev/docs/installation/prompt
# Themes: https://ohmyposh.dev/docs/themes
# Font: set the terminal to a Nerd Font (the meslo-nerd-font setup step installs one).
# OHMYPOSH_THEME picks the theme, as on Linux and macOS: the name of a theme in
# ~\.config\oh-my-posh\themes (without .omp.json; bubblesextra by default) or a
# path to any theme file. The generated prompt runs only if `oh-my-posh init`
# produced it successfully.
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
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
