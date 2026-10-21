#!/bin/bash
# auto-continue.sh —— 等 adb 授权恢复后，自动更新 ESP 并引导新内核
# 用法：bash auto-continue.sh   （后台运行，日志写 auto-continue.log）
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
IMG="C:/Users/duoya/AppData/Local/Temp/mi8flash/BOOTAA64.EFI"
UEFI="C:/Users/duoya/AppData/Local/Temp/mi8flash/boot-equuleus.img"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "等待 adb 授权（最多 60 分钟）..."
OK=0
for i in $(seq 1 720); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  if [ "$st" = "device" ]; then OK=1; log "授权恢复"; break; fi
  sleep 5
done
if [ "$OK" != "1" ]; then log "超时未授权，退出"; exit 1; fi

log "推送新内核到设备..."
"$ADB" -s "$SER" push "$IMG" /data/local/tmp/BOOTAA64.EFI || { log "push 失败"; exit 1; }

log "挂载 ESP 并替换 BOOTAA64.EFI..."
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp; mount -t vfat -o rw /dev/block/sda22 /data/local/tmp/esp && cp /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>&1

log "重启到 fastboot..."
"$ADB" -s "$SER" reboot bootloader
sleep 15
FBOK=0
for i in $(seq 1 24); do
  d=$("$FB" devices 2>/dev/null | grep -c "$SER")
  if [ "$d" != "0" ]; then FBOK=1; log "fastboot 就绪"; break; fi
  sleep 5
done
if [ "$FBOK" != "1" ]; then log "没进 fastboot，停止"; exit 1; fi

log "引导 UEFI + 新内核..."
"$FB" -s "$SER" boot "$UEFI" 2>&1

log "已发出引导命令；等待 COM 口出现（新 init 会暴露 UMS + 诊断）"
for i in $(seq 1 24); do
  sleep 5
  c=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | tr '\n' ' ')
  if [ -n "$c" ]; then log "串口出现: $c"; break; fi
done
log "完成"
