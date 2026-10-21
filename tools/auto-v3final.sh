#!/bin/bash
# 设备一出现就自动：切安卓(如需) → 写 v3final 到 ESP → UEFI → 抓 COM
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/auto-v3final.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 等待设备（30 分钟）==="
MODE=""
for i in $(seq 1 360); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; break; }
  [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ] && { MODE=fastboot; break; }
  sleep 5
done
log "检测到: ${MODE:-无}"
[ -z "$MODE" ] && exit 1

if [ "$MODE" = "fastboot" ]; then
  log "=== 在 fastboot，先切安卓 ==="
  "$FB" -s "$SER" erase misc 2>&1 | tr -d '\r' | tee -a "$LOG"
  "$FB" -s "$SER" reboot 2>&1 | tr -d '\r' | tee -a "$LOG"
  MODE=""
  for i in $(seq 1 60); do
    sleep 5
    st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
    [ "$st" = "device" ] && { MODE=adb; log "adb 就绪 T+$((i*5))s"; break; }
  done
  [ "$MODE" = "adb" ] || { log "!! 没进 Android"; exit 1; }
fi

log "=== 写 ESP（v3final：cmdline 无 dtb=）==="
EFI="$WIN/BOOTAA64-v3final.efi"
[ -f "$EFI" ] || { log "!! $EFI 缺失"; exit 1; }
L_EFI=$(md5sum "$EFI" | awk '{print $1}')
log "本地: $(stat -c %s "$EFI")B md5=$L_EFI"

"$ADB" -s "$SER" push "$EFI" /data/local/tmp/BOOTAA64.EFI 2>&1 | tr -d '\r' | tee -a "$LOG"
D_EFI=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "push 后: $D_EFI"
[ "$D_EFI" = "$L_EFI" ] || { log "!! push md5 不符"; exit 1; }

"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  sync
  stat -c \"%s %n\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

sleep 2
R_EFI=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回: $R_EFI（期望 $L_EFI）"
[ "$R_EFI" = "$L_EFI" ] || { log "!! ESP 落盘不符"; exit 1; }
log "✅ 落盘确认"

log "=== UEFI 引导 ==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 等 COM（180 秒）==="
PORT=""
for i in $(seq 1 36); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "✅✅ 串口出现: $PORT (T+$((i*5))s)"; break; }
done
if [ -z "$PORT" ]; then
  log "!! 180 秒无串口"
  exit 1
fi

log "=== 抓日志 45 秒 ==="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 45 2>&1 \
  | tr -d '\r' | tee -a "$LOG"
log "=== 完成 ==="
