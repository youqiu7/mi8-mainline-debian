#!/bin/bash
# 74 —— 决定性实验：ESP 回滚到 deb0b27b（UEFI cmdline，无 console=ttyGS0），rootfs 保持 72801274
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
EFI="$PROJ/03-备份/esp-boot-20261021-040450.EFI"
EXP="deb0b27b188e2cedfd866a448edd3661"
LOG="$PROJ/02-工具/74-esp-rollback.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 0) 校验源文件 ==="
L=$(md5sum "$EFI" | awk '{print $1}')
log "源 $(stat -c %s "$EFI")B md5=$L"
[ "$L" = "$EXP" ] || { log "!! md5 不符"; exit 1; }

log "=== 1) adb ==="
st=$("$ADB" devices | tr -d '\r' | grep "$SER" | awk '{print $2}')
[ "$st" = "device" ] || { log "!! 无 adb（需要设备在 Android）"; exit 1; }
log "adb OK"

log "=== 2) push + 写 ESP ==="
"$ADB" -s "$SER" push "$EFI" /data/local/tmp/old.efi 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/old.efi" | tr -d '\r' | awk '{print $1}')
[ "$D" = "$EXP" ] || { log "!! push 校验失败 $D"; exit 1; }
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/old.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"
sleep 1
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回 $R（期望 $EXP）"
[ "$R" = "$EXP" ] || { log "!! 落盘不符"; exit 1; }
log "✅ ESP = deb0b27b（UEFI cmdline 版）"

log "=== 3) 引导 ==="
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/old.efi; rm -f /data/local/tmp/rf.img; rm -f /data/local/tmp/journal.tgz"
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"
log "已 reboot recovery"
