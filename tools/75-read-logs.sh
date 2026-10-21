#!/bin/bash
# 75 —— 只读取证：挂 sda23(ro)，拉 journal + first-boot.log
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
OUT="$PROJ/04-实验/journal-latest"
mkdir -p "$OUT"
LOG="$OUT/read.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

st=""
for i in $(seq 1 50); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && break
  sleep 3
done
[ "$st" = "device" ] || { log "!! 无 adb"; exit 1; }
log "adb OK"

log "=== 挂载 + 打包 ==="
"$ADB" -s "$SER" shell "su -c '
  umount /data/local/tmp/r 2>/dev/null
  mkdir -p /data/local/tmp/r
  mount -t ext4 -o ro,noload /dev/block/sda23 /data/local/tmp/r || { echo MOUNT_FAIL; exit 1; }
  echo \"--- journal 文件 ---\"; ls -la /data/local/tmp/r/var/log/journal/*/ 2>/dev/null
  echo \"--- var/log 列表 ---\"; ls -la /data/local/tmp/r/var/log/ | head -25
  echo \"--- first-boot.log ---\"; tail -40 /data/local/tmp/r/var/log/first-boot.log 2>/dev/null || echo \"(无)\"
  echo \"--- first-boot-done ---\"; ls -l /data/local/tmp/r/var/lib/first-boot-done 2>/dev/null || echo \"(无)\"
  echo \"--- df ---\"; df -h /data/local/tmp/r | tail -2
  rm -f /data/local/tmp/l.tgz
  tar czf /data/local/tmp/l.tgz -C /data/local/tmp/r/var/log journal first-boot.log 2>/dev/null
  ls -l /data/local/tmp/l.tgz
  umount /data/local/tmp/r && echo UMOUNT_OK
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

"$ADB" -s "$SER" pull /data/local/tmp/l.tgz "$OUT/logs.tgz" 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
log "输出: $OUT"
