#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
cd $K
rm -f drivers/soc/qcom/rmtfs_mem.o drivers/soc/qcom/rmtfs_mem.mod.o drivers/soc/qcom/rmtfs_mem.ko
# obj-m 编译应自带 -DMODULE；若没有则显式补上（KBUILD_EXTRA_CFLAGS）
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o 2>&1 | tail -2
echo '=== 验证 init_module 符号（MODULE 生效标志）==='
aarch64-linux-gnu-nm drivers/soc/qcom/rmtfs_mem.o | grep -E 'init_module|cleanup_module|__initcall' || true
echo '=== modpost + modfinal ==='
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_MODPOST_WARN=1 KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.ko 2>&1 | grep -vE 'Leaving|Entering|undefined|suppressed|WARNING: modpost|WARNING: /|CC|MODPOST' | tail -4
ls -la drivers/soc/qcom/rmtfs_mem.ko
aarch64-linux-gnu-readelf -p .modinfo drivers/soc/qcom/rmtfs_mem.ko | grep -E 'license|vermagic'
cp drivers/soc/qcom/rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO4_READY
