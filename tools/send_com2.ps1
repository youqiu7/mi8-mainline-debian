param(
    [string]$Port = "COM6",
    [string]$Cmd = "r",
    [int]$Baud = 115200,
    [int]$Repeat = 5,
    [int]$HoldMs = 2000
)
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 500
try { $sp.Open() } catch { Write-Host "打开失败: $_"; exit 1 }
Start-Sleep -Milliseconds 500
for ($i = 0; $i -lt $Repeat; $i++) {
    $sp.Write($Cmd)
    Start-Sleep -Milliseconds 200
}
Write-Host "已发送 $Repeat 次 '$Cmd'，保持 ${HoldMs}ms 读回显..."
$deadline = (Get-Date).AddMilliseconds($HoldMs)
$buf = New-Object char[] 1024
while ((Get-Date) -lt $deadline) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        if ($n -gt 0) { Write-Host -NoNewline (-join $buf[0..($n-1)]) }
    } catch [System.TimeoutException] { }
    catch { break }
}
$sp.Close()
Write-Host "`n--- 关闭 ---"
