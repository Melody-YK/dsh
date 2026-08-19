# DSH one-click startup (silent version):
# - DSH web + forwarder run fully hidden (logs written to files)
# - only ONE window pops up at the end: a connection page (URL + QR code)
$ErrorActionPreference = 'Continue'
$dshRoot = 'D:\Users\Melody\Desktop\日常不用\deepseek-harness-app'
$binJs   = Join-Path $dshRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$toolDir = 'D:\workspace\clawbox-main\dsh-mobile-client'
$logDir  = Join-Path $toolDir 'logs'
$tsExe   = 'C:\Program Files\Tailscale\tailscale.exe'
$tmpDir  = Join-Path $env:TEMP 'dsh-mobile-start'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

# --- 1. Detect LAN IP (WLAN preferred) ---
$wlan = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'WLAN' -ErrorAction SilentlyContinue | Select-Object -First 1
$lanIp = $wlan.IPAddress
if (-not $lanIp) {
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } |
        Where-Object { $_.IPAddress -notmatch '^192\.168\.(88|230)\.' } |
        Select-Object -First 1).IPAddress
}

# --- 2. Detect Tailscale IP ---
$tsIp = $null
if (Test-Path $tsExe) {
    $tsIp = (& $tsExe ip -4 2>$null | Select-Object -First 1)
}

# --- 3. Start DSH web fully hidden (skip if already listening) ---
$dshUp = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
if ($dshUp) {
    # already running
} else {
    $trusted = ''
    if ($lanIp) { $trusted += " --trusted-host $lanIp`:3080 --trusted-host $lanIp`:3081" }
    if ($tsIp)   { $trusted += " --trusted-host $tsIp" }
    $bat = Join-Path $tmpDir 'dsh-web.bat'
    $logFile = Join-Path $logDir 'dsh-3080.log'
    $content = "@echo off`r`ncd /d `"$dshRoot`"`r`nnode `"$binJs`" web --host 127.0.0.1 --port 3080$trusted >> `"$logFile`" 2>&1`r`n"
    [System.IO.File]::WriteAllText($bat, $content, [System.Text.Encoding]::GetEncoding('GBK'))
    Start-Process -FilePath $bat -WindowStyle Hidden
    Start-Sleep -Seconds 4
}

# --- 4. Start LAN forwarder fully hidden ---
$fwdUp = Get-NetTCPConnection -LocalPort 3081 -State Listen -ErrorAction SilentlyContinue | Where-Object LocalAddress -eq '0.0.0.0'
if (-not $fwdUp) {
    $fwdOut = Join-Path $logDir 'port-forward.log'
    $fwdErr = Join-Path $logDir 'port-forward.err.log'
    Start-Process -FilePath 'node' -ArgumentList "$toolDir\tools\port-forward.mjs", '3081', '3080' `
        -WorkingDirectory $toolDir -WindowStyle Hidden `
        -RedirectStandardOutput $fwdOut -RedirectStandardError $fwdErr
    Start-Sleep -Seconds 2
}

# --- 5. Ensure Tailscale serve (idempotent) ---
if (Test-Path $tsExe) {
    & $tsExe serve --bg --tcp=3081 3080 2>$null | Out-Null
}

# --- 6. Build the ONE connection page (URL + QR) and open it ---
$remoteUrl = if ($tsIp) { "http://${tsIp}:3081" } else { $null }
$lanUrl = if ($lanIp) { "http://${lanIp}:3081" } else { $null }
$primaryUrl = if ($remoteUrl) { $remoteUrl } else { $lanUrl }

$qrSrc = ''
if ($primaryUrl) {
    $qrSrc = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=' + [uri]::EscapeDataString($primaryUrl)
}

$html = @"
<!doctype html>
<html><head><meta charset="utf-8"><title>DSH Mobile 连接</title></head>
<body style="font-family:'Segoe UI',sans-serif;text-align:center;padding:40px 24px;">
<h1 style="margin:0 0 8px;">DSH Mobile 连接</h1>
<p style="color:#666;margin:0 0 20px;">手机 DSH Mobile → 服务地址 → 点扫码图标，扫下面的二维码</p>
$(if ($primaryUrl) { "<p style='font-size:26px;color:#4D6BFE;margin:0 0 20px;user-select:all;'>$primaryUrl</p>" } else { '' })
$(if ($qrSrc) { "<img src='$qrSrc' width='280' height='280' alt='二维码加载失败，请手动输入上面地址'>" } else { '<p>未能获取地址，请检查网络后重试</p>' })
$(if ($lanUrl -and $remoteUrl -and $lanUrl -ne $remoteUrl) { "<p style='color:#999;margin-top:16px;'>同一 WiFi 备用：<span style='user-select:all;'>$lanUrl</span></p>" } else { '' })
<p style="color:#999;margin-top:20px;">扫完关掉这个页面即可，服务已在后台运行。</p>
</body></html>
"@

$htmlFile = Join-Path $tmpDir 'dsh-connect.html'
[System.IO.File]::WriteAllText($htmlFile, $html, (New-Object System.Text.UTF8Encoding($false)))
Start-Process $htmlFile

# --- 7. Copy URL to clipboard (best-effort) ---
if ($primaryUrl) {
    try { Set-Clipboard -Value $primaryUrl } catch {}
}
