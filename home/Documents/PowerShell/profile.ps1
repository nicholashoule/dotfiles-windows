# PowerShell 7 profile for the current user in every host
# ($PROFILE.CurrentUserAllHosts): pwsh runs it at the start of every session that
# loads profiles, before the host's own profile, $PROFILE.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
#
# homeskillet links it to ~\Documents\PowerShell\profile.ps1, which OneDrive
# holds when it backs up Documents, so this file stays small and the rest lives
# under ~\.config and ~\.local, outside Documents. Keep this file ASCII: Windows
# PowerShell 5.1 reads a script without a byte-order mark in the system's ANSI
# code page, which garbles anything else.
#
# Order of operations:
#   1. this file                  environment defaults, PATH, and the helpers
#                                 in ~\.local\share\helpers\pwsh, appended
#   2. ~\.config\powershell\profile.d\*.ps1
#                                 one file per tool, dot-sourced in alphabetical
#                                 order; prefix a name with 00- or zz- to run it
#                                 first or last. Machine-specific settings go in
#                                 an unmanaged local.ps1 there, which the local
#                                 setup step creates with commented examples and
#                                 never links; it loads with the others.
#   3. $PROFILE                   the host's own profile, a local file that
#                                 installers such as Coreutils for Windows write
#                                 to by replacing the whole file, which would turn
#                                 a link into a copy, so nothing here links it

# Environment
# Values set before the profile runs win. pwsh reads its own two as it starts, so
# here they reach only the processes this session starts, such as a nested pwsh;
# set them as user environment variables to cover every session. DO_NOT_TRACK
# opts out of telemetry in tools that honor the Console Do Not Track convention.
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_update_notifications
# https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_telemetry
if (-not $env:POWERSHELL_UPDATECHECK) { $env:POWERSHELL_UPDATECHECK = 'Off' }
if (-not $env:POWERSHELL_TELEMETRY_OPTOUT) { $env:POWERSHELL_TELEMETRY_OPTOUT = '1' }
if (-not $env:DO_NOT_TRACK) { $env:DO_NOT_TRACK = '1' }

# PATH
# A terminal inherits PATH from the process that started it, so it can miss a
# tool installed since then, such as by a setup step. Append the machine and user
# PATH entries this session lacks, keeping the inherited entries and their order.
if ($IsWindows) {
    $pathSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pathEntries = foreach ($pathEntry in @(
            $env:PATH
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
        ) -split ';') {
        if ($pathEntry -and $pathSeen.Add($pathEntry.TrimEnd('\'))) { $pathEntry }
    }
    $env:PATH = $pathEntries -join ';'
    Remove-Variable pathSeen, pathEntries, pathEntry -ErrorAction SilentlyContinue
}
# Helper commands from this repository, appended so they never shadow another
# command.
$helpersPath = Join-Path $HOME '.local/share/helpers/pwsh'
if ((Test-Path -LiteralPath $helpersPath -PathType Container) -and
    ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $helpersPath) {
    $env:PATH = $env:PATH + [System.IO.Path]::PathSeparator + $helpersPath
}
Remove-Variable helpersPath -ErrorAction SilentlyContinue

# One file per tool. The extension check skips names such as local.ps1.bak.*,
# and the leaf check skips dangling links, for example after the clone moves.
$profileSnippets = Join-Path $HOME '.config/powershell/profile.d'
if (Test-Path -LiteralPath $profileSnippets -PathType Container) {
    foreach ($profileSnippet in Get-ChildItem -LiteralPath $profileSnippets -Filter '*.ps1' | Sort-Object Name) {
        if ($profileSnippet.Extension -eq '.ps1' -and (Test-Path -LiteralPath $profileSnippet.FullName -PathType Leaf)) {
            . $profileSnippet.FullName
        }
    }
}
Remove-Variable profileSnippets, profileSnippet -ErrorAction SilentlyContinue
