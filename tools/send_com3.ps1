# send_com3.ps1 —— 发送命令并读回（用于判断 ttyGS0 上是否已有 shell / getty）
param(
    [string]$Port = "COM7",
    [int]$Baud = 115200,
    [string]$Cmd = "",
    [int]$Seconds = 12,
    [switch]$EnterFirst
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 500
try { $sp.Open() } catch { Write-Host "OPEN FAIL: $($_.Exception.Message)"; exit 2 }
Start-Sleep -Milliseconds 300

if ($EnterFirst) { $sp.Write("`r"); Start-Sleep -Milliseconds 800 }
if ($Cmd) { $sp.Write($Cmd + "`r"); Write-Host "[sent] $Cmd" }

$buf = New-Object byte[] 8192
$enc = [System.Text.Encoding]::UTF8
$end = (Get-Date).AddSeconds($Seconds)
$total = 0
while ((Get-Date) -lt $end) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        if ($n -gt 0) { $total += $n; Write-Host -NoNewline $enc.GetString($buf, 0, $n) }
    } catch [System.TimeoutException] { }
    catch { Write-Host "`nREAD EXC: $($_.Exception.Message)"; break }
}
Write-Host "`n[read $total bytes]"
try { $sp.Close(); $sp.Dispose() } catch {}
