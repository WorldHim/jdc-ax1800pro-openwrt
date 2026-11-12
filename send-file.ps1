# send-file.ps1 -- push a file to the router over raw TCP. No install, no admin, no Python.
#
# The stock JDCOS busybox HAS `nc` but only in client mode, so the PC must listen.
#
#   powershell -ExecutionPolicy Bypass -File .\send-file.ps1 `
#       -File ..\firmware\uboot-flashfiles-ss-01.bin -BindIp 192.168.68.11 -Port 8000
#
# Router side:
#   nc 192.168.68.11 8000 > /tmp/uboot.bin
#
param(
    [Parameter(Mandatory=$true)][string]$File,
    [string]$BindIp = "0.0.0.0",
    [int]$Port = 8000,
    [int]$Seconds = 300
)

$ErrorActionPreference = "Stop"

$full  = (Resolve-Path $File).Path
$item  = Get-Item $full
$bytes = [System.IO.File]::ReadAllBytes($full)
$md5   = (Get-FileHash $full -Algorithm MD5).Hash.ToLower()

Write-Host ""
Write-Host "  file : $full"
Write-Host "  size : $($item.Length) bytes"
Write-Host "  md5  : $md5"
Write-Host ""
Write-Host "  Router side (telnet):"
Write-Host "    nc $BindIp $Port > /tmp/$($item.Name)"
Write-Host ""
Write-Host "  Then verify on the router:"
Write-Host "    wc -c /tmp/$($item.Name)   # must be $($item.Length)"
Write-Host "    md5sum /tmp/$($item.Name)  # must be $md5"
Write-Host ""

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($BindIp), $Port)
try {
    $listener.Start()
} catch {
    Write-Host "  LISTEN FAILED: $($_.Exception.Message)"
    Write-Host "  common causes:"
    Write-Host "    - port $Port already in use   -> pick another port"
    Write-Host "    - BindIp not on this machine  -> check Get-NetIPAddress -AddressFamily IPv4"
    exit 1
}

Write-Host "  LISTENING $BindIp`:$Port -- waiting for the router to connect ..."
Write-Host "  (Ctrl+C to abort; auto-give-up after $Seconds s)"
Write-Host ""

$deadline = (Get-Date).AddSeconds($Seconds)
$client = $null

while ((Get-Date) -lt $deadline) {
    if ($listener.Pending()) { $client = $listener.AcceptTcpClient(); break }
    Start-Sleep -Milliseconds 200
}

if ($client -eq $null) {
    $listener.Stop()
    Write-Host "  TIMEOUT: nothing connected in $Seconds s."
    Write-Host "  check: firewall inbound rule for TCP/$Port, and the IP you typed on the router."
    exit 1
}

$peer = $client.Client.RemoteEndPoint.ToString()
Write-Host "  CONNECTED from $peer"
Write-Host "  sending $($bytes.Length) bytes ..."

try {
    $stream = $client.GetStream()
    $stream.WriteTimeout = 60000
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    $client.Client.Shutdown([System.Net.Sockets.SocketShutdown]::Send)
    Start-Sleep -Milliseconds 400
    Write-Host "  SENT. $($bytes.Length) bytes written to socket."
} catch {
    Write-Host "  SEND ERROR: $($_.Exception.Message)"
} finally {
    try { $client.Close() } catch { }
    try { $listener.Stop() } catch { }
}

Write-Host ""
Write-Host "  Next: on the router, verify size and md5 before dd-ing."
