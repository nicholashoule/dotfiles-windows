# Aliases
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_aliases
# Short commands, as on Unix. A PowerShell alias cannot take arguments, so the
# ones that pass arguments are one-line functions.

# Listing. PowerShell's own ls alias would hand -a to Get-ChildItem, which
# rejects it, so the alias gives way to a function: ls lists visible items, ls -a
# (or -la, -al) hidden ones too, and -l is accepted because Get-ChildItem always
# shows the long form. When Coreutils for Windows' integration is in $PROFILE,
# lines typed at the prompt run its ls, la, and env instead.
Remove-Item Alias:\ls -Force -ErrorAction SilentlyContinue
function ls {
    param([switch]$a, [switch]$l, [switch]$la, [switch]$al, [string]$Path = '.')
    Get-ChildItem -Path $Path -Force:($a -or $la -or $al)
}
function la { Get-ChildItem -Force @args }
Set-Alias ll Get-ChildItem
function env { Get-ChildItem Env: }

# Git. gcm, gp, and gl stay PowerShell's own aliases (Get-Command,
# Get-ItemProperty, Get-Location); an alias wins over a function of the same
# name, so these use names PowerShell leaves free.
function gs { git status @args }
function gitcm { git commit @args }
