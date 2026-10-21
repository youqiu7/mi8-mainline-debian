#!/bin/bash
# 72 —— Android 侧就地修改 rootfs：注入 proof 服务（不整盘重写，秒级）
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
INJ="$PROJ/04-实验/p3/inject"
OUT="$PROJ/04-实验/rootfs-inspect-$(date +%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/inject.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

st=""
for i in $(seq 1 45); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && break
  sleep 2
done
[ "$st" = "device" ] || { log "!! 无 adb"; exit 1; }
log "adb OK"

"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/inj'" 2>&1 | tr -d '\r'
"$ADB" -s "$SER" push "$INJ/proof.sh" /data/local/tmp/inj/proof.sh 2>&1 | tail -1 | tr -d '\r'
"$ADB" -s "$SER" push "$INJ/proof.service" /data/local/tmp/inj/proof.service 2>&1 | tail -1 | tr -d '\r'

log "=== 挂载 sda23 并取证/注入 ==="
"$ADB" -s "$SER" shell "su -c '
  umount /data/local/tmp/r 2>/dev/null
  mkdir -p /data/local/tmp/r
  mount -t ext4 /dev/block/sda23 /data/local/tmp/r || { echo MOUNT_FAIL; exit 1; }
  echo \"--- var/log ---\"; ls -la /data/local/tmp/r/var/log/ 2>/dev/null
  echo \"--- first-boot.log (tail 40) ---\"; tail -40 /data/local/tmp/r/var/log/first-boot.log 2>/dev/null
  echo \"--- first-boot-done? ---\"; ls -l /data/local/tmp/r/var/lib/first-boot-done 2>/dev/null || echo \"(未完成)\"
  echo \"--- journal 目录 ---\"; ls -la /data/local/tmp/r/var/log/journal/*/ 2>/dev/null | tail -12
  echo \"--- 注入 proof ---\"
  cp /data/local/tmp/inj/proof.sh /data/local/tmp/r/usr/local/sbin/proof.sh
  chmod 755 /data/local/tmp/r/usr/local/sbin/proof.sh
  cp /data/local/tmp/inj/proof.service /data/local/tmp/r/etc/systemd/system/proof.service
  ln -sf /etc/systemd/system/proof.service /data/local/tmp/r/etc/systemd/system/multi-user.target.wants/proof.service
  ls -l /data/local/tmp/r/etc/systemd/system/multi-user.target.wants/ | grep -E \"proof|getty\"
  sync
  echo \"--- 打包日志 ---\"
  cd /data/local/tmp/r/var/log && tar czf /data/local/tmp/logs.tgz journal first-boot.log 2>/dev/null
  ls -l /data/local/tmp/logs.tgz
  umount /data/local/tmp/r && echo UMOUNT_OK
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

"$ADB" -s "$SER" pull /data/local/tmp/logs.tgz "$OUT/logs.tgz" 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
log "输出: $OUT"
