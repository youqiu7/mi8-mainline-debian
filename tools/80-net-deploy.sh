#!/bin/bash
# 80 —— 一次性部署：ESP 写 BOOTAA64-net.efi(98eea6b2) + sda23 写 rootfs(f6a1f11e) + 引导
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
EFI="C:/Users/duoya/AppData/Local/Temp/mi8flash/BOOTAA64-net.efi"
EXP_EFI="98eea6b2665fd9497e77449153e9b93b"
IMG="$PROJ/04-实验/rootfs-f6a1f11e.img"
EXP_IMG="f6a1f11e5bfc117b820b8e8b0285fd7d"
LOG="$PROJ/02-工具/80-net-deploy.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 0) 本地校验 ==="
[ -f "$EFI" ] || { log "!! 缺 $EFI"; exit 1; }
[ -f "$IMG" ] || { log "复制 rootfs 到 $IMG"; wsl.exe -d Debian -u root -- cp /root/rootfs-4g.img "/mnt/f/小米刷机/米8移植debian/04-实验/rootfs-f6a1f11e.img"; }
E=$(md5sum "$EFI" | awk '{print $1}'); I=$(md5sum "$IMG" | awk '{print $1}')
log "EFI  $(stat -c %s "$EFI")B $E"
log "IMG  $(stat -c %s "$IMG")B $I"
[ "$E" = "$EXP_EFI" ] || { log "!! EFI md5 不符"; exit 1; }
[ "$I" = "$EXP_IMG" ] || { log "!! IMG md5 不符"; exit 1; }

log "=== 1) 等 adb ==="
st=""
for i in $(seq 1 45); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && break
  sleep 2
done
[ "$st" = "device" ] || { log "!! 无 adb（设备需在 Android）"; exit 1; }
log "adb OK"

log "=== 2) 写 ESP ==="
"$ADB" -s "$SER" push "$EFI" /data/local/tmp/net.efi 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/net.efi" | tr -d '\r' | awk '{print $1}')
[ "$D" = "$E" ] || { log "!! push EFI 校验失败"; exit 1; }
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/net.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"
sleep 1
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回 $R"
[ "$R" = "$E" ] || { log "!! ESP 落盘不符"; exit 1; }
log "✅ ESP OK"

log "=== 3) 写 rootfs（4GB push + dd）==="
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img /data/local/tmp/rf2.img"
"$ADB" -s "$SER" push "$IMG" /data/local/tmp/rf2.img 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D2=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/rf2.img" | tr -d '\r' | awk '{print $1}')
log "push md5 $D2"
[ "$D2" = "$I" ] || { log "!! push rootfs 失败"; exit 1; }
"$ADB" -s "$SER" shell "su -c 'umount /data/local/tmp/r 2>/dev/null; dd if=/data/local/tmp/rf2.img of=/dev/block/sda23 bs=4M count=1024 conv=notrunc,fsync 2>&1 | tail -2'" 2>&1 | tr -d '\r' | tee -a "$LOG"
L64=$(head -c 67108864 "$IMG" | md5sum | awk '{print $1}')
D64=$("$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=1M count=64 2>/dev/null | md5sum'" | tr -d '\r' | awk '{print $1}')
log "前64MB 本地=$L64 设备=$D64"
[ "$L64" = "$D64" ] || { log "!! 落盘校验失败"; exit 1; }
log "✅ rootfs OK"

log "=== 4) 引导 ==="
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf2.img /data/local/tmp/net.efi"
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"
log "已 reboot recovery（等 RNDIS 网卡 + ssh 10.55.0.1）"
