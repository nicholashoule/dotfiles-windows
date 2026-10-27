# PSReadLine
# https://learn.microsoft.com/powershell/module/psreadline/about/about_psreadline
# Line editing, history, and predictions. It runs first because setting EditMode
# resets every key binding, which would undo bindings that later files, such as
# the Oh My Posh prompt, add. The console loads PSReadLine before profiles only in
# interactive sessions, so this leaves `pwsh -Command` alone.
# History is saved when the session exits. Predictions come from history and any
# predictor plugins, as a list when the window has room for one (50 columns by 5
# rows) and inline otherwise. Tab shows every completion in a menu.
if (Get-Module PSReadLine) {
    $psReadLineView = 'InlineView'
    if ($Host.UI.RawUI.WindowSize.Width -ge 50 -and $Host.UI.RawUI.WindowSize.Height -ge 5) {
        $psReadLineView = 'ListView'
    }
    $psReadLineOptions = @{
        EditMode            = 'Windows'
        HistorySaveStyle    = 'SaveAtExit'
        PredictionSource    = 'HistoryAndPlugin'
        PredictionViewStyle = $psReadLineView
        Colors              = @{
            Command   = '#00afff'
            Parameter = '#ffaf00'
            String    = '#5fd700'
        }
    }
    Set-PSReadLineOption @psReadLineOptions
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Remove-Variable psReadLineView, psReadLineOptions -ErrorAction Ignore
}
