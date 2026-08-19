# DSH one-click shutdown: kill DSH web + LAN forwarder + disable Tailscale serve.
$ErrorActionPreference = 'Continue'
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'

Write-Host '===== DSH one-click shutdown ====='

$killed = 0

# 1. Kill DSH web node processes (command line mentions dsh bin.js)
Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'dsh' -and $_.CommandLine -match 'bin\.js' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "stopped DSH web (PID $($_.ProcessId))"
        $killed++
    }

# 2. Kill LAN forwarder (node port-forward.mjs)
Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'port-forward\.mjs' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "stopped forwarder (PID $($_.ProcessId))"
        $killed++
    }

# 3. Disable Tailscale serve
if (Test-Path $tsExe) {
    & $tsExe serve --tcp=3081 off 2>$null | Out-Null
    Write-Host 'tailscale serve disabled'
}

if ($killed -eq 0) {
    Write-Host 'no running DSH/forwarder processes found'
}
Write-Host '===== done ====='
