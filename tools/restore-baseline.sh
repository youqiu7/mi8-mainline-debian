#!/bin/bash
# 恢复基线：把 BOOTAA64.EFI.bak-0020（23:43 跑通的那个）恢复为主启动文件
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
LOG="F:/小米刷机/米8移植debian/02-工具/restore-baseline.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 1) 确认 adb ==="
"$ADB" devices 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 2) 查看 ESP 里现有哪些文件 ==="
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  ls -l /data/local/tmp/esp/EFI/Boot/
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 3) 恢复基线（bak-0020 → BOOTAA64.EFI）==="
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cd /data/local/tmp/esp/EFI/Boot
  if [ -f BOOTAA64.EFI.bak-0020 ]; then
    cp -f BOOTAA64.EFI.bak-0020 BOOTAA64.EFI
    sync
    echo \"--- 恢复后 ---\"
    stat -c \"%s %n\" BOOTAA64.EFI
    md5sum BOOTAA64.EFI
  else
    echo \"!! bak-0020 不存在\"
    ls -l
  fi
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 4) 校验基线 md5（应为 39716510B / fa316ed2…）==="
"$ADB" -s "$SER" shell "su -c '
  mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp
  stat -c \"%s bytes\" /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 5) reboot recovery（UEFI 引导基线内核）==="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 6) 等 COM 120 秒 ==="
PORT=""
for i in $(seq 1 24); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "✅ 串口出现: $PORT (T+$((i*5))s)"; break; }
done
if [ -z "$PORT" ]; then
  log "!! 基线也没出串口 —— 设备或 UEFI 状态已变，需要重新评估"
  exit 1
fi

log "=== 7) 抓 35 秒日志 ==="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 35 2>&1 \
  | tr -d '\r' | tee -a "$LOG"
log "=== 完成 ==="
