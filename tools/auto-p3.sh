#!/bin/bash
# auto-p3.sh —— 设备一开机就自动：更新 ESP 内核 → 重启到 recovery(UEFI) → 校验 DTB
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
NEW="C:/Users/duoya/AppData/Local/Temp/mi8flash/BOOTAA64.EFI"
IMG="C:/Users/duoya/AppData/Local/Temp/mi8flash/boot-equuleus.img"
LOG="F:/小米刷机/米8移植debian/02-工具/auto-p3.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== auto-p3 启动，等待设备（90 分钟）==="

# -------- 1. 等设备（adb device 或 fastboot）--------
MODE=""
for i in $(seq 1 1080); do
  if [ "$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | grep -c 'device$')" != "0" ]; then MODE=adb; break; fi
  if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then MODE=fastboot; break; fi
  sleep 5
done
log "检测到: ${MODE:-无}"
[ -z "$MODE" ] && { log "超时退出"; exit 1; }

# -------- 2. fastboot 情况：直接 boot（不改分区）--------
if [ "$MODE" = "fastboot" ]; then
  log "设备在 fastboot，直接引导 UEFI"
  "$FB" -s "$SER" boot "$IMG" 2>&1 | tee -a "$LOG"
  sleep 25
  for i in $(seq 1 10); do
    c=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | tr '\n' '/')
    [ -n "$c" ] && { log "COM 出现: $c"; break; }
    sleep 6
  done
  log "完成（fastboot 路径）"
  exit 0
fi

# -------- 3. adb 情况：更新 ESP 再 reboot recovery --------
log "推送新内核..."
"$ADB" -s "$SER" push "$NEW" /data/local/tmp/BOOTAA64.EFI 2>&1 | tee -a "$LOG"

log "挂载 ESP 并替换..."
"$ADB" -s "$SER" shell "su -c '
  mkdir -p /data/local/tmp/esp
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp || mount /dev/block/sda22 /data/local/tmp/esp
  cp /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  sync
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  ls -l /data/local/tmp/esp/ | head
  umount /data/local/tmp/esp
'" 2>&1 | tee -a "$LOG"

log "确认 ESP 里的 equuleus.dtb 还在（dtb= 要用）..."
"$ADB" -s "$SER" shell "su -c '
  mount /dev/block/sda22 /data/local/tmp/esp
  ls -l /data/local/tmp/esp/equuleus.dtb
  umount /data/local/tmp/esp
'" 2>&1 | tee -a "$LOG"

log "重启到 recovery（= UEFI）..."
"$ADB" -s "$SER" reboot recovery 2>&1 | tee -a "$LOG"

# -------- 4. 等内核起来 + 串口 --------
log "等待内核 + 串口..."
PORT=""
for i in $(seq 1 20); do
  sleep 7
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "串口: $PORT"; break; }
done
[ -z "$PORT" ] && { log "内核未起串口，检查屏幕/pstore"; exit 1; }

log "抓取启动日志 40 秒..."
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 40 2>&1 \
  | tr -d '\r' | tee -a "$LOG"

log "=== 完成：请检查上面的日志里 DT model 是否为 equuleus ==="
