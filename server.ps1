# ================================================
#  C# 课件局域网服务 - PowerShell 静态服务器
#  （Windows 自带 PowerShell，无需安装任何软件）
#  用法：由 start_server.bat / 启动课件服务.bat 自动调用
# ================================================

$ErrorActionPreference = "Stop"
$port = 8000
$root = $PSScriptRoot

# 获取本机 IPv4（跳过虚拟网卡）
$ip = ""
$addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
foreach ($a in $addrs) {
    if ($a.IPAddress -notlike "169.254*" -and $a.IPAddress -ne "127.0.0.1") {
        $ip = $a.IPAddress
        break
    }
}
if (-not $ip) { $ip = "127.0.0.1" }

Write-Host ""
Write-Host "  C# 课件 - 局域网访问服务"
Write-Host "  -------------------------------------"
Write-Host "  本机 IP:   $ip"
Write-Host "  学生访问:  http://$ip`:$port/"
Write-Host "  本机测试:  http://127.0.0.1:$port/"
Write-Host "  关闭本窗口 = 停止服务"
Write-Host ""

# TcpListener 绑定 8000 端口（普通用户即可，无需管理员）
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
try {
    $listener.Start()
} catch {
    Write-Host "[错误] 端口 $port 启动失败：$($_.Exception.Message)"
    Write-Host "可能原因：端口被占用。可用命令查看：netstat -ano | findstr 8000"
    Read-Host "按回车退出"
    exit 1
}

Write-Host "  服务已启动，等待访问..."
Write-Host ""

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
    } catch {
        break
    }
    $stream = $client.GetStream()
    try {
        # 读取 HTTP 请求头（直到空行）
        $buffer = New-Object byte[] 8192
        $sb = New-Object System.Text.StringBuilder
        $received = $false
        while (-not $received) {
            $n = $stream.Read($buffer, 0, $buffer.Length)
            if ($n -le 0) { break }
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $n))
            if ($sb.ToString().Contains("`r`n`r`n")) { $received = $true }
        }
        $requestLine = ($sb.ToString() -split "`r`n")[0]
        if (-not $requestLine) { continue }

        # 解析请求路径
        $path = ($requestLine -split " ")[1]
        if (-not $path -or $path -eq "/") { $path = "/index.html" }
        $path = [System.Uri]::UnescapeDataString($path).TrimStart("/")
        $file = Join-Path $root $path

        if (Test-Path $file -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file).ToLower()
            switch ($ext) {
                ".html"  { $ct = "text/html; charset=utf-8" }
                ".css"   { $ct = "text/css; charset=utf-8" }
                ".js"    { $ct = "application/javascript; charset=utf-8" }
                ".json"  { $ct = "application/json; charset=utf-8" }
                ".png"   { $ct = "image/png" }
                ".jpg"   { $ct = "image/jpeg" }
                ".gif"   { $ct = "image/gif" }
                ".svg"   { $ct = "image/svg+xml" }
                ".ico"   { $ct = "image/x-icon" }
                ".woff2" { $ct = "font/woff2" }
                ".woff"  { $ct = "font/woff" }
                ".ttf"   { $ct = "font/ttf" }
                default  { $ct = "application/octet-stream" }
            }
            $header = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bytes, 0, $bytes.Length)
            Write-Host ("  [{0}] {1}" -f $client.Client.RemoteEndPoint.Address.ToString(), $path)
        } else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($msg.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($msg, 0, $msg.Length)
            Write-Host ("  [404] {0}" -f $path)
        }
    } catch {
        Write-Host ("  [错误] " + $_.Exception.Message)
    } finally {
        if ($stream) { $stream.Close() }
        if ($client) { $client.Close() }
    }
}
