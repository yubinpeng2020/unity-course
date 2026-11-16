# ================================================
#  数字产品设计（Unity）课件 - 局域网访问服务
#  用 Windows 自带的 PowerShell，不用装任何东西
#  由 启动课件服务.bat / start_server.bat 调用
#  用法：powershell -ExecutionPolicy Bypass -File server.ps1 [-Port 8000]
# ================================================

param([int]$Port = 8000)

$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $root) { $root = (Get-Location).Path }
$root = (Resolve-Path $root).Path

# ---------- 挑一个真正能给学生用的 IP ----------
# 不能随便取第一个：装了 VMware / VirtualBox / WSL / VPN 的机器，
# 取到的往往是虚拟网卡（192.168.56.1 之类），学生当然连不上。
function Test-VirtualName([string]$name) {
    if (-not $name) { return $true }
    $n = $name.ToLower()
    $keys = @('vmware','virtualbox','vethernet','hyper-v','loopback','bluetooth',
              'tap-','openvpn','wireguard','docker','wsl','npcap','zerotier','tailscale')
    foreach ($k in $keys) { if ($n.Contains($k)) { return $true } }
    return $false
}

$cand = @()
try {
    $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric
    foreach ($r in $routes) {
        try {
            $ips = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
        } catch { continue }
        foreach ($a in $ips) {
            if ($a.IPAddress -notlike '169.254*' -and $a.IPAddress -ne '127.0.0.1') {
                $cand += [pscustomobject]@{ IP = $a.IPAddress; Alias = $a.InterfaceAlias }
            }
        }
    }
} catch { }

if ($cand.Count -eq 0) {
    try {
        foreach ($a in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue) {
            if ($a.IPAddress -notlike '169.254*' -and $a.IPAddress -ne '127.0.0.1') {
                $cand += [pscustomobject]@{ IP = $a.IPAddress; Alias = $a.InterfaceAlias }
            }
        }
    } catch { }
}

$ip = ""
foreach ($c in $cand) {
    if (-not (Test-VirtualName $c.Alias)) { $ip = $c.IP; break }
}
if (-not $ip -and $cand.Count -gt 0) { $ip = $cand[0].IP }

# 最后的兜底：老系统没有 Get-NetIPAddress，直接解析 ipconfig
if (-not $ip -or $ip -eq "127.0.0.1") {
    try {
        $lines = & ipconfig 2>$null
        foreach ($l in $lines) {
            if ($l -match "IPv4") {
                $m = [regex]::Match($l, "(\d{1,3}(\.\d{1,3}){3})")
                if ($m.Success) {
                    $c = $m.Groups[1].Value
                    if ($c -notlike "169.254*" -and $c -ne "127.0.0.1") { $ip = $c; break }
                }
            }
        }
    } catch { }
}
if (-not $ip) { $ip = "127.0.0.1" }

Write-Host ""
Write-Host "  =============================================="
Write-Host "   数字产品设计（Unity）课件 - 局域网访问服务"
Write-Host "  =============================================="
Write-Host "   学生访问：  http://$($ip):$Port/"
Write-Host "   本机测试：  http://127.0.0.1:$Port/"
Write-Host "  ----------------------------------------------"
Write-Host "   本机检测到的可用地址："
foreach ($c in $cand) {
    $mark = "  "
    if ($c.IP -eq $ip) { $mark = "->" }
    $tag = ""
    if (Test-VirtualName $c.Alias) { $tag = "  (虚拟网卡，别用这个)" }
    Write-Host "   $mark $($c.IP)   [$($c.Alias)]$tag"
}
Write-Host "   学生连不上时：先把上面「本机测试」链接在自己电脑上打开，"
Write-Host "   能开说明服务没问题，是防火墙 / 不在同一个 Wi-Fi。"
Write-Host "  ----------------------------------------------"

# ---------- 防火墙：顺手放行 8000（需要管理员，失败也不影响本机） ----------
$fwOK = $false
try {
    $chk = (& netsh advfirewall firewall show rule name="课件局域网8000" 2>$null) -join "`n"
    if ($chk -and $chk -notmatch "没有与指定条件相符的规则" -and $chk -notmatch "No rules match") { $fwOK = $true }
} catch { }
if (-not $fwOK) {
    try {
        & netsh advfirewall firewall add rule name="课件局域网8000" dir=in action=allow protocol=TCP localport=$Port 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $fwOK = $true }
    } catch { }
}
if ($fwOK) {
    Write-Host "   防火墙：已放行 TCP $Port"
} else {
    Write-Host "   防火墙：未放行（本机能看，学生机可能打不开）"
    Write-Host "           右键这个 bat -> 以管理员身份运行，可自动放行"
}
Write-Host "  ----------------------------------------------"
Write-Host ""

# ---------- 起服务 ----------
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
try {
    $listener.Start()
} catch {
    Write-Host "  [失败] 端口 $Port 起不来：$($_.Exception.Message)"
    Write-Host "  多半是端口被占用，另开一个窗口执行：netstat -ano | findstr $Port"
    Read-Host "  按回车退出"
    exit 1
}

Write-Host "  服务已启动，正在等待连接（关闭本窗口 = 停止服务）"
Write-Host ""

function Get-ContentType([string]$ext) {
    switch ($ext) {
        ".html" { return "text/html; charset=utf-8" }
        ".htm"  { return "text/html; charset=utf-8" }
        ".css"  { return "text/css; charset=utf-8" }
        ".js"   { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".png"  { return "image/png" }
        ".jpg"  { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".gif"  { return "image/gif" }
        ".svg"  { return "image/svg+xml" }
        ".ico"  { return "image/x-icon" }
        ".woff2" { return "font/woff2" }
        ".woff" { return "font/woff" }
        ".ttf"  { return "font/ttf" }
        ".pdf"  { return "application/pdf" }
        ".mp4"  { return "video/mp4" }
        default { return "application/octet-stream" }
    }
}

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
    } catch {
        break
    }

    # 关键：浏览器会先开一条空连接探路（preconnect），不发数据。
    # 不设超时的话，这一条就能把整个单线程服务卡死，表现就是"链接一直转圈"。
    try {
        $client.ReceiveTimeout = 5000
        $client.SendTimeout = 15000
    } catch { }

    $stream = $null
    try {
        $stream = $client.GetStream()

        $buffer = New-Object byte[] 8192
        $sb = New-Object System.Text.StringBuilder
        $got = $false
        while (-not $got) {
            $n = $stream.Read($buffer, 0, $buffer.Length)
            if ($n -le 0) { break }
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $n))
            if ($sb.ToString().Contains("`r`n`r`n")) { $got = $true }
            if ($sb.Length -gt 32768) { break }
        }

        $req = $sb.ToString()
        $requestLine = ($req -split "`r`n")[0]
        if (-not $requestLine) { continue }

        $parts = $requestLine -split " "
        if ($parts.Length -lt 2) { continue }
        $method = $parts[0].ToUpper()
        $path = $parts[1]

        # 去掉查询串 / 锚点，解百分号编码
        $path = $path.Split("?")[0].Split("#")[0]
        if (-not $path -or $path -eq "/") { $path = "/index.html" }
        $path = [System.Uri]::UnescapeDataString($path).TrimStart("/")
        $path = $path -replace "/", "\"

        # 自带一个探活地址，方便排查"到底有没有连上"
        if ($path -eq "__ping") {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("ok")
            $h = "HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($msg.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::UTF8.GetBytes($h)
            $stream.Write($hb, 0, $hb.Length)
            $stream.Write($msg, 0, $msg.Length)
            continue
        }

        $file = Join-Path $root $path
        # 防越权：不允许 .. 跳出课件目录
        $full = ""
        try { $full = [System.IO.Path]::GetFullPath($file) } catch { $full = "" }
        if (-not $full -or -not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
            $h = "HTTP/1.1 403 Forbidden`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($msg.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::UTF8.GetBytes($h)
            $stream.Write($hb, 0, $hb.Length)
            if ($method -ne "HEAD") { $stream.Write($msg, 0, $msg.Length) }
            Write-Host ("  [403] {0}" -f $path)
            continue
        }

        # 目录自动找 index.html
        if (Test-Path $full -PathType Container) {
            $full = Join-Path $full "index.html"
        }

        if (Test-Path $full -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $ct = Get-ContentType ([System.IO.Path]::GetExtension($full).ToLower())
            $h = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::UTF8.GetBytes($h)
            $stream.Write($hb, 0, $hb.Length)
            if ($method -ne "HEAD") { $stream.Write($bytes, 0, $bytes.Length) }
            $who = ""
            try { $who = $client.Client.RemoteEndPoint.Address.ToString() } catch { }
            if ($who -and $who -ne "127.0.0.1") { Write-Host ("  [{0}] {1}" -f $who, $path) }
        } else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: " + $path)
            $h = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($msg.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::UTF8.GetBytes($h)
            $stream.Write($hb, 0, $hb.Length)
            if ($method -ne "HEAD") { $stream.Write($msg, 0, $msg.Length) }
            Write-Host ("  [404] {0}" -f $path)
        }
    } catch {
        # 超时 / 客户端半路断开都是常态，不打印堆栈
        $msg = $_.Exception.Message
        if ($msg -notmatch "超时|timed out|已中止|aborted|forced|远程主机") {
            Write-Host ("  [跳过] " + $msg)
        }
    } finally {
        if ($stream) { try { $stream.Close() } catch { } }
        if ($client) { try { $client.Close() } catch { } }
    }
}

Write-Host ""
Write-Host "  服务已停止。"
