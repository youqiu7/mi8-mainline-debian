# read_com2.ps1 —— 稳健版串口读取（byte 流 + 全异常捕获 + 关键字提前结束）
# 用法: powershell -File read_com2.ps1 -Port COM7 -Seconds 120 -Until "login:|systemd|Kernel panic|EQUULEUS init"
param(
    [string]$Port = "COM7",
    [int]$Seconds = 120,
    [int]$Baud = 115200,
    [string]$OutFile = "",
    [string]$Until = ""
)

$ErrorActionPreference = "Continue"
if (-not $OutFile) { $OutFile = Join-Path $PSScriptRoot ("com-log-" + (Get-Date -Format "HHmmss") + ".txt") }

# 先列一遍可用口，提示
Write-Host ("当前串口: " + (([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object) -join ", "))

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 700
$sp.WriteTimeout = 700
try { $sp.Open() } catch { Write-Host "打开失败: $($_.Exception.Message)"; exit 2 }

$enc = [System.Text.Encoding]::UTF8
$sw = [System.IO.StreamWriter]::new($OutFile, $true, [System.Text.Encoding]::UTF8)
$sw.AutoFlush = $true
Write-Host "开始读取 ${Seconds}s → $OutFile"

$buf = New-Object byte[] 8192
$end = (Get-Date).AddSeconds($Seconds)
$total = 0
$acc = New-Object System.Text.StringBuilder
$exitCode = 0

while ((Get-Date) -lt $end) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        if ($n -gt 0) {
            $total += $n
            $s = $enc.GetString($buf, 0, $n)
            [void]$acc.Append($s)
            Write-Host -NoNewline $s
            $sw.Write($s)
            if ($Until -and ($acc.ToString() -match $Until)) {
                Write-Host "`n[命中关键字，提前结束]"
                break
            }
        }
    } catch [System.TimeoutException] {
        # 正常，继续等
    } catch {
        Write-Host "`n读取异常: $($_.Exception.Message)"
        $exitCode = 3
        break
    }
}

Write-Host "`n[共 $total 字节，日志: $OutFile]"
$sw.Close()
try { $sp.Close(); $sp.Dispose() } catch {}
exit $exitCode
