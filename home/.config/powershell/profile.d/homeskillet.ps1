# homeskillet
# Documentation: Installing in homeskillet's docs/windows.md, and `homeskillet help`.
# homeskillet writes its own completion script, so commands, options, setup step
# names, and installed versions always match the installed version. It needs
# PowerShell 7.3 or later, which passes the empty word after a space. Loaded in
# interactive sessions only, and run only if homeskillet produced it
# successfully; a homeskillet too old to have the completion command fails
# quietly and loads nothing.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = 'homeskillet documents loading its generated completion with Invoke-Expression')]
param()

if ((Get-Module PSReadLine) -and $PSVersionTable.PSVersion -ge [version]'7.3' -and
    (Get-Command homeskillet -CommandType Application -ErrorAction Ignore)) {
    # A homeskillet that cannot start throws; the profile stays silent.
    $homeskilletCompletion = try { homeskillet completion pwsh 2>$null } catch { $null }
    if ($LASTEXITCODE -eq 0 -and $homeskilletCompletion) {
        $homeskilletCompletion | Out-String | Invoke-Expression
    }
    Remove-Variable homeskilletCompletion -ErrorAction Ignore
}
