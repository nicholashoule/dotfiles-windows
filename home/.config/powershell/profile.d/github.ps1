# GitHub: the GITHUB_TOKEN personal access token
# https://docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
# Builds that download dependencies from private repositories, such as a
# Makefile, read GITHUB_TOKEN, a token with access to those repositories.
# Set-GitHubToken saves it in your user environment variables, so it never sits
# in a file here or in local.ps1. Windows stores those unencrypted in the
# registry and passes them to every program you start, so give the token only
# the access the builds need. The GitHub CLI (gh) also reads it, ahead of the
# login `gh auth login` stores (`gh help environment`): while it is set, gh acts
# with the token's access, and `gh auth login` refuses to run. gh's telemetry is
# off through DO_NOT_TRACK, which profile.ps1 sets.

# Set-GitHubToken (set-gh-token) asks for the token without echoing it and saves
# it as GITHUB_TOKEN, for this session and the programs Windows starts from now
# on; other open terminals keep their old value until restarted. An empty answer
# changes nothing. -Remove deletes it from both places.
function Set-GitHubToken {
    param([switch]$Remove)
    if ($Remove) {
        [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $null, 'User')
        Remove-Item Env:GITHUB_TOKEN -ErrorAction Ignore
        'Removed GITHUB_TOKEN from your user environment variables and this session.'
        return
    }
    $secure = Read-Host 'GitHub token' -AsSecureString
    $token = [Net.NetworkCredential]::new('', $secure).Password.Trim()
    if (-not $token) {
        Write-Warning 'No token entered; GITHUB_TOKEN is unchanged.'
        return
    }
    [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $token, 'User')
    $env:GITHUB_TOKEN = $token
    'Saved GITHUB_TOKEN in your user environment variables and this session.'
}
Set-Alias set-gh-token Set-GitHubToken
