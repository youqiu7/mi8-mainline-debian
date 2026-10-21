#!/bin/bash
# 查 sda23 被谁占用（sysfs holders + /proc/mounts + dm 映射）
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
LOG="F:/小米刷机/米8移植debian/02-工具/check-sda23.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 1) 串口 'r' 回 Android ==="
powershell -NoProfile -ExecutionPolicy Bypass -Command "
try {
  \$sp = New-Object System.IO.Ports.SerialPort COM7,115200,'None',8,'One'
  \$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=400
  \$sp.Open(); Start-Sleep -Milliseconds 400
  \$sp.Write('r' + [char]13)
  Start-Sleep -Milliseconds 500
  \$sp.Close(); Write-Host 'r sent'
} catch { Write-Host ('serial fail: ' + \$_.Exception.Message) }
" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 2) 等 adb ==="
for i in $(seq 1 48); do
  sleep 5
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { log "adb 就绪"; break; }
done

log "=== 3) sda23 的占用调查 ==="
"$ADB" -s "$SER" shell "su -c '
echo \"--- /proc/partitions (sda23) ---\"
grep sda23 /proc/partitions
echo \"--- /proc/mounts 里和 sda23 / dm 相关的 ---\"
grep -E \"sda23|dm-\" /proc/mounts
echo \"--- sda23 的 holders ---\"
ls -l /sys/class/block/sda23/holders/ 2>/dev/null || echo \"(无 holders)\"
echo \"--- sda23 的 slaves ---\"
ls -l /sys/class/block/sda23/slaves/ 2>/dev/null || echo \"(无 slaves)\"
echo \"--- 上层设备（partition of）---\"
readlink -f /sys/class/block/sda23 2>/dev/null
echo \"--- device-mapper 列表 ---\"
ls /dev/device-mapper/ 2>/dev/null || ls /dev/dm-* 2>/dev/null || echo \"(无 dm)\"
echo \"--- vold 挂载状态 ---\"
cat /proc/mounts | grep -E \"sda2[0-9]|mindows\" || echo \"(vold 未挂 sda2x)\"
echo \"--- 谁在用这个分区（lsof 替代：查 /sys/block/*/holders）---\"
for d in /sys/block/sda/sda23/holders/*; do [ -e \"\$d\" ] && echo \"holder: \$(basename \$d)\"; done
echo \"--- block 设备 open 计数 ---\"
cat /sys/class/block/sda23/stat 2>/dev/null
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 4) 尝试在 Android 上挂载 sda23（是否也 EBUSY）==="
"$ADB" -s "$SER" shell "su -c '
mkdir -p /data/local/tmp/t23
mount -t ext4 -o ro /dev/block/sda23 /data/local/tmp/t23 2>&1
echo \"mount rc=\$?\"
ls /data/local/tmp/t23 2>/dev/null | head -5
umount /data/local/tmp/t23 2>/dev/null
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=== 完成 ==="
