# read_com.ps1 —— 读取 USB CDC-ACM 串口（equuleus P1 控制台）
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File read_com.ps1 -Port COM3 -Seconds 90
#   powershell -NoProfile -ExecutionPolicy Bypass -File read_com.ps1 -Auto -Seconds 90   # 自动挑新出现的口
param(
    [string]$Port = "",
    [int]$Seconds = 90,
    [int]$Baud = 115200,
    [switch]$Auto
)

function Get-Ports { [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object }

if ($Auto -or -not $Port) {
    $before = Get-Ports
    Write-Host "当前串口: $($before -join ', ')"
    # 等新口出现（最多 60 秒）
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        $now = Get-Ports
        $new = $now | Where-Object { $before -notcontains $_ }
        if ($new) { $Port = $new[0]; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $Port) {
        $now = Get-Ports
        if ($now) { $Port = $now[0] } else { Write-Host "没有发现任何串口"; exit 1 }
    }
}

Write-Host "打开 $Port @ $Baud ..."
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 1000
$sp.NewLine = "`n"
try { $sp.Open() } catch { Write-Host "打开失败: $_"; exit 1 }

$outFile = Join-Path $PSScriptRoot ("com-log-" + (Get-Date -Format "HHmmss") + ".txt")
Write-Host "开始读取 ${Seconds}s，日志同时写入 $outFile"
$sw = [System.IO.StreamWriter]::new($outFile, $true)
$sw.AutoFlush = $true

$end = (Get-Date).AddSeconds($Seconds)
$buf = New-Object char[] 4096
while ((Get-Date) -lt $end) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        if ($n -gt 0) {
            $s = -join $buf[0..($n-1)]
            Write-Host -NoNewline $s
            $sw.Write($s)
        }
    } catch [System.TimeoutException] { }
    catch { Write-Host "`n读取异常: $_"; break }
}
$sw.Close()
$sp.Close()
Write-Host "`n--- 结束，日志: $outFile ---"
