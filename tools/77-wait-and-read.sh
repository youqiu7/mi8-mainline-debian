#!/bin/bash
# 77 —— 后台守候：设备一回到 Android 就自动做只读取证（不改盘）
set -u
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
SER=225bd9ea
echo "[77] 等待 adb（最多 20 分钟）..."
found=0
for i in $(seq 1 240); do
  st=$("$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}')
  if [ "$st" = "device" ]; then echo "[77] adb 就绪 T+$((i*5))s"; found=1; break; fi
  sleep 5
done
[ "$found" = "1" ] || { echo "[77] 超时：设备未回到 Android"; exit 1; }
sleep 5
bash "F:/小米刷机/米8移植debian/02-工具/75-read-logs.sh" 2>&1 | tail -40
echo "[77] 取证完成"
