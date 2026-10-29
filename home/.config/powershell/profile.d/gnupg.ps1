# GnuPG
# https://www.gnupg.org/documentation/manuals/gnupg/
# Helpers for signing Git commits; each needs gpg on PATH, which tools.psd1
# installs. new-gpg-key -h and git-sign-key -h print examples.
#   new-gpg-key [-Name N] [-Email E] [-Years 1|2|3|5|10]  create an Ed25519 signing key
#   gpg-key-1y, gpg-key-5y, gpg-key-10y                  the same, with that expiry
#   gpg-keyid [ID], gpg-keyid-short [ID]                 list secret key IDs
#   gpg-pub [ID] [-Clipboard], gpg-pub-copy [ID]         print or copy public keys
#   git-sign-key [-KeyId K | -Email E] [-Local]          make Git sign commits

# New-GpgSigningKey (new-gpg-key) creates an Ed25519 signing key, by default for
# Git's author identity variables and with a one-year expiry.
function New-GpgSigningKey {
    param(
        [Alias('h')]
        [switch]$Help,
        [string]$Name = $(if ($env:GIT_AUTHOR_NAME) { $env:GIT_AUTHOR_NAME } else { $env:GIT_COMMITTER_NAME }),
        [string]$Email = $(if ($env:GIT_AUTHOR_EMAIL) { $env:GIT_AUTHOR_EMAIL } else { $env:GIT_COMMITTER_EMAIL }),
        [ValidateSet(1, 2, 3, 5, 10)]
        [int]$Years = 1
    )
    if ($Help) {
        'Usage: new-gpg-key [-Name <name>] [-Email <email>] [-Years 1|2|3|5|10]'
        ''
        'Name and Email default to GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL, then'
        'GIT_COMMITTER_NAME and GIT_COMMITTER_EMAIL. Examples:'
        '  new-gpg-key -Name "Example User" -Email "user@example.com" -Years 5'
        '  gpg --quick-generate-key "Example User <user@example.com>" ed25519 sign 1y'
        ''
        'Then find the key ID with gpg-keyid, and sign commits with git-sign-key.'
        return
    }
    if (-not (Get-Command gpg -ErrorAction Ignore)) {
        Write-Warning 'gpg is not available: install it with winget install --id GnuPG.GnuPG --exact.'
        return
    }
    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Email)) {
        Write-Warning 'No name or email: pass -Name and -Email, or set GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL.'
        return
    }
    gpg --quick-generate-key "$Name <$Email>" ed25519 sign "${Years}y"
}
Set-Alias new-gpg-key New-GpgSigningKey
function New-GpgSigningKey1Y { New-GpgSigningKey -Years 1 }
function New-GpgSigningKey5Y { New-GpgSigningKey -Years 5 }
function New-GpgSigningKey10Y { New-GpgSigningKey -Years 10 }
Set-Alias gpg-key-1y New-GpgSigningKey1Y
Set-Alias gpg-key-5y New-GpgSigningKey5Y
Set-Alias gpg-key-10y New-GpgSigningKey10Y

# Get-GpgPublicKey (gpg-pub) prints the armored public key for an identity (an
# email, user ID, or key ID), or every public key without one; -Clipboard copies
# it instead. Copy-GpgPublicKey (gpg-pub-copy) is gpg-pub -Clipboard.
function Get-GpgPublicKey {
    param(
        [string]$Identity,
        [Alias('c')]
        [switch]$Clipboard
    )
    if (-not (Get-Command gpg -ErrorAction Ignore)) {
        Write-Warning 'gpg is not available: install it with winget install --id GnuPG.GnuPG --exact.'
        return
    }
    $exportArgs = @('--armor', '--export')
    if (-not [string]::IsNullOrWhiteSpace($Identity)) { $exportArgs += $Identity }
    $publicKey = gpg @exportArgs
    if (-not $Clipboard) { return $publicKey }
    if ([string]::IsNullOrWhiteSpace(($publicKey -join "`n"))) {
        Write-Warning 'gpg exported no public key: check the identity.'
        return
    }
    $publicKey | Set-Clipboard
    Write-Information 'Public key copied to the clipboard.' -InformationAction Continue
}
Set-Alias gpg-pub Get-GpgPublicKey
function Copy-GpgPublicKey {
    param([string]$Identity)
    Get-GpgPublicKey -Identity $Identity -Clipboard
}
Set-Alias gpg-pub-copy Copy-GpgPublicKey

# Get-GpgKeyId (gpg-keyid) lists secret keys with long key IDs, the form
# git-sign-key wants, for one identity or all; -Short (gpg-keyid-short) lists
# 8-character IDs.
function Get-GpgKeyId {
    param(
        [string]$Identity,
        [switch]$Short
    )
    if (-not (Get-Command gpg -ErrorAction Ignore)) {
        Write-Warning 'gpg is not available: install it with winget install --id GnuPG.GnuPG --exact.'
        return
    }
    $format = if ($Short) { 'short' } else { 'long' }
    $listArgs = @('--list-secret-keys', "--keyid-format=$format")
    if (-not [string]::IsNullOrWhiteSpace($Identity)) { $listArgs += $Identity }
    gpg @listArgs 2>$null
}
Set-Alias gpg-keyid Get-GpgKeyId
function Get-GpgKeyIdShort {
    param([string]$Identity)
    Get-GpgKeyId -Identity $Identity -Short
}
Set-Alias gpg-keyid-short Get-GpgKeyIdShort

# Set-GitGpgSigningKey (git-sign-key) makes Git sign commits with a GnuPG key,
# globally or with -Local for the current repository: the key from -KeyId, or
# piped from gpg-keyid, or else the first secret key, for -Email if given. It
# records gpg's full path, so Git finds it whatever PATH Git starts with.
function Set-GitGpgSigningKey {
    [CmdletBinding()]
    param(
        [Alias('h')]
        [switch]$Help,
        # A bare key ID, or the lines gpg-keyid and gpg-keyid-short print.
        [Parameter(ValueFromPipeline)]
        [string]$KeyId,
        [string]$Email,
        [switch]$Local
    )
    begin {
        $keyLines = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($KeyId) { $keyLines.Add($KeyId) }
    }
    end {
        if ($Help) {
            'Usage: git-sign-key [-KeyId <key ID>] [-Email <email>] [-Local]'
            ''
            'Examples:'
            '  git-sign-key -KeyId ABCDEF1234567890'
            '  git-sign-key -Email user@example.com'
            '  git-sign-key -Local -Email user@example.com'
            '  gpg-keyid user@example.com | git-sign-key'
            return
        }
        foreach ($tool in 'git', 'gpg') {
            if (-not (Get-Command $tool -ErrorAction Ignore)) {
                Write-Warning "$tool is not available on PATH."
                return
            }
        }

        # gpg-keyid prints lines such as "sec   ed25519/ABCD1234 2024-01-01 [SC]";
        # a bare hexadecimal ID works too.
        $signingKey = $null
        if ($keyLines.Count -gt 0) {
            $keyMatch = [regex]::Match(($keyLines -join "`n"), 'sec\s+\S+/([0-9A-Fa-f]+)')
            if ($keyMatch.Success) {
                $signingKey = $keyMatch.Groups[1].Value
            } elseif ($keyLines[0].Trim() -match '^[0-9A-Fa-f]{8,}$') {
                $signingKey = $keyLines[0].Trim()
            }
        }
        if (-not $signingKey) {
            $listArgs = @('--list-secret-keys', '--keyid-format=long')
            if (-not [string]::IsNullOrWhiteSpace($Email)) { $listArgs += $Email }
            $keyLine = gpg @listArgs 2>$null | Select-String 'sec\s+\S+/([0-9A-Fa-f]+)' | Select-Object -First 1
            if (-not $keyLine) {
                Write-Warning 'No GnuPG secret key found: create one with new-gpg-key.'
                return
            }
            $signingKey = $keyLine.Matches[0].Groups[1].Value
        }

        $scope = if ($Local) { '--local' } else { '--global' }
        $settings = [ordered]@{
            'user.signingkey' = $signingKey
            'commit.gpgsign'  = 'true'
            'gpg.program'     = (Get-Command gpg).Source
        }
        foreach ($setting in $settings.GetEnumerator()) {
            git config $scope $setting.Key $setting.Value
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "git config $scope $($setting.Key) failed; -Local works only inside a repository."
                return
            }
        }
        Write-Information "Git now signs commits ($($scope.TrimStart('-'))) with key $signingKey." -InformationAction Continue
    }
}
Set-Alias git-sign-key Set-GitGpgSigningKey
