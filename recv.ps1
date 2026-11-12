<#
  接收京东云 AX1800 Pro 备份文件
  —— 适配 BusyBox v1.30.1 的 nc（只支持 `nc [IPADDR PORT]` 客户端模式，无 -l / -p / -w）

  协议（PC 当服务端，路由器主动连上来推）：
      第 1 行 : 文件名       （\n 结尾）
      第 2 行 : 字节数       （\n 结尾）
      之后    : 恰好 N 字节的文件内容
  这样 PC 端读到 N 字节就主动关连接，避免双方互等 EOF 造成卡死。

  路由端命令见下方提示（脚本启动后会打印）。
#>

param(
  [string]$OutDir  = "./backup",
  [string]$BindIp  = "0.0.0.0",
  [int]   $Port    = 8000,
  [int]   $Expect  = 1,
  [int]   $IdleSec = 300
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$routerCmd = 'cd /mnt/mmcblk0p27/emmc_backup; for f in *.bin; do sz=$(wc -c < "$f"); { echo "$f"; echo "$sz"; cat "$f"; } | busybox nc ' + $BindIp + ' ' + $Port + '; sleep 1; done'

Write-Host ""
Write-Host "=== 备份接收服务（nc push 模式）===" -ForegroundColor Cyan
Write-Host ("  监听 : {0}:{1}" -f $BindIp, $Port)
Write-Host ("  存到 : {0}" -f $OutDir)
Write-Host ("  期望 : {0} 个文件" -f $Expect)
Write-Host ""
Write-Host "  Ctrl+C 可随时中止" -ForegroundColor DarkGray
Write-Host ""

# ---------- 启动监听 ----------
$listener = $null
try {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindIp), $Port)
  $listener.Start()
} catch {
  Write-Host ("监听失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ("常见原因：{0} 不在本机网卡上 / 端口被占用 / 需要管理员权限" -f $BindIp) -ForegroundColor Red
  Write-Host "  查看本机 IP： ipconfig" -ForegroundColor Yellow
  Write-Host "  换端口：     .\recv.ps1 -Port 8001" -ForegroundColor Yellow
  return
}

function Read-LineFromStream {
  param([System.IO.Stream]$Stream)
  $ms = New-Object System.IO.MemoryStream
  $n = 0
  while ($true) {
    $b = $Stream.ReadByte()
    if ($b -lt 0) { throw "连接在读取过程中被关闭（是否路由器端 nc 直接退出？）" }
    if ($b -eq 10) { break }
    if ($b -ne 13) { $ms.WriteByte([byte]$b) }
    $n++
    if ($n -gt 512) { throw "字段过长，协议不匹配" }
  }
  $s = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).Trim()
  $ms.Dispose()
  return $s
}

$received = New-Object 'System.Collections.Generic.List[string]'
$failures = New-Object 'System.Collections.Generic.List[string]'
$count    = 0
$lastAct  = Get-Date

try {
  while ($true) {
    # ---- 等待连接（带空闲超时）----
    $connected = $false
    while (-not $connected) {
      if ($listener.Pending()) { $connected = $true; break }
      if ($count -ge $Expect) { Write-Host "`n已达期望文件数，收工。" -ForegroundColor Cyan; break }
      if (((Get-Date) - $lastAct).TotalSeconds -gt $IdleSec) {
        Write-Host ("`n已 {0} 秒无新连接，收工。" -f $IdleSec) -ForegroundColor Yellow
        break
      }
      Start-Sleep -Milliseconds 150
    }
    if (-not $connected) { break }

    $client = $listener.AcceptTcpClient()
    $client.ReceiveTimeout = 300000     # 单文件 5 分钟上限
    $name = $null
    try {
      $stream = $client.GetStream()

      # 1) 文件名
      $name = Read-LineFromStream -Stream $stream
      if ([string]::IsNullOrWhiteSpace($name)) { throw "读到空文件名" }
      if ($name -match '[\\/:*?"<>|\x00-\x1f]') { throw ("非法文件名：{0}" -f $name) }

      # 2) 字节数
      $sizeStr = Read-LineFromStream -Stream $stream
      $size = 0
      if (-not [int64]::TryParse($sizeStr, [ref]$size)) { throw ("字节数解析失败：'{0}'" -f $sizeStr) }
      if ($size -le 0 -or $size -gt 64GB) { throw ("字节数不合理：{0}" -f $size) }

      # 3) 恰好 size 字节
      $path = Join-Path $OutDir $name
      $fs = [System.IO.File]::Create($path)
      $remain = [int64]$size
      try {
        $buf = New-Object byte[] 65536
        while ($remain -gt 0) {
          $want = [int][Math]::Min([int64]$buf.Length, $remain)
          $r = $stream.Read($buf, 0, $want)
          if ($r -le 0) { throw ("数据提前结束：还差 {0} 字节" -f $remain) }
          $fs.Write($buf, 0, $r)
          $remain -= $r
        }
      } finally { $fs.Close() }

      $count++
      $lastAct = Get-Date
      $actual = (Get-Item -LiteralPath $path).Length
      if ($actual -ne $size) { throw ("大小不符：期望 {0}，实际 {1}" -f $size, $actual) }

      $hash = (Get-FileHash -Algorithm MD5 -Path $path).Hash.ToLower()
      $received.Add(("{0}  {1}" -f $hash, $name))
      Write-Host ("[{0,2}/{1}] OK  {2,-22} {3,12} bytes  {4}" -f `
                  $count, $Expect, $name, $actual, $hash) -ForegroundColor Green
    }
    catch {
      Write-Host ("  !! 失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
      if ($name) { $failures.Add($name) }
    }
    finally {
      try { $client.Close() } catch {}     # 主动关闭，让路由器端 nc 退出
    }
  }
}
finally {
  try { $listener.Stop() } catch {}
}

# ---------- 收尾 ----------
Write-Host ""
Write-Host ("=== 收到 {0} / {1} 个文件 ===" -f $count, $Expect) -ForegroundColor Cyan

$md5file = Join-Path $OutDir "md5sums_pc.txt"
$received | Set-Content -Path $md5file -Encoding ASCII
Write-Host ("电脑端 MD5 清单：{0}" -f $md5file)

if ($failures.Count -gt 0) {
  Write-Host "`n以下文件失败，需要重传：" -ForegroundColor Red
  foreach ($f in $failures) { Write-Host ("  {0}" -f $f) -ForegroundColor Red }
}

Write-Host ""
Write-Host "下一步：与路由器上的 md5sums.txt 对比（p22/p25 属动态分区，本身就会不同）" -ForegroundColor Yellow
