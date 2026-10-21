#!/bin/bash
# 第1步：写 rootfs-4g.img 到 sda23（经 Android + adb + dd）
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
IMG="C:/Users/duoya/AppData/Local/Temp/mi8flash/rootfs-4g.img"
LOG="F:/小米刷机/米8移植debian/02-工具/write-rootfs-sda23.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=========== 1) 通过串口让 Linux 重启回 Android ==========="
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
  \$sp = New-Object System.IO.Ports.SerialPort COM7,115200,'None',8,'One'
  \$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=500
  \$sp.Open(); Start-Sleep -Milliseconds 400
  \$sp.Write('r' + [char]13)
  Start-Sleep -Milliseconds 800
  \$buf=New-Object char[] 256
  try{ \$n=\$sp.Read(\$buf,0,256); Write-Host -NoNewline (-join \$buf[0..(\$n-1)]) }catch{}
  \$sp.Close()
} catch { Write-Host ('串口操作失败: ' + \$_.Exception.Message) }
" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 2) 等 Android + adb（4 分钟）==========="
MODE=""
for i in $(seq 1 48); do
  sleep 5
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; log "adb 就绪 T+$((i*5))s"; break; }
done
[ "$MODE" = "adb" ] || { log "!! 没进 Android，请手动开机"; exit 1; }

log "=========== 3) 前置检查 ==========="
L_SIZE=$(stat -c %s "$IMG")
L_MD5=$(md5sum "$IMG" | awk '{print $1}')
log "本地 rootfs: ${L_SIZE}B md5=$L_MD5"
[ "$L_SIZE" -eq 4294967296 ] || { log "!! 镜像大小异常"; exit 1; }

log "--- 确认 sda23 的存在与大小 ---"
"$ADB" -s "$SER" shell "su -c 'ls -l /dev/block/sda23; cat /proc/partitions | grep sda23'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 4) push 镜像（4GB，需要几分钟）==========="
"$ADB" -s "$SER" push "$IMG" /data/local/tmp/rootfs-4g.img 2>&1 | tail -3 | tr -d '\r' | tee -a "$LOG"

D_MD5=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/rootfs-4g.img" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "push 后设备端 md5=$D_MD5（期望 $L_MD5）"
[ "$D_MD5" = "$L_MD5" ] || { log "!! push 后 md5 不符，中止（不写盘）"; exit 1; }
log "✅ 镜像传输完整"

log "=========== 5) dd 写入 sda23 ==========="
"$ADB" -s "$SER" shell "su -c 'dd if=/data/local/tmp/rootfs-4g.img of=/dev/block/sda23 bs=4M conv=fsync 2>&1 | tail -5'" 2>&1 | tr -d '\r' | tee -a "$LOG"
sync

log "=========== 6) 读回校验（前 4GB 的 md5）==========="
R_MD5=$("$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=4M count=1024 2>/dev/null | md5sum'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "sda23 前4GB md5=$R_MD5（期望 $L_MD5）"
if [ "$R_MD5" = "$L_MD5" ]; then
  log "✅✅ sda23 写入校验通过"
else
  log "!! sda23 读回 md5 不符（可能 dd 未完成或分区异常）"
fi

log "=========== 7) 查看 sda23 的分区内容（ext4 标签）==========="
"$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=1024 skip=1 count=1 2>/dev/null | strings | head -3'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 完成 ==========="
