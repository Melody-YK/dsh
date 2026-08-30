# DSH one-click startup.
# DSH and the forwarder stay hidden; the connection page is opened at the end.
$ErrorActionPreference = 'Stop'

$toolDir = 'D:\workspace\clawbox-main\dsh-mobile-client'
$logDir = Join-Path $toolDir 'logs'
$tmpDir = Join-Path $env:TEMP 'dsh-mobile-start'
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
$dshHome = Join-Path $env:USERPROFILE '.dsh'
$dailyName = -join @([char]0x65e5, [char]0x5e38, [char]0x4e0d, [char]0x7528)
$dshRoot = Join-Path (Join-Path 'D:\Users\Melody\Desktop' $dailyName) 'deepseek-harness-app'
$nodeExe = 'D:\Apps\DevTools\java\Node.js\node.exe'
$binJs = Join-Path $dshRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$forwarderJs = Join-Path $toolDir 'tools\port-forward.mjs'
$apiForwarderJs = Join-Path $dshHome 'opencode-go-forwarder.cjs'
$runLog = Join-Path $logDir 'start-all.log'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

function Write-RunLog {
    param([string] $Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $runLog -Value "[$stamp] $Message" -Encoding UTF8
}

function Test-ListeningPort {
    param([int] $Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    return $null -ne $connection
}

function Wait-ListeningPort {
    param(
        [int] $Port,
        [int] $TimeoutSeconds = 10
    )
    for ($second = 0; $second -lt $TimeoutSeconds; $second++) {
        if (Test-ListeningPort $Port) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return Test-ListeningPort $Port
}

function Get-LanIPv4 {
    $upNames = @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' } |
            ForEach-Object { $_.Name }
    )
    $candidates = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' -and
                $_.IPAddress -notmatch '^192\.168\.(88|230)\.'
            }
    )
    $connected = @($candidates | Where-Object { $upNames -contains $_.InterfaceAlias })
    if ($connected.Count -eq 0) {
        $connected = $candidates
    }
    $ethernet = $connected | Where-Object { $_.InterfaceAlias -match '以太网|Ethernet' } | Select-Object -First 1
    if ($ethernet) {
        return $ethernet.IPAddress
    }
    $wlan = $connected | Where-Object { $_.InterfaceAlias -eq 'WLAN' } | Select-Object -First 1
    if ($wlan) {
        return $wlan.IPAddress
    }
    return ($connected | Select-Object -First 1).IPAddress
}

function Invoke-Tailscale {
    param([Parameter(Mandatory = $true)][string[]] $TsArgs)
    if (-not (Test-Path -LiteralPath $tsExe)) {
        return [pscustomobject]@{ ExitCode = 1; Text = 'tailscale.exe not found'; Lines = @() }
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $tsExe @TsArgs 2>&1
        $code = $LASTEXITCODE
        $lines = @($output | ForEach-Object { $_.ToString() })
        return [pscustomobject]@{
            ExitCode = $code
            Text = ($lines -join "`n").Trim()
            Lines = $lines
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            Text = $_.Exception.Message
            Lines = @()
        }
    } finally {
        $ErrorActionPreference = $previous
    }
}

try {
    Write-RunLog 'startup requested'

    if (-not (Test-Path -LiteralPath $dshRoot)) {
        throw "DSH root not found: $dshRoot"
    }
    if (-not (Test-Path -LiteralPath $binJs)) {
        throw "DSH entry not found: $binJs"
    }
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nodeCommand) {
            $nodeExe = $nodeCommand.Source
        }
    }
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        throw 'Node.js executable was not found'
    }

    $lanIp = Get-LanIPv4
    if ($lanIp) {
        Write-RunLog "LAN address: $lanIp"
    } else {
        Write-RunLog 'LAN address not detected'
    }

    $tsIp = $null
    $tsDomain = $null
    $tsBackend = $null
    if (Test-Path -LiteralPath $tsExe) {
        $tsIpResult = Invoke-Tailscale -TsArgs @('ip', '-4')
        $candidateIp = $tsIpResult.Lines |
            Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } |
            Select-Object -First 1
        if ($candidateIp) {
            $tsIp = $candidateIp.Trim()
        } elseif ($tsIpResult.Text) {
            Write-RunLog "Tailscale IPv4 unavailable: $($tsIpResult.Text)"
        }

        $tsStatusResult = Invoke-Tailscale -TsArgs @('status', '--json')
        $tsStatusText = $tsStatusResult.Text
        $jsonStart = $tsStatusText.IndexOf('{')
        if ($jsonStart -ge 0) {
            $tsStatusText = $tsStatusText.Substring($jsonStart)
        }
        try {
            $tsStatus = $tsStatusText | ConvertFrom-Json
            $tsBackend = $tsStatus.BackendState
            $tsDomain = $tsStatus.Self.DNSName
        } catch {
            if ($tsStatusText -match '"DNSName"\s*:\s*"([^"]+)"') {
                $tsDomain = $Matches[1]
            }
        }
        if ($tsDomain) {
            $tsDomain = $tsDomain.ToString().Trim().TrimEnd('.')
        }
        if ($tsBackend) {
            Write-RunLog "Tailscale backend: $tsBackend"
        }
    }

    $trustedHosts = @()
    if ($lanIp) {
        $trustedHosts += $lanIp
        $trustedHosts += "${lanIp}:3080"
        $trustedHosts += "${lanIp}:3081"
    }
    if ($tsIp) {
        $trustedHosts += $tsIp
    }
    if ($tsDomain) {
        $trustedHosts += $tsDomain
        $trustedHosts += "${tsDomain}:3080"
        $trustedHosts += "${tsDomain}:3081"
    }
    $trustedHosts = @($trustedHosts | Where-Object { $_ } | Select-Object -Unique)

    $env:DSH_HOME = $dshHome
    if (-not (Test-ListeningPort 3080)) {
        $dshOut = Join-Path $logDir 'dsh-3080.stdout.log'
        $dshErr = Join-Path $logDir 'dsh-3080.stderr.log'
        $dshArgs = @($binJs, 'web', '--host', '127.0.0.1', '--port', '3080')
        foreach ($authority in $trustedHosts) {
            $dshArgs += @('--trusted-host', $authority)
        }
        Start-Process -FilePath $nodeExe -ArgumentList $dshArgs -WorkingDirectory $dshRoot -WindowStyle Hidden -RedirectStandardOutput $dshOut -RedirectStandardError $dshErr | Out-Null
        if (-not (Wait-ListeningPort 3080 15)) {
            throw "DSH failed to listen on port 3080. See $dshErr"
        }
        Write-RunLog "DSH started with $($trustedHosts.Count) trusted authorities"
    } else {
        Write-RunLog 'DSH was already listening on port 3080'
    }

    $fwdUp = Get-NetTCPConnection -LocalPort 3081 -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq '0.0.0.0' } |
        Select-Object -First 1
    if (-not $fwdUp) {
        $fwdOut = Join-Path $logDir 'port-forward.log'
        $fwdErr = Join-Path $logDir 'port-forward.err.log'
        Start-Process -FilePath $nodeExe -ArgumentList @($forwarderJs, '3081', '3080') -WorkingDirectory $toolDir -WindowStyle Hidden -RedirectStandardOutput $fwdOut -RedirectStandardError $fwdErr | Out-Null
        if (-not (Wait-ListeningPort 3081 10)) {
            throw "Port forwarder failed to listen on port 3081. See $fwdErr"
        }
        Write-RunLog 'port forwarder started on 0.0.0.0:3081'
    } else {
        Write-RunLog 'port forwarder was already listening on port 3081'
    }

    if (-not (Test-ListeningPort 18890)) {
        if (Test-Path -LiteralPath $apiForwarderJs) {
            $apiFwdOut = Join-Path $logDir 'opencode-go-forwarder.out.log'
            $apiFwdErr = Join-Path $logDir 'opencode-go-forwarder.err.log'
            Start-Process -FilePath $nodeExe -ArgumentList @($apiForwarderJs) -WorkingDirectory $dshHome -WindowStyle Hidden -RedirectStandardOutput $apiFwdOut -RedirectStandardError $apiFwdErr | Out-Null
            if (-not (Wait-ListeningPort 18890 10)) {
                Write-RunLog "API forwarder failed to listen on 18890. See $apiFwdErr"
            } else {
                Write-RunLog 'API forwarder started on 127.0.0.1:18890'
            }
        } else {
            Write-RunLog 'API forwarder script not found, skipped'
        }
    } else {
        Write-RunLog 'API forwarder was already listening on port 18890'
    }

    if (Test-Path -LiteralPath $tsExe) {
        if ($tsIp) {
            $serveResult = Invoke-Tailscale -TsArgs @('serve', '--bg', '--tcp=3081', '3080')
            if ($serveResult.Text) {
                $serveResult.Text | Add-Content -LiteralPath $runLog -Encoding UTF8
            }
            if ($serveResult.ExitCode -ne 0) {
                Write-RunLog "Tailscale serve skipped: $($serveResult.Text)"
            } else {
                Write-RunLog 'Tailscale serve configured: TCP 3081 -> 127.0.0.1:3080'
            }
        } else {
            Write-RunLog 'Tailscale serve skipped: no current Tailscale IPs'
        }
    }

    $magicUrl = if ($tsDomain) { "http://${tsDomain}:3081" } else { $null }
    $remoteUrl = if ($tsIp -and -not $tsDomain) { "http://${tsIp}:3081" } else { $null }
    $lanUrl = if ($lanIp) { "http://${lanIp}:3081" } else { $null }
    $primaryUrl = if ($magicUrl) { $magicUrl } elseif ($remoteUrl) { $remoteUrl } else { $lanUrl }

    $qrSrc = ''
    if ($primaryUrl) {
        $qrSrc = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=' + [uri]::EscapeDataString($primaryUrl)
    }

    $html = @"
<!doctype html>
<html><head><meta charset="utf-8"><title>DSH Mobile &#36830;&#25509;</title></head>
<body style="font-family:'Segoe UI',sans-serif;text-align:center;padding:40px 24px;">
<h1 style="margin:0 0 8px;">DSH Mobile &#36830;&#25509;</h1>
<p style="color:#666;margin:0 0 20px;">&#25163;&#26426; DSH Mobile &#8594; &#26381;&#21153;&#22320;&#22336; &#8594; &#25195;&#25551;&#19979;&#26041;&#20108;&#32500;&#30721;</p>
$(if ($magicUrl) { "<p style='font-size:26px;color:#4D6BFE;margin:0 0 8px;user-select:all;'>$magicUrl</p>" } else { '' })
$(if ($magicUrl) { "<p style='color:#888;font-size:13px;margin:0 0 20px;'>&#36825;&#26159; MagicDNS &#31283;&#23450;&#22320;&#22336;</p>" } else { '' })
$(if (-not $magicUrl -and $primaryUrl) { "<p style='font-size:26px;color:#4D6BFE;margin:0 0 20px;user-select:all;'>$primaryUrl</p>" } else { '' })
$(if ($qrSrc) { "<img src='$qrSrc' width='280' height='280' alt='QR code'>" } else { '<p>No address was detected.</p>' })
$(if ($lanUrl -and $primaryUrl -and $lanUrl -ne $primaryUrl) { "<p style='color:#999;margin-top:16px;'>&#21516; WiFi: <span style='user-select:all;'>$lanUrl</span></p>" } else { '' })
$(if (-not $tsIp) { "<p style='color:#c0392b;margin-top:16px;'>Tailscale &#26410;&#22312;&#32447;&#65292;&#24050;&#25913;&#29992;&#23616;&#22495;&#32593;&#22320;&#22336;&#12290;&#25171;&#24320;&#20195;&#29702;&#24182;&#30331;&#24405; Tailscale &#21518;&#20877;&#36319;&#19968;&#27425;&#21551;&#21160;&#21363;&#21487;&#12290;</p>" } else { '' })
<p style="color:#999;margin-top:20px;">&#25195;&#23436;&#21518;&#20851;&#38381;&#27492;&#39029;&#38754;&#21363;&#21487;&#12290;</p>
</body></html>
"@

    $htmlFile = Join-Path $tmpDir 'dsh-connect.html'
    [System.IO.File]::WriteAllText($htmlFile, $html, (New-Object System.Text.UTF8Encoding($true)))
    Start-Process -FilePath $htmlFile

    if ($primaryUrl) {
        try {
            Set-Clipboard -Value $primaryUrl
        } catch {
            Write-RunLog 'clipboard update skipped'
        }
    }
    Write-RunLog "startup completed: $primaryUrl"
} catch {
    $detail = ($_ | Out-String).Trim()
    Write-RunLog "startup failed: $detail"
    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList $runLog
    } catch {
    }
    exit 1
}
