#!/bin/bash
# 90 —— 建立新锚点（20261021-0520）：串口可用 + USB-NCM/SSH 可用 + WiFi 驱动内建
set -u
A="F:/小米刷机/米8移植debian/03-备份/锚点-20261021-0520"
WIN="C:/Users/duoya/AppData/Local/Temp/mi8flash"
PROJ="F:/小米刷机/米8移植debian"
OLD="$PROJ/03-备份/锚点-20261021-0515"
SSHKEY="/c/Users/duoya/.ssh/dagu_key"
log() { echo "[$(date +%H:%M:%S)] $*"; }

mkdir -p "$A"/{01-boot,02-esp,03-rootfs,04-config,05-scripts}

log "=== 01-boot ==="
cp -f "$WIN/BOOTAA64-wifi2.efi" "$A/01-boot/BOOTAA64-wifi2-00b17e15.efi"
cp -f "$WIN/BOOTAA64-wifi.efi"  "$A/01-boot/BOOTAA64-wifi-5c977dce.efi"
cp -f "$WIN/BOOTAA64-ncm.efi"   "$A/01-boot/BOOTAA64-ncm-7989f352.efi"
cp -f "$WIN/BOOTAA64-net.efi"   "$A/01-boot/BOOTAA64-rndis-98eea6b2.efi"
cp -f "$WIN/BOOTAA64-debian.efi" "$A/01-boot/BOOTAA64-badcmdline-0c25619f.efi"
cp -f "$PROJ/03-备份/esp-boot-20261021-040450.EFI" "$A/01-boot/BOOTAA64-ueficmdline-deb0b27b.efi"
cp -f "$OLD/01-boot/boot-equuleus.img" "$A/01-boot/"
cp -f "$OLD/01-boot/recovery-原厂.img" "$A/01-boot/"
cp -f "$OLD/01-boot/BOOTAA64-v3final.efi" "$A/01-boot/"

log "=== 02-esp 快照 ==="
cp -f "$WIN/BOOTAA64-wifi2.efi" "$A/02-esp/BOOTAA64.EFI.running"
cp -f "$PROJ/04-实验/p1/sdm845-xiaomi-equuleus-wifi.dtb" "$A/02-esp/equuleus-wifi.dtb"

log "=== 03-rootfs（4GB 干净镜像）==="
cp -f "$PROJ/04-实验/rootfs-f6a1f11e.img" "$A/03-rootfs/rootfs-4g-f6a1f11e.img"

log "=== 03-rootfs 运行时增量（非镜像内改动）==="
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@169.254.1.1 \
  'tar czf - -C / etc/systemd/system/usb0-static.service root/.ssh/authorized_keys var/log/proof.log var/log/first-boot.log 2>/dev/null' \
  > "$A/03-rootfs/runtime-incremental.tgz" 2>/dev/null
ls -l "$A/03-rootfs/runtime-incremental.tgz"

log "=== 04-config ==="
wsl.exe -d Debian -u root -- cp /root/k619/linux-6.19.14/.config "/mnt/f/小米刷机/米8移植debian/03-备份/锚点-20261021-0520/04-config/kernel.config"
wsl.exe -d Debian -u root -- bash -c 'grep -E "^CONFIG_(CMDLINE|CMDLINE_FORCE|ARCH_QCOM|SCSI_UFS_QCOM|EXT4_FS|CFG80211|MAC80211|ATH10K|ATH10K_SNOC|QRTR|QCOM_RPROC_COMMON|QCOM_QMI_HELPERS|USB_CONFIGFS_(ACM|NCM|RNDIS))=" /root/k619/linux-6.19.14/.config' > "$A/04-config/key-options.txt" 2>/dev/null
cat "$A/04-config/key-options.txt"

log "=== 05-scripts ==="
cp -f "$PROJ/04-实验/p3/init_v5.c" "$PROJ/04-实验/p3/init_v6.c" "$PROJ/04-实验/p3/init_v7.c" "$A/05-scripts/" 2>/dev/null
for f in 44-rebuild-dtb-verified.sh 64-verify-rootfs-state.sh 68-fix-rootfs-entropy.sh 70-fix-firstboot-merge.sh \
         76-fix-serial-console.sh 78-build-net-image.sh 79-add-usbnet.sh 81-build-ncm-image.sh \
         84-dtb-wifi.sh 85-build-wifi-image.sh 86-pack-wifi.sh 87-add-firmware.sh 88-fix-wifi-rootfs.sh 89-build-wifi-initramfs.sh; do
  cp -f "$PROJ/04-实验/p3/$f" "$A/05-scripts/" 2>/dev/null
done
for f in 65-deploy-cmdline-force.sh 71-deploy-rootfs.sh 74-write-esp-deb0b27b.sh 80-net-deploy.sh 82-write-esp-ncm.sh \
         83-auto-cycle.sh 66-collect-journal.sh 75-read-logs.sh com_probe.py com_monitor.py; do
  cp -f "$PROJ/02-工具/$f" "$A/05-scripts/" 2>/dev/null
done
cp -f "$PROJ/04-实验/p1/sdm845-xiaomi-equuleus.dts" "$A/05-scripts/sdm845-xiaomi-equuleus-wifi.dts"
ls "$A/05-scripts/" | head -30

log "=== md5 manifest ==="
cd "$A" && find . -type f ! -name md5-manifest.txt -exec md5sum {} \; > md5-manifest.txt
wc -l md5-manifest.txt
echo "总大小: $(du -sh "$A" | cut -f1)"
