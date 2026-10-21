#!/bin/bash
# 等 Android → 写 wifioff 隔离镜像到 ESP → reboot recovery → 抓 COM
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/test-wifioff.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 等待 Android（20 分钟）==="
for i in $(seq 1 240); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { log "adb 就绪"; break; }
  sleep 5
done
st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
[ "$st" = "device" ] || { log "!! 没等到 adb（$st）"; exit 1; }

IMGF="$WIN/BOOTAA64-wifioff.efi"
DTBF="$WIN/equuleus-wifioff.dtb"
LMD5=$(md5sum "$IMGF" | awk '{print $1}')
LDTB=$(md5sum "$DTBF" | awk '{print $1}')
LSZ=$(stat -c %s "$IMGF")
log "本地: ${LSZ}B md5=$LMD5 / dtb md5=$LDTB"

log "=== push ==="
"$ADB" -s "$SER" push "$IMGF" /data/local/tmp/BOOTAA64.EFI 2>&1 | tr -d '\r' | tee -a "$LOG"
"$ADB" -s "$SER" push "$DTBF" /data/local/tmp/equuleus.dtb 2>&1 | tr -d '\r' | tee -a "$LOG"

DMD5=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
DDTB=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/equuleus.dtb" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "设备临时: md5=$DMD5 / dtb=$DDTB"
[ "$DMD5" = "$LMD5" ] || { log "!! push md5 不符"; exit 1; }

log "=== 写 ESP ==="
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  cp -f /data/local/tmp/equuleus.dtb /data/local/tmp/esp/equuleus.dtb
  sync
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
  stat -c \"%s %n\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 读回校验 ==="
E=$( "$ADB" -s "$SER" shell "su -c 'mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}' )
log "ESP 读出 md5=$E （期望 $LMD5）"
[ "$E" = "$LMD5" ] || { log "!! ESP 落盘不符，中止"; exit 1; }
log "✅ 落盘确认"

log "=== reboot recovery ==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 等串口 100 秒 ==="
PORT=""
for i in $(seq 1 20); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "串口: $PORT (T+$((i*5))s)"; break; }
done
if [ -z "$PORT" ]; then
  log "!! 无串口 —— 仍是早期 panic"
  exit 1
fi

log "=== 抓 35 秒日志 ==="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 35 2>&1 \
  | tr -d '\r' | tee -a "$LOG"
log "=== 完成 ==="
