# Functions
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions
# General-purpose commands; tool-specific ones live in that tool's file.

# hist PATTERN searches this session's history by regular expression; Ctrl+R
# searches the history saved from every session.
function hist {
    param([string]$Pattern)
    Get-History | Where-Object CommandLine -Match $Pattern
}

# edit-last opens the last command in VS Code, for turning it into a script.
function edit-last {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Warning 'edit-last needs VS Code: the code command is not on PATH.'
        return
    }
    $file = Join-Path ([System.IO.Path]::GetTempPath()) "edit-last-$PID.ps1"
    (Get-History -Count 1).CommandLine | Set-Content -LiteralPath $file
    code $file
}

# Update-PowerShell (update-pwsh) upgrades PowerShell 7 with winget. Restart the
# terminal afterward to run the new version.
function Update-PowerShell {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning 'winget is not available: install App Installer from the Microsoft Store.'
        return
    }
    winget upgrade --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements
}
Set-Alias update-pwsh Update-PowerShell
