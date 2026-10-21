#!/bin/bash
# ============================================================
# 米8系列 Debian 安装器 · 配套 06-安装包（单版本制）
# 用法:
#   bash install.sh --serial <sn> [选项]
# 选项:
#   --serial <sn>    目标设备 adb/fastboot serial（必填，多台时必填）
#   --boot           阶段1: 刷 UEFI 外壳到 boot 分区（fastboot 或 Android dd 二选一自动）
#   --efi <file>     默认: 同目录 BOOTAA64-*.efi（取本包内唯一一份）
#   --rootfs <img>   默认: 同目录 rootfs-*.img
#   --tools <dir>    platform-tools 目录（含 adb.exe/fastboot.exe）
#   --key <file>     SSH 私钥（默认: %TMPDIR%/mi8flash/dagu_key 或同目录 dagu_key）
#   --com <port>     串口（默认自动扫描第一个可用口）
#   --skip-efs       跳过阶段6（本机 EFS 提取；不建议跳过——IMEI 属于每台设备自己）
#   --no-boot        写完 ESP/rootfs 后不引导（仅落盘）
# 阶段: 0前置 → 1刷UEFI → 2到Android → 2.5提EFS → 3写ESP → 4写rootfs → 5引导 → 6装EFS+终验
# ============================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="$HERE/install-$(date +%m%d-%H%M%S).log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
die() { log "!! $*"; exit 1; }

SER="" DO_BOOT=0 DO_REBOOT=1 SKIP_EFS=0 TOOLS="" KEY="" COM=""
EFI="$(ls "$HERE"/BOOTAA64-*.efi 2>/dev/null | head -1)"
ROOTFS="$(ls "$HERE"/rootfs-*.img 2>/dev/null | head -1)"
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SER="$2"; shift 2;;
    --boot) DO_BOOT=1; shift;;
    --efi) EFI="$2"; shift 2;;
    --rootfs) ROOTFS="$2"; shift 2;;
    --tools) TOOLS="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --com) COM="$2"; shift 2;;
    --skip-efs) SKIP_EFS=1; shift;;
    --no-boot) DO_REBOOT=0; shift;;
    *) die "未知参数 $1";;
  esac
done

# ---- 默认值解析 ----
[ -n "$TOOLS" ] || TOOLS="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
ADB="$TOOLS/adb.exe"; FB="$TOOLS/fastboot.exe"
[ -x "$ADB" ] || die "找不到 adb: $ADB（用 --tools 指定 platform-tools 目录）"
[ -n "$EFI" ] && [ -f "$EFI" ] || die "找不到 BOOTAA64-*.efi"
[ -n "$ROOTFS" ] && [ -f "$ROOTFS" ] || die "找不到 rootfs-*.img"
if [ -z "$KEY" ]; then
  for k in "$HERE/dagu_key" "$TMPDIR/mi8flash/dagu_key" "$LOCALAPPDATA/Temp/mi8flash/dagu_key"; do
    [ -f "$k" ] && { KEY="$k"; break; }
  done
fi
if [ -z "$SER" ]; then
  n=$("$ADB" devices | grep -cw device)
  [ "$n" = "1" ] || die "adb 设备数=$n，必须 --serial 指定"
  SER=$("$ADB" devices | grep -w device | awk '{print $1}')
fi
adb_state() { "$ADB" -s "$SER" devices 2>/dev/null | tr -d '\r' | awk '$1=="'"$SER"'"{print $2}'; }
fb_present() { "$FB" devices 2>/dev/null | grep -q "$SER"; }
ssh_cmd() { ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@169.254.1.1 "$@"; }

log "===== 米8 Debian 安装开始 serial=$SER ====="
log "EFI=$(basename "$EFI")  ROOTFS=$(basename "$ROOTFS")"

# ---------- 阶段1: 刷 UEFI 外壳 ----------
if [ "$DO_BOOT" = "1" ]; then
  bootimg="$HERE/boot-equuleus.img"
  [ -f "$bootimg" ] || die "缺 boot-equuleus.img"
  if fb_present; then
    log "阶段1: fastboot flash boot"
    "$FB" -s "$SER" flash boot "$bootimg" || die "flash boot 失败"
  else
    log "阶段1: Android dd → by-name/boot（设备需 adb+root）"
    [ "$(adb_state)" = "device" ] || die "设备不在 Android 也不在 fastboot，先手动处理"
    "$ADB" -s "$SER" push "$bootimg" /data/local/tmp/boot.img || die "push boot 失败"
    "$ADB" -s "$SER" shell "su -c 'dd if=/data/local/tmp/boot.img of=/dev/block/by-name/boot bs=4M && sync'" || die "dd boot 失败"
    "$ADB" -s "$SER" shell "su -c 'rm /data/local/tmp/boot.img'"
  fi
  log "✅ UEFI 外壳已写入 boot 分区"
fi

# ---------- 阶段2: 到 Android ----------
log "阶段2: 确保设备在 Android"
if [ "$(adb_state)" != "device" ]; then
  if fb_present; then
    "$FB" -s "$SER" erase misc >/dev/null 2>&1
    "$FB" -s "$SER" reboot || die "fastboot reboot 失败（本平台可能拒绝，手动长按电源重进系统）"
  else
    die "设备既不在 adb 也不在 fastboot"
  fi
  for i in $(seq 1 60); do sleep 3; [ "$(adb_state)" = "device" ] && break; done
  [ "$(adb_state)" = "device" ] || die "等 Android 超时"
fi
log "✅ Android 就绪"

# ---------- 阶段2.5: 提取本机 EFS（IMEI/校准，必须是本机自己的） ----------
EFSHOLD="$HERE/.efs-$SER"
if [ "$SKIP_EFS" = "0" ]; then
  log "阶段2.5: 提取本机 modemst → $EFSHOLD"
  mkdir -p "$EFSHOLD"
  ok=0
  for p in modemst1 modemst2; do
    if "$ADB" -s "$SER" shell "su -c 'test -e /dev/block/by-name/$p'" 2>/dev/null | tr -d '\r' | grep -q ""; then
      "$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/by-name/$p of=/data/local/tmp/$p.img bs=4096'" >/dev/null 2>&1
      "$ADB" -s "$SER" pull "/data/local/tmp/$p.img" "$EFSHOLD/$p.img" >/dev/null 2>&1 && ok=$((ok+1))
      "$ADB" -s "$SER" shell "su -c 'rm -f /data/local/tmp/$p.img'" >/dev/null 2>&1
    fi
  done
  [ "$ok" = "2" ] || log "!! modemst 提取 $ok/2（若新设备分区名不同请手动放 $EFSHOLD）"
  log "✅ EFS 提取完成（$ok/2）"
fi

# ---------- 阶段3: 写 ESP ----------
log "阶段3: 写 ESP"
exp=$(md5sum "$EFI" | awk '{print $1}')
"$ADB" -s "$SER" push "$EFI" /data/local/tmp/payload.efi >/dev/null || die "push EFI 失败"
md5d=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/payload.efi" | tr -d '\r' | awk '{print $1}')
[ "$md5d" = "$exp" ] || die "push md5 不同 ($md5d != $exp)"
"$ADB" -s "$SER" shell "su -c 'mkdir -p /data/local/tmp/esp && mount -t vfat /dev/block/sda22 /data/local/tmp/esp && cp -f /data/local/tmp/payload.efi /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI && sync && umount /data/local/tmp/esp'" >/dev/null || die "写 ESP 失败"
r=$("$ADB" -s "$SER" shell "su -c 'mount -t vfat -o ro /dev/block/sda22 /data/local/tmp/esp && md5sum /data/local/tmp/esp/EFI/Boot/BOOTAA64.EFI; umount /data/local/tmp/esp'" 2>/dev/null | tr -d '\r' | awk '{print $1}')
[ "$r" = "$exp" ] || die "ESP 落盘 md5 不同 ($r)"
log "✅ ESP 落盘 OK"

# ---------- 阶段4: 写 rootfs ----------
log "阶段4: 写 rootfs（约 1 分钟）"
exp=$(md5sum "$ROOTFS" | awk '{print $1}')
"$ADB" -s "$SER" push "$ROOTFS" /data/local/tmp/rf.img >/dev/null || die "push rootfs 失败"
md5d=$("$ADB" -s "$SER" shell "md5sum /data/local/tmp/rf.img" | tr -d '\r' | awk '{print $1}')
[ "$md5d" = "$exp" ] || die "push rootfs md5 不同"
"$ADB" -s "$SER" shell "su -c 'dd if=/data/local/tmp/rf.img of=/dev/block/sda23 bs=4M conv=notrunc,fsync 2>&1 | tail -1'" | tr -d '\r' | tee -a "$LOG"
l64=$(head -c 67108864 "$ROOTFS" | md5sum | awk '{print $1}')
d64=$("$ADB" -s "$SER" shell "su -c 'dd if=/dev/block/sda23 bs=1M count=64 2>/dev/null | md5sum'" | tr -d '\r' | awk '{print $1}')
[ "$l64" = "$d64" ] || die "rootfs 前64MB 校验失败"
"$ADB" -s "$SER" shell "rm -f /data/local/tmp/rf.img" >/dev/null
log "✅ rootfs 落盘 OK"

# ---------- 阶段5: 引导 ----------
if [ "$DO_REBOOT" = "1" ]; then
  log "阶段5: reboot recovery → 等 Debian"
  "$ADB" -s "$SER" reboot recovery
  for i in $(seq 1 50); do sleep 3; ssh_cmd true 2>/dev/null && break; done
  ssh_cmd true || die "Debian 未起来——串口/屏幕取证（见 安装指南 判读表）"
  log "✅ Debian SSH 可达"
else
  log "已写盘未引导（--no-boot）"
  exit 0
fi

# ---------- 阶段6: EFS 入位 + 终验 ----------
if [ "$SKIP_EFS" = "0" ] && [ -f "$EFSHOLD/modemst1.img" ]; then
  log "阶段6: EFS 入位 /var/lib/rmtfs"
  ssh_cmd "mkdir -p /var/lib/rmtfs"
  scp -i "$KEY" -o StrictHostKeyChecking=no "$EFSHOLD/modemst1.img" root@169.254.1.1:/var/lib/rmtfs/modem_fs1
  scp -i "$KEY" -o StrictHostKeyChecking=no "$EFSHOLD/modemst2.img" root@169.254.1.1:/var/lib/rmtfs/modem_fs2
  ssh_cmd "chmod 644 /var/lib/rmtfs/modem_fs1 /var/lib/rmtfs/modem_fs2
           for f in modem_fsc modem_fsg modem_study modem_tunning modem_tng modem_fsg_oem_1 modem_fsg_oem_2; do
             [ -e /var/lib/rmtfs/\$f ] || truncate -s \$([ \$f = modem_fsc -o \$f = modem_fsg ] && echo 64M || echo 8M) /var/lib/rmtfs/\$f
           done
           chown -R root:root /var/lib/rmtfs; chmod 644 /var/lib/rmtfs/*
           systemctl restart rmtfs && systemctl is-active rmtfs"
  log "✅ EFS 就位，rmtfs 重启"
fi
log "===== 终验 ====="
ssh_cmd "df -h / | tail -1; ls /dev/qcom_rmtfs_mem1 2>/dev/null || echo 'rmtfs_mem 驱动未开(预期内,路线A)'; \
         systemctl is-active rmtfs pd-mapper tqftpserv ssh; \
         test -e /var/lib/first-boot-done && echo FIRSTBOOT_DONE=OK || echo FIRSTBOOT_DONE=未跑; \
         ip -br a | head -3; hostname"
log "===== 安装完成 ====="
log "后续: 屏幕/触摸看 00-文档/23号；WiFi 看 25号（modem 保持 mss-start disabled 直到路线A）"
