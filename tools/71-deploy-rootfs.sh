#!/bin/bash
# 71 —— 把修好的 rootfs（72801274）写到 sda23 并引导验证
# 用法: bash 71-deploy-rootfs.sh [--no-reboot]
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
IMG_WIN="$PROJ/04-实验/rootfs-70a4d071.img"
LOG="$PROJ/02-工具/deploy-rootfs.log"
EXP="70a4d0710cf8819a2a12ed102ed5d655"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=========== 0) 准备镜像 ==========="
[ -f "$IMG_WIN" ] || { log "从 WSL 复制 rootfs 到 $IMG_WIN"; wsl.exe -d Debian -u root -- cp /root/rootfs-4g.img "/mnt/f/小米刷机/米8移植debian/04-实验/rootfs-70a4d071.img"; }
L=$(md5sum "$IMG_WIN" | awk '{print $1}')
log "本地 $(stat -c %s "$IMG_WIN")B md5=$L"
[ "$L" = "$EXP" ] || { log "!! md5 不是预期 $EXP"; exit 1; }

log "=========== 1) adb ==========="
st=$("$ADB" devices | tr -d '\r' | grep "$SER" | awk '{print $2}')
[ "$st" = "device" ] || { log "!! 无 adb"; exit 1; }
log "adb OK"

log "=========== 2) push 4G 镜像（约 2 分钟）==========="
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img"
"$ADB" -s "$SER" push "$IMG_WIN" /data/local/tmp/rf.img 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/rf.img" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "设备端 md5=$D"
[ "$D" = "$EXP" ] || { log "!! push 校验失败"; exit 1; }
log "✅ push 校验 OK"

log "=========== 3) dd 写入 sda23 ==========="
"$ADB" -s "$SER" shell "su -c 'umount /data/local/tmp/r 2>/dev/null; dd if=/data/local/tmp/rf.img of=/dev/block/sda23 bs=4M count=1024 conv=notrunc,fsync 2>&1 | tail -3'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 4) 回读前 64MB 校验 ==========="
LOCAL64=$(head -c 67108864 "$IMG_WIN" | md5sum | awk '{print $1}')
DEV64=$("$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=1M count=64 2>/dev/null | md5sum'" | tr -d '\r' | awk '{print $1}')
log "前64MB  本地=$LOCAL64  设备=$DEV64"
[ "$LOCAL64" = "$DEV64" ] || { log "!! 前 64MB 不一致"; exit 1; }
log "✅ 落盘校验 OK"

if [ "${1:-}" = "--no-reboot" ]; then log "跳过引导"; exit 0; fi

log "=========== 5) 引导到 recovery(UEFI) ==========="
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img"
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"
log "已发送 reboot recovery"
