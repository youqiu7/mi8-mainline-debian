#!/bin/bash
# 第2步验证：写 EXT4 内核到 ESP → UEFI → 看 COM 是否仍在
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/test-ext4.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 等 adb ==="
MODE=""
for i in $(seq 1 60); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; break; }
  [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ] && { MODE=fastboot; break; }
  sleep 5
done
log "模式: ${MODE:-无}"

if [ "$MODE" = "fastboot" ]; then
  log "在 fastboot，先切安卓"
  "$FB" -s "$SER" erase misc >/dev/null 2>&1
  "$FB" -s "$SER" reboot >/dev/null 2>&1
  for i in $(seq 1 60); do
    sleep 5
    st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
    [ "$st" = "device" ] && { MODE=adb; break; }
  done
fi
[ "$MODE" = "adb" ] || { log "!! 无 adb"; exit 1; }

EFI="$WIN/BOOTAA64-ext4.efi"
[ -f "$EFI" ] || { log "!! 文件缺失"; exit 1; }
L=$(md5sum "$EFI" | awk '{print $1}')
log "本地 $(stat -c %s "$EFI")B md5=$L"

"$ADB" -s "$SER" push "$EFI" /data/local/tmp/BOOTAA64.EFI 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
[ "$D" = "$L" ] || { log "!! push md5 不符"; exit 1; }
log "✅ push 校验"

"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  sync
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

sleep 2
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回 $R（期望 $L）"
[ "$R" = "$L" ] || { log "!! 落盘不符"; exit 1; }
log "✅ 落盘确认"

log "=== UEFI 引导 ==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 等 COM 180 秒 ==="
PORT=""
for i in $(seq 1 36); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "✅✅ COM 出现: $PORT (T+$((i*5))s)"; break; }
done
[ -z "$PORT" ] && { log "!! 180 秒无 COM"; exit 1; }

log "=== 发 d 命令要诊断 ==="
powershell -NoProfile -ExecutionPolicy Bypass -Command "
\$sp = New-Object System.IO.Ports.SerialPort $PORT,115200,'None',8,'One'
\$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=700
\$sp.Open(); Start-Sleep -Milliseconds 500
\$sp.Write('d' + [char]13)
\$end=(Get-Date).AddSeconds(15); \$buf=New-Object char[] 4096
while((Get-Date) -lt \$end){ try{ \$n=\$sp.Read(\$buf,0,\$buf.Length); if(\$n -gt 0){ Write-Host -NoNewline (-join \$buf[0..(\$n-1)]) } }catch{} }
\$sp.Close()
" 2>&1 | tr -d '\r' | tee -a "$LOG"
log "=== 完成 ==="
