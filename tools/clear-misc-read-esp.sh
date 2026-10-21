#!/bin/bash
# 清 misc 里的 boot-recovery → 重启进 Android → 读 ESP 真实内容（只读验证）
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
LOG="F:/小米刷机/米8移植debian/02-工具/read-esp.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 1) 确认 fastboot ==="
"$FB" devices 2>&1 | tee -a "$LOG"

log "=== 2) 清 misc（只清 bootloader_message，4MB 分区无关键数据）==="
"$FB" -s "$SER" erase misc 2>&1 | tee -a "$LOG"
sleep 2

log "=== 3) 重启（这次应该进 Android 而不是 recovery）==="
"$FB" -s "$SER" reboot 2>&1 | tee -a "$LOG"

log "=== 4) 等 Android + adb（最多 5 分钟）==="
MODE=""
for i in $(seq 1 60); do
  sleep 5
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  if [ "$st" = "device" ]; then MODE=adb; log "adb 就绪（T+$((i*5))s）"; break; fi
  if [ "$st" = "unauthorized" ]; then MODE=unauth; log "adb unauthorized"; break; fi
  if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then MODE=fastboot; log "又回 fastboot 了"; break; fi
done
log "结果: ${MODE:-超时}"

if [ "$MODE" != "adb" ]; then
  log "!! 没进 Android（$MODE）"
  log "   如果又进 GRUB/UEFI 或黑屏，需要换方案"
  exit 1
fi

log "=== 5) 读 ESP 真实内容（只读）==="
"$ADB" -s "$SER" shell "su -c '
  mkdir -p /data/local/tmp/esp
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  echo \"--- ESP 根 ---\"
  ls -l /data/local/tmp/esp/
  echo \"--- EFI/Boot ---\"
  ls -l /data/local/tmp/esp/EFI/Boot/
  echo \"--- BOOTAA64.EFI 真实大小/md5/头 ---\"
  stat -c \"%s bytes\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  xxd -l 16 /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null || od -A x -t x1 -N 16 /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  echo \"--- 是 GRUB 吗（grub 字符串计数）---\"
  strings /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null | grep -ci grub
  echo \"--- 是我们的内核吗（Linux version / EQUULEUS）---\"
  strings /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null | grep -ciE \"Linux version|EQUULEUS\"
  echo \"--- equuleus.dtb ---\"
  stat -c \"%s bytes\" /data/local/tmp/esp/equuleus.dtb 2>/dev/null
  md5sum /data/local/tmp/esp/equuleus.dtb 2>/dev/null
  echo \"--- ESP 根其他文件 ---\"
  ls -l /data/local/tmp/esp/Image /data/local/tmp/esp/initramfs.cpio.gz 2>/dev/null
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 6) misc 现在的状态 ==="
"$ADB" -s "$SER" shell "su -c 'xxd -l 32 /dev/block/by-name/misc 2>/dev/null || od -A x -t x1 -N 32 /dev/block/by-name/misc'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 完成：以上是 ESP 的真实状态，未做任何写入 ==="
