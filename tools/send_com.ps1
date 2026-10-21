param(
    [string]$Port = "COM6",
    [string]$Cmd = "r",
    [int]$Baud = 115200
)
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.DtrEnable = $false
$sp.RtsEnable = $false
try { $sp.Open() } catch { Write-Host "打开失败: $_"; exit 1 }
Start-Sleep -Milliseconds 200
$sp.Write($Cmd)
Start-Sleep -Milliseconds 300
$sp.Close()
Write-Host "已向 $Port 发送: $Cmd"
