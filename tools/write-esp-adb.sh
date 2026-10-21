#!/bin/bash
# 用 adb 写 ESP（唯一验证过有效的方式），每步设备端 md5 校验
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/write-esp-adb.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 1) 确认 adb 与本地文件 ==="
"$ADB" devices 2>&1 | tr -d '\r' | tee -a "$LOG"
NEW="$WIN/BOOTAA64.EFI"
DTB="$WIN/equuleus.dtb"
ls -l "$NEW" "$DTB" 2>&1 | tee -a "$LOG" || { log "!! 本地文件缺失"; exit 1; }

LOCAL_EFI_MD5=$(md5sum "$NEW" | awk '{print $1}')
LOCAL_DTB_MD5=$(md5sum "$DTB" | awk '{print $1}')
LOCAL_EFI_SIZE=$(stat -c %s "$NEW")
log "本地 BOOTAA64.EFI: ${LOCAL_EFI_SIZE}B md5=${LOCAL_EFI_MD5}"
log "本地 equuleus.dtb: $(stat -c %s "$DTB")B md5=${LOCAL_DTB_MD5}"

log "=== 2) push 到 /data/local/tmp ==="
"$ADB" -s "$SER" push "$NEW" /data/local/tmp/BOOTAA64.EFI 2>&1 | tr -d '\r' | tee -a "$LOG"
"$ADB" -s "$SER" push "$DTB" /data/local/tmp/equuleus.dtb 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 3) 校验设备上的临时文件（Android 侧 md5）==="
DEV_EFI_MD5=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
DEV_DTB_MD5=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/equuleus.dtb" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "设备临时 BOOTAA64.EFI md5=$DEV_EFI_MD5"
log "设备临时 equuleus.dtb md5=$DEV_DTB_MD5"
[ "$DEV_EFI_MD5" = "$LOCAL_EFI_MD5" ] || { log "!! push 后 md5 不一致，中止"; exit 1; }
[ "$DEV_DTB_MD5" = "$LOCAL_DTB_MD5" ] || { log "!! dtb push md5 不一致，中止"; exit 1; }
log "✅ push 校验通过"

log "=== 4) 挂载 ESP ==="
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp; mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp; df -h /data/local/tmp/esp | tail -2'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 5) 备份现有 BOOTAA64.EFI，然后写入 ==="
"$ADB" -s "$SER" shell "su -c '
  cd /data/local/tmp/esp/EFI/Boot
  [ -f BOOTAA64.EFI ] && cp -f BOOTAA64.EFI BOOTAA64.EFI.bak-\$(date +%H%M) 
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  cp -f /data/local/tmp/equuleus.dtb /data/local/tmp/esp/equuleus.dtb
  sync
  echo \"--- 写入后设备端校验 ---\"
  stat -c \"%s bytes  %n\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI /data/local/tmp/esp/equuleus.dtb
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 6) 读回确认（设备端真实值 vs 本地）==="
ESP_EFI_MD5=$("$ADB" -s "$SER" shell "su -c 'md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
ESP_DTB_MD5=$("$ADB" -s "$SER" shell "su -c 'md5sum /data/local/tmp/esp/equuleus.dtb'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
ESP_EFI_SIZE=$("$ADB" -s "$SER" shell "su -c 'stat -c %s /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI'" 2>/dev/null | tr -d '\r')

log "ESP BOOTAA64.EFI: ${ESP_EFI_SIZE}B md5=$ESP_EFI_MD5 （期望 ${LOCAL_EFI_SIZE}B $LOCAL_EFI_MD5）"
log "ESP equuleus.dtb: md5=$ESP_DTB_MD5 （期望 $LOCAL_DTB_MD5）"

if [ "$ESP_EFI_MD5" != "$LOCAL_EFI_MD5" ]; then
  log "!! ESP 里的 BOOTAA64.EFI 与本地不一致，中止，不重启"
  exit 1
fi
if [ "$ESP_DTB_MD5" != "$LOCAL_DTB_MD5" ]; then
  log "!! ESP 里的 dtb 与本地不一致，中止"
  exit 1
fi
log "✅ ESP 落盘校验通过（设备端 md5 一致）"

log "=== 7) 移除干扰项（UEFI 菜单里的 grub 备份）==="
"$ADB" -s "$SER" shell "su -c '
  cd /data/local/tmp/esp/EFI/Boot
  ls -l
  mv -f BOOTAA64.EFI.grub /data/local/tmp/BOOTAA64.EFI.grub.disabled 2>/dev/null && echo \"grub 备份已移出 ESP\"
  ls -l
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 8) 卸载 ESP ==="
"$ADB" -s "$SER" shell "su -c 'sync; umount /data/local/tmp/esp; echo umounted'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 9) 重启到 recovery（= UEFI = 新内核）==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 10) 等内核 + 串口（90 秒）==="
PORT=""
for i in $(seq 1 15); do
  sleep 6
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "串口出现: $PORT （T+$((i*6))s）"; break; }
done
[ -z "$PORT" ] && { log "!! 90 秒内没有串口，内核未启动"; exit 1; }

log "=== 11) 抓启动日志 30 秒 ==="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 30 2>&1 \
  | tr -d '\r' | tee -a "$LOG"

log "=== 完成 ==="
