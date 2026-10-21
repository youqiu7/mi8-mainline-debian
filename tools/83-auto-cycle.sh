#!/bin/bash
# 83 —— 全链路自动循环：任意设备状态 → Android → 写 ESP(/rootfs) → 引导 → 串口自检
#
# 用法:
#   bash 83-auto-cycle.sh --efi C:/path/BOOTAA64-xxx.efi [--rootfs F:/.../rootfs-xxx.img] [--no-boot]
#
# 能力:
#   * 设备在 Linux（串口 shell 可达）→ 串口发 sync;reboot → 自动回 Android
#   * 设备在 fastboot → erase misc → reboot → 等 Android
#   * 在 Android → push + 设备端 md5 双校验写 ESP；可选 dd rootfs（4GB）
#   * WSL 侧镜像自动 cp 到 F: 盘再 push
#   * reboot recovery → 等串口 → 发探测命令确认 Debian shell 可达
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$PT/adb.exe"
FB="$PT/fastboot.exe"
SER=225bd9ea
PROJ="F:/小米刷机/米8移植debian"
TOOLS="$PROJ/02-工具"
LOG="$TOOLS/83-auto-cycle-$(date +%m%d-%H%M%S).log"
EFI=""
ROOTFS=""
DO_BOOT=1

while [ $# -gt 0 ]; do
  case "$1" in
    --efi) EFI="$2"; shift 2;;
    --rootfs) ROOTFS="$2"; shift 2;;
    --no-boot) DO_BOOT=0; shift;;
    *) echo "未知参数 $1"; exit 2;;
  esac
done
[ -n "$EFI" ] || { echo "必须给 --efi"; exit 2; }

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
adb_state() { "$ADB" devices 2>/dev/null | tr -d '\r' | grep "$SER" | awk '{print $2}'; }
fb_present() { [ "$("$FB" devices 2>/dev/null | grep -c "$SER")" != "0" ]; }
serial_cmd() { python "$TOOLS/com_probe.py" --port COM7 --send "$1" --read "${2:-6}" 2>&1; }

to_android() {
  log "→ 尝试把设备弄到 Android"
  st=$(adb_state)
  [ "$st" = "device" ] && { log "已在 Android"; return 0; }
  if fb_present; then
    log "fastboot: erase misc + reboot"
    "$FB" -s "$SER" erase misc >/dev/null 2>&1
    "$FB" -s "$SER" reboot >/dev/null 2>&1
  elif powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | grep -q COM7; then
    log "串口在：发 sync;reboot 回 Android"
    serial_cmd "sync; reboot" 4 >/dev/null 2>&1
  else
    log "!! 无 adb/fastboot/串口 —— 需要人工开机"
    return 1
  fi
  for i in $(seq 1 60); do
    sleep 3
    [ "$(adb_state)" = "device" ] && { log "adb 就绪 T+$((i*3))s"; return 0; }
  done
  log "!! 等 adb 超时"
  return 1
}

write_esp() {
  local f="$1" exp md5d
  exp=$(md5sum "$f" | awk '{print $1}')
  log "写 ESP: $(basename "$f") md5=$exp"
  "$ADB" -s "$SER" push "$f" /data/local/tmp/payload.efi 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
  md5d=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/payload.efi" | tr -d '\r' | awk '{print $1}')
  [ "$md5d" = "$exp" ] || { log "!! push md5 不同（$md5d）"; return 1; }
  "$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/payload.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && umount /data/local/tmp/esp'" 2>&1 | tr -d '\r' | tee -a "$LOG"
  sleep 1
  local r
  r=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  [ "$r" = "$exp" ] || { log "!! 落盘 md5 不同（$r）"; return 1; }
  log "✅ ESP 落盘 OK"
}

write_rootfs() {
  local f="$1" exp md5d
  exp=$(md5sum "$f" | awk '{print $1}')
  log "写 rootfs: $(basename "$f") md5=$exp ($(stat -c %s "$f") B)"
  "$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img" >/dev/null 2>&1
  "$ADB" -s "$SER" push "$f" /data/local/tmp/rf.img 2>&1 | tail -1 | tr -d '\r' | tee -a "$LOG"
  md5d=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/rf.img" | tr -d '\r' | awk '{print $1}')
  [ "$md5d" = "$exp" ] || { log "!! push rootfs md5 不同"; return 1; }
  "$ADB" -s "$SER" shell "su -c 'umount /data/local/tmp/r 2>/dev/null; dd if=/data/local/tmp/rf.img of=/dev/block/sda23 bs=4M conv=notrunc,fsync 2>&1 | tail -1'" 2>&1 | tr -d '\r' | tee -a "$LOG"
  local l64 d64
  l64=$(head -c 67108864 "$f" | md5sum | awk '{print $1}')
  d64=$("$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=1M count=64 2>/dev/null | md5sum'" | tr -d '\r' | awk '{print $1}')
  [ "$l64" = "$d64" ] || { log "!! 前64MB 校验失败"; return 1; }
  log "✅ rootfs 落盘 OK"
  "$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img" >/dev/null 2>&1
}

wait_serial() {
  local port=""
  for i in $(seq 1 40); do
    port=$(powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()" 2>/dev/null | tr -d '\r' | head -1)
    [ -n "$port" ] && { log "串口出现: $port (T+$((i*3))s)"; return 0; }
    sleep 3
  done
  return 1
}

verify_serial() {
  local out
  for try in 1 2 3 4 5; do
    sleep 8
    out=$(serial_cmd "echo AUTO_OK_$try; uname -r; ip -br a" 8)
    if echo "$out" | grep -q "AUTO_OK_$try"; then
      log "✅ 串口 shell 可达"
      echo "$out" | grep -E "AUTO_OK|6\.[0-9]" | head -5 | tee -a "$LOG"
      return 0
    fi
  done
  log "!! 串口无 shell 响应"
  return 1
}

# ---------------- 主流程 ----------------
log "===== 83 自动循环开始 ====="
log "EFI=$EFI ROOTFS=${ROOTFS:-无}"
# WSL 路径自动转 F:
case "$EFI" in /root/*|/mnt/*) log "EFI 在 WSL 内，复制到 F:"; base=$(basename "$EFI"); wsl.exe -d Debian -u root -- cp "$EFI" "/mnt/f/小米刷机/米8移植debian/04-实验/$base"; EFI="$PROJ/04-实验/$base";; esac
case "$ROOTFS" in /root/*|/mnt/*) log "rootfs 在 WSL 内，复制到 F:"; base=$(basename "$ROOTFS"); wsl.exe -d Debian -u root -- cp "$ROOTFS" "/mnt/f/小米刷机/米8移植debian/04-实验/$base"; ROOTFS="$PROJ/04-实验/$base";; esac

to_android || exit 1
write_esp "$EFI" || exit 1
[ -n "$ROOTFS" ] && { write_rootfs "$ROOTFS" || exit 1; }

if [ "$DO_BOOT" = "1" ]; then
  log "→ reboot recovery"
  "$ADB" -s "$SER" reboot recovery 2>&1 | tr -d '\r' | tee -a "$LOG"
  wait_serial && verify_serial
  log "===== 结束 ====="
else
  log "已写盘，未引导"
fi
