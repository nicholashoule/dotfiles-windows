# Go
# https://pkg.go.dev/cmd/go#hdr-Environment_variables
# A toolchain from install-golang.ps1 lives in $HOME\.local\share\go (or
# GO_INSTALL_DIR) and goes first on PATH, ahead of one Go's installer put on the
# saved PATH. GOBIN, or else the first GOPATH entry's bin, where `go install`
# puts programs, is appended; relative paths are ignored. Set GOBIN, GOPATH, and
# other settings with `go env -w`, which Go saves outside this repository.
# One `go env` call reads them and the telemetry mode. Go's telemetry (Go 1.23+)
# has no environment switch, so it is turned off with `go telemetry off`, which
# Go saves, and which runs only while telemetry is not already off. A go that
# does not run is ignored, so a broken toolchain cannot break the profile. Both
# run with GOTOOLCHAIN=local, so a go.mod in the directory the session starts
# in cannot make go switch to, and download, another toolchain at startup.
$goBin = Join-Path ($(if ($env:GO_INSTALL_DIR) { $env:GO_INSTALL_DIR } else { Join-Path $HOME '.local/share/go' })) 'bin'
if ((Test-Path -LiteralPath (Join-Path $goBin 'go.exe') -PathType Leaf) -and
    ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $goBin) {
    $env:PATH = $goBin + [System.IO.Path]::PathSeparator + $env:PATH
}
if (Get-Command go -CommandType Application -ErrorAction Ignore) {
    $goToolchain = $env:GOTOOLCHAIN
    $env:GOTOOLCHAIN = 'local'
    try {
        $goEnv = try { @(go env GOBIN GOPATH GOTELEMETRY 2>$null) } catch { @() }
        if ($LASTEXITCODE -eq 0 -and $goEnv.Count -eq 3) {
            $goTools = if ($goEnv[0]) { $goEnv[0] } elseif ($goEnv[1]) {
                Join-Path ($goEnv[1] -split [System.IO.Path]::PathSeparator)[0] 'bin'
            }
            if ($goTools -and [System.IO.Path]::IsPathRooted($goTools) -and
                ($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $goTools) {
                $env:PATH = $env:PATH + [System.IO.Path]::PathSeparator + $goTools
            }
            if ($goEnv[2] -and $goEnv[2] -ne 'off') {
                try { go telemetry off 2>$null | Out-Null } catch { $null = $_ }
            }
        }
    } finally {
        $env:GOTOOLCHAIN = $goToolchain
    }
}
Remove-Variable goBin, goEnv, goTools, goToolchain -ErrorAction Ignore
