#!/bin/bash
# 65 —— 部署 CONFIG_CMDLINE_FORCE 内核（BOOTAA64-debian.efi md5 0c25619f）
# 先备份 ESP 里现有的 BOOTAA64.EFI（能 switch_root 的 deb0b27b 版），再写入新内核
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
PROJ="F:/小米刷机/米8移植debian"
LOG="$PROJ/02-工具/deploy-cmdline-force.log"
EFI="$WIN/BOOTAA64-debian.efi"
EXP="0c25619f3fff82035fd5d02792cb3839"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=========== 0) 本地校验 ==========="
[ -f "$EFI" ] || { log "!! 缺 $EFI"; exit 1; }
L=$(md5sum "$EFI" | awk '{print $1}')
log "本地 $(stat -c %s "$EFI")B md5=$L"
[ "$L" = "$EXP" ] || { log "!! md5 与预期 $EXP 不符，停止"; exit 1; }

log "=========== 1) 找设备 ==========="
MODE=""
for i in $(seq 1 24); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; break; }
  [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ] && { MODE=fastboot; break; }
  sleep 2
done
log "模式: ${MODE:-无}"

if [ "$MODE" = "fastboot" ]; then
  log "fastboot：清 misc 切 Android"
  "$FB" -s "$SER" erase misc 2>&1 | tr -d '\r' | tee -a "$LOG"
  "$FB" -s "$SER" reboot 2>&1 | tr -d '\r' | tee -a "$LOG"
  for i in $(seq 1 60); do
    sleep 5
    st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
    [ "$st" = "device" ] && { MODE=adb; break; }
  done
fi
[ "$MODE" = "adb" ] || { log "!! 设备不在 adb（请在 Android 下重试）"; exit 1; }
log "adb 就绪"

log "=========== 2) 备份 ESP 现有 BOOTAA64.EFI ==========="
BK="$PROJ/03-备份/esp-boot-$(date +%Y%m%d-%H%M%S).EFI"
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && cp /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/old-esp-boot.efi && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"
"$ADB" -s "$SER" pull /data/local/tmp/old-esp-boot.efi "$BK" 2>&1 | tr -d '\r' | tail -1 | tee -a "$LOG"
if [ -f "$BK" ]; then log "已备份 -> $(basename "$BK")  md5=$(md5sum "$BK" | awk '{print $1}')"; else log "!! 备份失败（继续，但失去回滚点）"; fi

log "=========== 3) push 新内核 ==========="
"$ADB" -s "$SER" push "$EFI" /data/local/tmp/new.efi 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/new.efi" 2>/dev/null | tr -d '\r' | awk '{print $1}')
[ "$D" = "$L" ] || { log "!! push md5 不符（$D）"; exit 1; }
log "✅ push 校验 OK"

log "=========== 4) 写入 ESP + 设备端读回 ==========="
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/new.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"

sleep 1
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 落盘读回: $R（期望 $L）"
[ "$R" = "$L" ] || { log "!! 落盘不符，停止（不重启）"; exit 1; }
log "✅ 落盘确认"

log "=========== 5) UEFI 引导 ==========="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 6) 等 COM 出现（最多 150s）==========="
PORT=""
for i in $(seq 1 30); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "✅ COM: $PORT (T+$((i*5))s)"; break; }
done
[ -z "$PORT" ] && { log "!! 无 COM"; exit 1; }

log "=========== 7) 抓 150 秒日志 ==========="
powershell -NoProfile -ExecutionPolicy Bypass -File "$PROJ/02-工具/read_com2.ps1" -Port "$PORT" -Seconds 150 \
  -OutFile "$PROJ/02-工具/com-log-cmdline-force-$(date +%H%M%S).txt" \
  -Until "login:|Kernel panic|EQUULEUS init" 2>&1 | tr -d '\r' | tee -a "$LOG"
log "=========== 完成 ==========="
