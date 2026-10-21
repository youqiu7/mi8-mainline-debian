#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
cd $K/drivers/soc/qcom
aarch64-linux-gnu-objcopy --globalize-symbol=qcom_rmtfs_mem_init --globalize-symbol=qcom_rmtfs_mem_exit rmtfs_mem.o
aarch64-linux-gnu-gcc -nostdinc -DKBUILD_MODNAME='"rmtfs_mem"' \
  -I$K/arch/arm64/include -I$K/arch/arm64/include/generated \
  -I$K/include -I$K/arch/arm64/include/uapi \
  -I$K/arch/arm64/include/generated/uapi -I$K/include/uapi \
  -I$K/include/generated/uapi \
  -include $K/include/linux/compiler-version.h \
  -include $K/include/linux/kconfig.h \
  -D__KERNEL__ -DMODULE -fno-strict-aliasing -fno-common -fshort-wchar \
  -std=gnu11 -fno-PIE \
  -c -o rmtfs_mem.mod.o rmtfs_mem.mod.c
aarch64-linux-gnu-ld -r -T $K/scripts/module.lds -o rmtfs_mem.ko rmtfs_mem.o rmtfs_mem.mod.o
aarch64-linux-gnu-nm rmtfs_mem.ko | grep -E ' [tT] qcom_rmtfs_mem_(init|exit)'
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO6_READY
