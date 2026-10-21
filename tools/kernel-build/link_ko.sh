#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
cd $K/drivers/soc/qcom
gcc_bin=aarch64-linux-gnu-gcc
ld_bin=aarch64-linux-gnu-ld
$gcc_bin -nostdinc \
  -DKBUILD_MODNAME='"rmtfs_mem"' \
  -I$K/arch/arm64/include -I$K/arch/arm64/include/generated \
  -I$K/include -I$K/arch/arm64/include/uapi \
  -I$K/arch/arm64/include/generated/uapi -I$K/include/uapi \
  -I$K/include/generated/uapi \
  -include $K/include/linux/compiler-version.h \
  -include $K/include/linux/kconfig.h \
  -D__KERNEL__ -fno-strict-aliasing -fno-common -fshort-wchar \
  -std=gnu11 -fno-PIE \
  -c -o rmtfs_mem.mod.o rmtfs_mem.mod.c
$ld_bin -r -o rmtfs_mem.ko rmtfs_mem.o rmtfs_mem.mod.o
ls -la rmtfs_mem.ko
aarch64-linux-gnu-readelf -p .modinfo rmtfs_mem.ko | grep -E 'license|vermagic|name='
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO_READY
