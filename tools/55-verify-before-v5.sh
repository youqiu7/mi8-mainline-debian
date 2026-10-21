#!/bin/bash
# 动 init v5 之前的强制校验（全部只读，不改设备、不改镜像）
# 任一项 FAIL → 不许继续
set -uo pipefail

P="/mnt/f/小米刷机/米8移植debian"
A="$P/03-备份/锚点-20261021-0515"
K=/root/k619/linux-6.19.14
SRC="$P/04-实验/p3"
WIN="/mnt/c/Users/duoya/AppData/Local/Temp/mi8flash"

PASS=0; FAIL=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
note() { echo "  [info] $*"; }

echo "=============================================="
echo "  动 init v5 之前的校验（只读）"
echo "=============================================="

echo
echo "--- 1) 内核镜像与 md5 ---"
IMG="$WIN/BOOTAA64-ext4.efi"
if [ -f "$IMG" ]; then
  SZ=$(stat -c %s "$IMG"); M=$(md5sum "$IMG" | awk '{print $1}')
  note "文件 $SZ B  md5=$M"
  [ "$M" = "eeb176a20c7bfac007408ce2a687f354" ] && ok "md5 与锚点一致（当前可启动版）" || bad "md5 与锚点不一致"
else
  bad "缺 $IMG"
fi

echo
echo "--- 2) cmdline 里不能有 dtb= ---"
if [ -f "$K/.config" ]; then
  CL=$(grep '^CONFIG_CMDLINE=' "$K/.config")
  note "$CL"
  echo "$CL" | grep -q "dtb=" && bad "cmdline 含 dtb=（会导致 panic）" || ok "cmdline 无 dtb="
else
  bad "缺 .config"
fi

echo
echo "--- 3) dtb reserved-memory 必须 = 23 ---"
DTB="$P/04-实验/p1/sdm845-xiaomi-equuleus.dtb"
if [ -f "$DTB" ]; then
  dtc -I dtb -O dts -o /tmp/vfy.dts "$DTB" 2>/dev/null
  RM=$(grep -c "reserved-memory" /tmp/vfy.dts)
  MEM=$(grep -c "memory@" /tmp/vfy.dts)
  NODES=$(grep -cE "^\s*[a-zA-Z0-9_@,.-]+ \{" /tmp/vfy.dts)
  note "dtb $(stat -c %s "$DTB") B  节点=$NODES memory@=$MEM reserved-memory=$RM"
  [ "$RM" -eq 23 ] && ok "reserved-memory = 23" || bad "reserved-memory = $RM（应 23）"
else
  bad "缺 dtb"
fi

echo
echo "--- 4) init v5 能否静态编译 ---"
if [ -f "$SRC/init_v5.c" ]; then
  if aarch64-linux-gnu-gcc -static -O2 -o /tmp/init_v5_test "$SRC/init_v5.c" 2>/tmp/v5.err; then
    ok "编译成功 $(stat -c %s /tmp/init_v5_test) B"
  else
    bad "编译失败："; head -5 /tmp/v5.err
  fi
else
  bad "缺 init_v5.c"
fi

echo
echo "--- 5) init v5 关键特征 ---"
if [ -f /tmp/init_v5_test ]; then
  PR=$(strings /tmp/init_v5_test | grep -c "pivot_root" || true)
  SD=$(strings /tmp/init_v5_test | grep -c "sda23" || true)
  note "pivot_root=$PR  sda23=$SD"
  [ "$PR" -ge 1 ] && ok "含 pivot_root" || bad "缺 pivot_root"
  [ "$SD" -ge 1 ] && ok "含 sda23" || bad "缺 sda23"
fi

echo
echo "--- 6) rootfs 镜像可挂载且关键文件齐全 ---"
RIMG="$WIN/rootfs-4g.img"
if [ -f "$RIMG" ]; then
  M=$(md5sum "$RIMG" | awk '{print $1}')
  note "镜像 $(stat -c %s "$RIMG") B md5=$M"
  [ "$M" = "340125ab17dbf81f612b464e77e402b5" ] && ok "md5 与锚点一致" || bad "md5 与锚点不一致"

  mkdir -p /mnt/vfy
  if mount -o loop,ro "$RIMG" /mnt/vfy 2>/dev/null; then
    for f in sbin/init lib/systemd/systemd usr/bin/systemctl usr/sbin/wpa_supplicant usr/sbin/resize2fs usr/sbin/sshd; do
      [ -e "/mnt/vfy/$f" ] && ok "rootfs: $f" || bad "rootfs 缺 $f"
    done
    grep -q "^youqi:" /mnt/vfy/etc/passwd && ok "rootfs: youqi 用户" || bad "rootfs 缺 youqi"
    grep -q 'ssid="OPPO A5-5G"' /mnt/vfy/etc/wpa_supplicant/wpa_supplicant-wlan0.conf 2>/dev/null \
      && ok "rootfs: WiFi 配置" || bad "rootfs 缺 WiFi 配置"
    [ -f /mnt/vfy/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin ] && ok "rootfs: WCN3990 固件" || bad "rootfs 缺 WCN3990 固件"
    umount /mnt/vfy
  else
    bad "镜像挂载失败"
  fi
else
  bad "缺 rootfs 镜像"
fi

echo
echo "--- 7) rootfs fsck ---"
if [ -f "$RIMG" ]; then
  if e2fsck -fn "$RIMG" >/tmp/fsck.out 2>&1; then
    ok "fsck 干净"
  else
    bad "fsck 报错："; tail -3 /tmp/fsck.out
  fi
fi

echo
echo "--- 8) 锚点完整性 ---"
if [ -f "$A/md5-manifest.txt" ]; then
  cd "$A"
  BADN=$(md5sum -c md5-manifest.txt 2>/dev/null | grep -c "FAILED" || true)
  [ "$BADN" -eq 0 ] && ok "锚点 md5 全部匹配（$(wc -l < md5-manifest.txt) 个文件）" || bad "锚点有 $BADN 个文件 md5 不符"
else
  bad "缺 md5 清单"
fi

echo
echo "--- 9) 回滚基线可用性 ---"
for f in "$A/01-boot/BOOTAA64-v3final.efi" "$A/01-boot/BOOTAA64-ext4.efi" "$A/01-boot/recovery-原厂.img"; do
  [ -f "$f" ] && ok "可回滚: $(basename "$f")" || bad "缺 $(basename "$f")"
done

echo
echo "=============================================="
echo "  结果：PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✅ 全部通过，可以开始改 init v5"
  exit 0
else
  echo "  ❌ 有 $FAIL 项未通过，禁止改 init"
  exit 1
fi
