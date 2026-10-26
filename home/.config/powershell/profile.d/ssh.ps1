# OpenSSH
# https://learn.microsoft.com/windows-server/administration/openssh/openssh_keymanagement
# Windows' OpenSSH agent is a service that keeps keys until it restarts. Set it
# to start at boot once, from an elevated shell:
#   Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent
# Git for Windows uses its own ssh, which cannot see that service; point Git at
# Windows' OpenSSH once:
#   git config --global core.sshCommand C:/Windows/System32/OpenSSH/ssh.exe

# Add-SshKey [PATH] adds a key to the agent unless it already holds one: the key
# at PATH, or else each of ~\.ssh\id_ed25519, id_rsa, and id_ecdsa that exists.
function Add-SshKey {
    param([string]$KeyPath)
    if (-not (Get-Command ssh-add -ErrorAction SilentlyContinue)) {
        Write-Warning 'ssh-add is not available: add the OpenSSH Client optional feature.'
        return
    }
    # ssh-add -l exits 0 when the agent holds keys, 1 when it holds none, and 2
    # when it cannot reach the agent.
    ssh-add -l *> $null
    if ($LASTEXITCODE -eq 0) { return }
    if ($LASTEXITCODE -ne 1) {
        Write-Warning 'The OpenSSH agent is not running. From an elevated shell: Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent'
        return
    }
    $keys = if ($KeyPath) { @($KeyPath) } else {
        foreach ($name in 'id_ed25519', 'id_rsa', 'id_ecdsa') {
            $key = Join-Path $HOME ".ssh/$name"
            if (Test-Path -LiteralPath $key) { $key }
        }
    }
    foreach ($key in $keys) { ssh-add $key }
}
