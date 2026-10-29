# PSScriptAnalyzer settings for every PowerShell file in this repository.
# https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer
# scripts/check-powershell.sh, beside this file, lints with them. To see the same
# findings in VS Code, set the PowerShell extension's
# powershell.scriptAnalysis.settingsPath to scripts/PSScriptAnalyzerSettings.psd1.
# Suppress a rule for one file or function with a SuppressMessageAttribute whose
# Justification says why; exclude it here only when it fits nothing in the
# repository.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # It asks for -WhatIf and -Confirm on every function whose verb could
        # change state, such as Set- or Update-. The profile's are interactive
        # shortcuts that do what their names say, and the helpers' are internal.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
