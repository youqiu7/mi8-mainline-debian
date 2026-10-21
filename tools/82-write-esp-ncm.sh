#!/bin/bash
# 82 —— 只写 ESP 为 BOOTAA64-ncm.efi(7989f352)，然后引导
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
EFI="C:/Users/duoya/AppData/Local/Temp/mi8flash/BOOTAA64-ncm.efi"
EXP="7989f352cad417bb107767cfeedd2935"
LOG="$PROJ/02-工具/82-esp-ncm.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

E=$(md5sum "$EFI" | awk '{print $1}')
[ "$E" = "$EXP" ] || { log "!! EFI md5 不符: $E"; exit 1; }
log "EFI $E"

st=""
for i in $(seq 1 60); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && break
  sleep 3
done
[ "$st" = "device" ] || { log "!! 无 adb（可能还在 Linux 或没进 Android）"; exit 1; }
log "adb OK"

"$ADB" -s "$SER" push "$EFI" /data/local/tmp/ncm.efi 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/ncm.efi" | tr -d '\r' | awk '{print $1}')
[ "$D" = "$E" ] || { log "!! push 失败"; exit 1; }
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/ncm.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"
sleep 1
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回 $R"
[ "$R" = "$E" ] || { log "!! 落盘不符"; exit 1; }
log "✅ ESP OK，引导"
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/ncm.efi"
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"
