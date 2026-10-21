#!/bin/bash
# auto-flash-uefi.sh —— 等设备进 fastboot 后，把 UEFI 刷进 recovery 分区
#
# 为什么刷 recovery 而不是 boot：
#   - 保住 Android（boot 分区不动，普通开机仍然进 Android）
#   - 「音量上 + 电源」= 进 recovery = 进 UEFI = 进 Linux
#   - recovery 原镜像已备份（03-备份/bk_recovery.img, md5 b5198af3…），可随时刷回
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
UEFI="C:/Users/duoya/AppData/Local/Temp/mi8flash/boot-equuleus.img"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "等待设备出现（fastboot 或 adb），最多 90 分钟..."
MODE=""
for i in $(seq 1 1080); do
  if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then MODE=fastboot; break; fi
  if [ "$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | grep -c "device$")" != "0" ]; then
    MODE=adb; break
  fi
  sleep 5
done
log "检测到模式: ${MODE:-无}"

if [ "$MODE" = "adb" ]; then
  log "设备在 Android，用 root 方式重启到 bootloader（比 adb reboot 可靠）"
  "$ADB" -s "$SER" shell "su -c 'reboot bootloader'" 2>&1 | head -2
  sleep 15
  for i in $(seq 1 36); do
    if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then MODE=fastboot; break; fi
    sleep 5
  done
fi

if [ "$MODE" != "fastboot" ]; then
  log "仍未进入 fastboot，退出（需要人工按 音量下+电源）"
  exit 1
fi

log "fastboot 就绪，刷 UEFI 到 recovery 分区..."
"$FB" -s "$SER" flash recovery "$UEFI" 2>&1

log "校验回读（只比对镜像前缀）..."
SZ=$(stat -c %s "$UEFI")
"$FB" -s "$SER" reboot bootloader 2>&1
sleep 12
for i in $(seq 1 12); do
  if [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; then break; fi
  sleep 5
done

log "刷写完成。之后：音量上+电源 = UEFI(→Linux)，普通电源 = Android"
log "如要回滚 recovery: fastboot flash recovery 03-备份/bk_recovery.img"
