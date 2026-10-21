#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
MODC=$K/drivers/soc/qcom/rmtfs_mem.mod.c
# 重建基底（modpost 版若被覆盖则重生成——直接手写保证一致）
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
#ifdef CONFIG_MODULE_UNLOAD
	.exit = qcom_rmtfs_mem_exit,
#endif
};

MODULE_INFO(depends, "");
MODULE_ALIAS("of:N*T*Cqcom,rmtfs-mem");
MODULE_ALIAS("of:N*T*Cqcom,rmtfs-memC*");
EOF
cd $K/drivers/soc/qcom
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
aarch64-linux-gnu-readelf -p .modinfo rmtfs_mem.ko | grep -E 'license|vermagic|name='
aarch64-linux-gnu-nm rmtfs_mem.ko | grep -E ' [tT] (qcom_rmtfs_mem_init|init_module)'
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO5_READY
