#!/bin/bash
# 完整正确路径：清 misc → 进 Android → 写正确的 dtb+内核到 ESP → UEFI 引导
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/fix-esp-uefi.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=========== 1) 清 misc，让开机回 Android ==========="
"$FB" devices 2>&1 | tr -d '\r' | tee -a "$LOG"
"$FB" -s "$SER" erase misc 2>&1 | tr -d '\r' | tee -a "$LOG"
"$FB" -s "$SER" reboot 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 2) 等 Android + adb（5 分钟）==========="
MODE=""
for i in $(seq 1 60); do
  sleep 5
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; log "adb 就绪 T+$((i*5))s"; break; }
  [ "$st" = "unauthorized" ] && { MODE=unauth; break; }
done
[ "$MODE" = "adb" ] || { log "!! 没进 Android（$MODE）"; exit 1; }

log "=========== 3) 写 ESP（正确 dtb + 内核）==========="
EFI="$WIN/BOOTAA64-good.efi"
DTB="$WIN/equuleus-good.dtb"
[ -f "$EFI" ] || { log "!! $EFI 缺失"; exit 1; }
[ -f "$DTB" ] || { log "!! $DTB 缺失"; exit 1; }

L_EFI=$(md5sum "$EFI" | awk '{print $1}')
L_DTB=$(md5sum "$DTB" | awk '{print $1}')
log "本地: EFI $(stat -c %s "$EFI")B md5=$L_EFI"
log "本地: DTB $(stat -c %s "$DTB")B md5=$L_DTB"

"$ADB" -s "$SER" push "$EFI" /data/local/tmp/BOOTAA64.EFI 2>&1 | tr -d '\r' | tee -a "$LOG"
"$ADB" -s "$SER" push "$DTB" /data/local/tmp/equuleus.dtb 2>&1 | tr -d '\r' | tee -a "$LOG"

D_EFI=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
D_DTB=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/equuleus.dtb" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "push 后设备: EFI=$D_EFI  DTB=$D_DTB"
[ "$D_EFI" = "$L_EFI" ] || { log "!! push EFI md5 不符"; exit 1; }
[ "$D_DTB" = "$L_DTB" ] || { log "!! push DTB md5 不符"; exit 1; }
log "✅ push 校验通过"

log "--- 挂载 ESP 并写入 ---"
"$ADB" -s "$SER" shell "su -c '
  mkdir -p /data/local/tmp/esp
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  cp -f /data/local/tmp/equuleus.dtb /data/local/tmp/esp/equuleus.dtb
  sync
  echo \"--- 写入后 ---\"
  stat -c \"%s %n\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "--- 重新挂载只读读回 ---"
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
  echo \"--- dtb 节点数验证 ---\"
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

R_EFI=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
R_DTB=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/equuleus.dtb; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')

log "ESP 读回: EFI=$R_EFI（期望 $L_EFI）"
log "ESP 读回: DTB=$R_DTB（期望 $L_DTB）"
[ "$R_EFI" = "$L_EFI" ] || { log "!! ESP EFI 落盘不符，中止"; exit 1; }
[ "$R_DTB" = "$L_DTB" ] || { log "!! ESP DTB 落盘不符，中止"; exit 1; }
log "✅ ESP 落盘确认（两个文件都对）"

log "=========== 4) 走 UEFI：adb reboot recovery ==========="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 5) 等 COM（120 秒）==========="
PORT=""
for i in $(seq 1 24); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "串口出现: $PORT (T+$((i*5))s)"; break; }
done
[ -z "$PORT" ] && { log "!! 120 秒无串口"; exit 1; }

log "=========== 6) 抓日志 40 秒 ==========="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 40 2>&1 \
  | tr -d '\r' | tee -a "$LOG"
log "=========== 完成 ==========="
