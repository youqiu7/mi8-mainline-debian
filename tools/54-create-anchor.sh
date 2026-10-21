#!/bin/bash
# 建立锚点：备份当前可启动状态的全部关键层（配置 / boot / rootfs）
set -uo pipefail

P="/mnt/f/小米刷机/米8移植debian"
A="$P/03-备份/锚点-20261021-0515"
WIN="/mnt/c/Users/duoya/AppData/Local/Temp/mi8flash"
K=/root/k619/linux-6.19.14

mkdir -p "$A"/{01-boot,02-esp,03-rootfs,04-config,05-scripts}

echo "=========== 1) boot 层（UEFI + 内核产物）==========="
cp -v "$WIN/boot-equuleus.img"      "$A/01-boot/" 2>&1 | tail -1
cp -v "$WIN/BOOTAA64-v3final.efi"   "$A/01-boot/" 2>&1 | tail -1
cp -v "$WIN/BOOTAA64-ext4.efi"      "$A/01-boot/" 2>&1 | tail -1
cp -v "$P/03-备份/bk_recovery.img"  "$A/01-boot/recovery-原厂.img" 2>&1 | tail -1

echo
echo "=========== 2) ESP 层（当前实际在 ESP 里的文件）==========="
if [ -d /e/EFI/Boot ]; then
  cp -v /e/EFI/Boot/BOOTAA64.EFI "$A/02-esp/BOOTAA64.EFI.running" 2>&1 | tail -1
  cp -v /e/equuleus.dtb          "$A/02-esp/equuleus.dtb.running" 2>&1 | tail -1
  ls -l /e/EFI/Boot/ 2>&1 | tee "$A/02-esp/ESP-listing.txt"
else
  echo "  !! E: 盘不可用（UMS 未挂），跳过 ESP 抓取"
fi

echo
echo "=========== 3) rootfs 层 ==========="
cp -v "$WIN/rootfs-4g.img" "$A/03-rootfs/rootfs-4g.img" 2>&1 | tail -1
ls -l "$A/03-rootfs/" 2>&1 | tail -2

echo
echo "=========== 4) config 层（内核配置 + cmdline）==========="
cp -v "$K/.config" "$A/04-config/kernel.config" 2>&1 | tail -1
grep -E "^CONFIG_(EXT4_FS|CMDLINE|INITRAMFS_SOURCE|ATH10K_SNOC)=" "$K/.config" > "$A/04-config/key-options.txt" 2>&1
cat "$A/04-config/key-options.txt"

echo
echo "=========== 5) 脚本层 =========="
for f in "$P/02-工具/auto-v3final.sh" "$P/02-工具/52-test-ext4.sh" \
         "$P/02-工具/50-write-rootfs-sda23.sh" \
         "$P/04-实验/p3/47-rebuild-v3.sh" "$P/04-实验/p3/49-rebuild-v3-nodtb.sh" \
         "$P/04-实验/p3/51-add-ext4.sh" "$P/04-实验/p3/53-build-debian-boot.sh" \
         "$P/04-实验/p1/init_v3.c" "$P/04-实验/p3/init_v5.c"; do
  [ -f "$f" ] && cp "$f" "$A/05-scripts/" 2>/dev/null
done
ls "$A/05-scripts/" 2>&1

echo
echo "=========== 6) 生成 md5 清单 ==========="
cd "$A"
find . -type f ! -name "md5-manifest.txt" -exec md5sum {} \; > md5-manifest.txt 2>/dev/null
cat md5-manifest.txt

echo
echo "=========== 7) 统计 ==========="
du -sh "$A"
echo "锚点目录: $A"
