# .NET SDK
# https://learn.microsoft.com/dotnet/core/tools/dotnet-environment-variables

# Telemetry: no usage data sent to Microsoft, and no first-run banner. Values
# set first win.
if (-not $env:DOTNET_CLI_TELEMETRY_OPTOUT) { $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1' }
if (-not $env:DOTNET_NOLOGO) { $env:DOTNET_NOLOGO = '1' }

# A user install from install-dotnet.ps1 lives in $HOME\.dotnet (or
# DOTNET_INSTALL_DIR, which the installer follows too) and goes first on PATH,
# ahead of a machine-wide SDK, with DOTNET_ROOT naming it so apps and global
# tools find its runtime. Global tools (dotnet tool install --global) live in
# $HOME\.dotnet\tools wherever the SDK is, which is appended.
$dotnetDir = if ($env:DOTNET_INSTALL_DIR) { $env:DOTNET_INSTALL_DIR } else { Join-Path $HOME '.dotnet' }
if (Test-Path -LiteralPath (Join-Path $dotnetDir 'dotnet.exe') -PathType Leaf) {
    if (-not $env:DOTNET_ROOT) { $env:DOTNET_ROOT = $dotnetDir }
    if (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $dotnetDir) {
        $env:PATH = $dotnetDir + [System.IO.Path]::PathSeparator + $env:PATH
    }
}
$dotnetTools = Join-Path $HOME '.dotnet/tools'
if ((Test-Path -LiteralPath $dotnetTools -PathType Container) -and
    ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $dotnetTools) {
    $env:PATH = $env:PATH + [System.IO.Path]::PathSeparator + $dotnetTools
}
Remove-Variable dotnetDir, dotnetTools -ErrorAction Ignore

# Completion in interactive sessions, as Microsoft documents it: dotnet answers
# through `dotnet complete`, run only when Tab is pressed. The arguments are the
# word, the command line, and the cursor position.
# https://learn.microsoft.com/dotnet/core/tools/enable-tab-autocomplete#powershell
if ((Get-Module PSReadLine) -and (Get-Command dotnet -ErrorAction Ignore)) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        dotnet complete --position $args[2] "$($args[1])" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
