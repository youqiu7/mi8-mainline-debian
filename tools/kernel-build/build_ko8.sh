#!/bin/bash
K=/root/k619/linux-6.19.14
cd $K || exit 1
rm -f drivers/soc/qcom/rmtfs_mem.o drivers/soc/qcom/rmtfs_mem.mod.o drivers/soc/qcom/rmtfs_mem.ko
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o > /tmp/ko8a.log 2>&1 || { tail -3 /tmp/ko8a.log; exit 1; }
aarch64-linux-gnu-nm drivers/soc/qcom/rmtfs_mem.o | grep -E '__initcall__kmod' || true
python3 /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/strip_modinfo.py > /dev/null
MODC=drivers/soc/qcom/rmtfs_mem.mod.c
cat > $MODC << 'EOF'
#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);
MODULE_INFO(vermagic, "6.19.14 SMP preempt mod_unload aarch64");

extern int qcom_rmtfs_mem_init(void);
extern void qcom_rmtfs_mem_exit(void);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.arch = MODULE_ARCH_INIT,
	.init = qcom_rmtfs_mem_init,
	.exit = qcom_rmtfs_mem_exit,
};

MODULE_INFO(depends, "");
MODULE_ALIAS("of:N*T*Cqcom,rmtfs-mem");
MODULE_ALIAS("of:N*T*Cqcom,rmtfs-memC*");
EOF
cd drivers/soc/qcom || exit 1
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
aarch64-linux-gnu-nm rmtfs_mem.ko | grep -E 'init_module|qcom_rmtfs_mem_init' | head -3
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO8_READY
