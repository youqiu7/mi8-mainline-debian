#!/bin/bash
# 66 —— 在 Android 侧取证：挂 sda23，抓 journal / 日志 / 状态（只读挂载）
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
OUT="$PROJ/04-实验/journal-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/collect.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 等 adb ==="
for i in $(seq 1 40); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { log "adb 就绪 T+$((i*2))s"; break; }
  sleep 2
done
[ "${st:-}" = "device" ] || { log "!! 无 adb"; exit 1; }

log "=== 挂载 sda23 (ro) ==="
"$ADB" -s "$SER" shell "su -c '
  umount /data/local/tmp/r 2>/dev/null
  mkdir -p /data/local/tmp/r
  mount -t ext4 -o ro,noload /dev/block/sda23 /data/local/tmp/r || mount -t ext4 -o ro /dev/block/sda23 /data/local/tmp/r
  echo \"--- mount ---\"; grep sda23 /proc/mounts
  echo \"--- var/log ---\"; ls -la /data/local/tmp/r/var/log 2>/dev/null | head -20
  echo \"--- journal dir ---\"; ls -la /data/local/tmp/r/var/log/journal 2>/dev/null
  echo \"--- 最后挂载时间 ---\"; stat -c \"%y %n\" /data/local/tmp/r/var/log 2>/dev/null
  echo \"--- 内核 modules ---\"; ls /data/local/tmp/r/lib/modules 2>/dev/null
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 打包 journal ==="
"$ADB" -s "$SER" shell "su -c '
  cd /data/local/tmp/r/var/log 2>/dev/null && tar czf /data/local/tmp/journal.tgz journal syslog* messages* 2>/dev/null
  ls -l /data/local/tmp/journal.tgz
'" 2>&1 | tr -d '\r' | tee -a "$LOG"
"$ADB" -s "$SER" pull /data/local/tmp/journal.tgz "$OUT/journal.tgz" 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"

log "=== dump systemd 状态文件 ==="
"$ADB" -s "$SER" shell "su -c '
  echo \"=== default.target ===\"; readlink -f /data/local/tmp/r/etc/systemd/system/default.target 2>/dev/null; ls -l /data/local/tmp/r/usr/lib/systemd/system/default.target 2>/dev/null
  echo \"=== timestamps ===\"; ls -ld --time-style=+%F_%T /data/local/tmp/r/var/log/journal/* 2>/dev/null
  umount /data/local/tmp/r
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "输出目录: $OUT"
ls -la "$OUT"
