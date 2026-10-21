#!/bin/bash
# 走 UEFI 并在内核一启动就抓住串口，捕获 try_switch_root 的失败原因
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
LOG="F:/小米刷机/米8移植debian/02-工具/catch-switchroot.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 1) 确认 adb ==="
"$ADB" devices 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 2) 确认 ESP 里是修复版 init v5 ==="
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp
  stat -c \"%s\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 3) reboot recovery（UEFI）==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 4) 轮询 COM7 并在打开后连续读 100 秒 ==="
powershell -NoProfile -ExecutionPolicy Bypass -Command "
\$opened=\$false
for (\$i=0; \$i -lt 50; \$i++) {
  Start-Sleep -Milliseconds 2000
  \$ports = [System.IO.Ports.SerialPort]::GetPortNames()
  if (\$ports -contains 'COM7') {
    try {
      \$sp = New-Object System.IO.Ports.SerialPort COM7,115200,'None',8,'One'
      \$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=300
      \$sp.Open()
      Write-Host ('=== COM7 opened (try ' + (\$i+1) + ') ===')
      \$opened=\$true
      \$end=(Get-Date).AddSeconds(100)
      \$buf=New-Object char[] 8192
      while((Get-Date) -lt \$end){
        try { \$n=\$sp.Read(\$buf,0,\$buf.Length); if(\$n -gt 0){ Write-Host -NoNewline (-join \$buf[0..(\$n-1)]) } } catch {}
      }
      \$sp.Close()
      break
    } catch { }
  }
}
if (-not \$opened) { Write-Host '!! COM7 never appeared' }
" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 完成 ==="
