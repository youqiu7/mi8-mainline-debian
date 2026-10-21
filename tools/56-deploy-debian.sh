#!/bin/bash
# 部署 Debian：串口重启回安卓 → 写 ESP(init v5) → UEFI → 等 Debian 启动
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
LOG="F:/小米刷机/米8移植debian/02-工具/deploy-debian.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=========== 1) 若在 Linux，串口发 r 回 Android ==========="
if powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | grep -q COM; then
  log "检测到串口，发 'r' 重启"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "
  try {
    \$sp = New-Object System.IO.Ports.SerialPort COM7,115200,'None',8,'One'
    \$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=500
    \$sp.Open(); Start-Sleep -Milliseconds 400
    \$sp.Write('r' + [char]13)
    Start-Sleep -Milliseconds 600
    \$sp.Close()
    Write-Host 'r 已发送'
  } catch { Write-Host ('串口失败: ' + \$_.Exception.Message) }
  " 2>&1 | tr -d '\r' | tee -a "$LOG"
fi

log "=========== 2) 等 Android + adb（4 分钟）==========="
MODE=""
for i in $(seq 1 48); do
  sleep 5
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  [ "$st" = "device" ] && { MODE=adb; log "adb 就绪 T+$((i*5))s"; break; }
  [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ] && { MODE=fastboot; log "在 fastboot"; break; }
done

if [ "$MODE" = "fastboot" ]; then
  log "fastboot：清 misc 切安卓"
  "$FB" -s "$SER" erase misc >/dev/null 2>&1
  "$FB" -s "$SER" reboot >/dev/null 2>&1
  for i in $(seq 1 60); do
    sleep 5
    st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
    [ "$st" = "device" ] && { MODE=adb; log "adb 就绪"; break; }
  done
fi
[ "$MODE" = "adb" ] || { log "!! 无 adb（$MODE），请手动开机"; exit 1; }

log "=========== 3) 写 ESP（init v5）==========="
EFI="$WIN/BOOTAA64-debian.efi"
[ -f "$EFI" ] || { log "!! 缺 $EFI"; exit 1; }
L=$(md5sum "$EFI" | awk '{print $1}')
log "本地 $(stat -c %s "$EFI")B md5=$L"

"$ADB" -s "$SER" push "$EFI" /data/local/tmp/BOOTAA64.EFI 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
D=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/BOOTAA64.EFI" 2>/dev/null | tr -d '\r' | awk '{print $1}')
[ "$D" = "$L" ] || { log "!! push md5 不符"; exit 1; }
log "✅ push 校验"

"$ADB" -s "$SER" shell "su -c '
  mount -t vfat /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount /dev/block/sda22 /data/local/tmp/esp
  cp -f BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/ 2>/dev/null
  cp -f /data/local/tmp/BOOTAA64.EFI /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  sync
  md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI
  umount /data/local/tmp/esp
'" 2>&1 | tr -d '\r' | tee -a "$LOG"

sleep 2
R=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp 2>/dev/null || mount -o ro /dev/block/sda22 /data/local/tmp/esp; md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
log "ESP 读回 $R（期望 $L）"
[ "$R" = "$L" ] || { log "!! 落盘不符"; exit 1; }
log "✅ 落盘确认"

log "=========== 4) UEFI 引导（应在串口看到 systemd 启动）==========="
"$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"

log "=========== 5) 等 COM 180 秒 ==========="
PORT=""
for i in $(seq 1 36); do
  sleep 5
  PORT=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
  [ -n "$PORT" ] && { log "✅ COM: $PORT (T+$((i*5))s)"; break; }
done
[ -z "$PORT" ] && { log "!! 无 COM"; exit 1; }

log "=========== 6) 抓 60 秒（看是 init 心跳还是 systemd 日志）==========="
powershell -NoProfile -ExecutionPolicy Bypass -File "F:/小米刷机/米8移植debian/02-工具/read_com.ps1" -Port "$PORT" -Seconds 60 2>&1 \
  | tr -d '\r' | tee -a "$LOG"
log "=========== 完成 ==========="
