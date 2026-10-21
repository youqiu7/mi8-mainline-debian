#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
grep -rn 'MODULE_ARCH_VERMAGIC' $K/arch/arm64/include/asm/vermagic.h || echo 'no arch vermagic (empty ok)'
MODC=$K/drivers/soc/qcom/rmtfs_mem.mod.c
if ! grep -q 'vermagic' $MODC; then
  sed -i 's/MODULE_INFO(name, KBUILD_MODNAME);/MODULE_INFO(name, KBUILD_MODNAME);\nMODULE_INFO(vermagic, "6.19.14 SMP PREEMPT mod_unload aarch64");/' $MODC
fi
grep -n vermagic $MODC
cd $K/drivers/soc/qcom
aarch64-linux-gnu-gcc -nostdinc -DKBUILD_MODNAME='"rmtfs_mem"' \
  -I$K/arch/arm64/include -I$K/arch/arm64/include/generated \
  -I$K/include -I$K/arch/arm64/include/uapi \
  -I$K/arch/arm64/include/generated/uapi -I$K/include/uapi \
  -I$K/include/generated/uapi \
  -include $K/include/linux/compiler-version.h \
  -include $K/include/linux/kconfig.h \
  -D__KERNEL__ -fno-strict-aliasing -fno-common -fshort-wchar \
  -std=gnu11 -fno-PIE \
  -c -o rmtfs_mem.mod.o rmtfs_mem.mod.c
aarch64-linux-gnu-ld -r -o rmtfs_mem.ko rmtfs_mem.o rmtfs_mem.mod.o
aarch64-linux-gnu-readelf -p .modinfo rmtfs_mem.ko | grep -E 'license|vermagic|name='
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO2_READY
