#!/bin/bash
# 只读不写：等 Android 起来，读 ESP 的真实内容（这是 A 方案唯一目的）
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
LOG="F:/小米刷机/米8移植debian/02-工具/read-esp.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 等待设备（adb 或 fastboot），最多 20 分钟 ==="
MODE=""
for i in $(seq 1 240); do
  if [ "$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | grep -c 'device$')" != "0" ]; then MODE=adb; break; fi
  if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then MODE=fastboot; break; fi
  sleep 5
done

log "检测到: ${MODE:-无}"

if [ "$MODE" = "fastboot" ]; then
  log "!! 设备在 fastboot 而不是 Android"
  log "   说明 misc 里还有 boot-recovery，或者你按了音量下"
  log "   需要先清 misc 才能进 Android"
  exit 2
fi

if [ "$MODE" != "adb" ]; then
  log "超时，退出"
  exit 1
fi

log "设备在 Android，开始只读检查（不做任何写入）"

log "--- 1) 设备身份 ---"
"$ADB" -s "$SER" shell "getprop ro.product.device; getprop ro.build.version.release; getprop ro.boot.verifiedbootstate" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "--- 2) 挂载 ESP 并读取真实内容 ---"
"$ADB" -s "$SER" shell "su -c '
  mkdir -p /data/local/tmp/esp
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  echo \"=== ESP 根目录 ===\"
  ls -l /data/local/tmp/esp/
  echo \"=== EFI/Boot 目录 ===\"
  ls -l /data/local/tmp/esp/EFI/Boot/
  echo \"=== BOOTAA64.EFI 真实 md5 和大小 ===\"
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  stat -c \"%s bytes\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  echo \"=== equuleus.dtb ===\"
  md5sum /data/local/tmp/esp/equuleus.dtb 2>/dev/null
  stat -c \"%s bytes\" /data/local/tmp/esp/equuleus.dtb 2>/dev/null
  echo \"=== 文件头 4 字节（4d5a=PE, 其他=非EFI）===\"
  xxd -l 8 /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null || od -A x -t x1 -N 8 /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  echo \"=== 校验是否为 GRUB（搜 grub 字符串）===\"
  strings /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null | grep -c -i grub
  echo \"=== 校验是否为我们内核（搜 EQUULEUS/P1/P3 标记）===\"
  strings /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI 2>/dev/null | grep -c -iE \"EQUULEUS|init v[0-9]|Linux version\"
  echo \"=== 分区信息 ===\"
  df -h /data/local/tmp/esp 2>/dev/null | tail -2
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "--- 3) misc 分区内容（看 boot-recovery 还在不在）---"
"$ADB" -s "$SER" shell "su -c '
  echo \"misc 前 64 字节:\"
  xxd -l 64 /dev/block/by-name/misc 2>/dev/null || od -A x -t x1 -N 64 /dev/block/by-name/misc
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 只读检查完成，未修改任何东西 ==="
