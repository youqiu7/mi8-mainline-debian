#!/bin/bash
# 极简 EFS 内存授权模块 —— 仅做一件事：qcom_scm_assign_mem 把 0xf6301000 区授权给 MSS_MSA
# 绕过 platform driver 全套（device_add/OF 解析/ACPI glue），零刷机验证 TZ 假设
set -e
K=/root/k619/linux-6.19.14
WORK=$K/drivers/soc/qcom
OUT=/mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs
cd $WORK

cat > rmtfs_auth.c << 'EOF'
// rmtfs_auth —— one-shot: give MPSS access to the rmtfs EFS shared-mem region
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/firmware/qcom/qcom_scm.h>

#define RMTFS_ADDR 0xf6301000ULL
#define RMTFS_SIZE 0x200000ULL

int rmtfs_auth_init(void)
{
	struct qcom_scm_vmperm perms[2];
	u64 cur;
	int ret;

	if (!qcom_scm_is_available()) {
		pr_err("rmtfs_auth: SCM unavailable\n");
		return -ENODEV;
	}

	cur = BIT(QCOM_SCM_VMID_HLOS);
	perms[0].vmid = QCOM_SCM_VMID_HLOS;
	perms[0].perm = QCOM_SCM_PERM_RW;
	perms[1].vmid = QCOM_SCM_VMID_MSS_MSA;
	perms[1].perm = QCOM_SCM_PERM_RW;

	ret = qcom_scm_assign_mem(RMTFS_ADDR, RMTFS_SIZE, &cur, perms, 2);
	pr_info("rmtfs_auth: assign_mem(0x%llx,+0x%llx) -> %d (src now 0x%llx)\n",
		RMTFS_ADDR, RMTFS_SIZE, ret, cur);
	return ret;
}

void rmtfs_auth_exit(void)
{
	pr_info("rmtfs_auth: unloaded (auth mapping persists in TZ)\n");
}

module_init(rmtfs_auth_init);
module_exit(rmtfs_auth_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("one-shot EFS region auth for MPSS");
EOF

KINC="-I$K/arch/arm64/include -I$K/arch/arm64/include/generated -I$K/include -I$K/arch/arm64/include/uapi -I$K/arch/arm64/include/generated/uapi -I$K/include/uapi -I$K/include/generated/uapi -include $K/include/linux/compiler-version.h -include $K/include/linux/kconfig.h"

aarch64-linux-gnu-gcc -nostdinc $KINC -D__KERNEL__ -DMODULE -fno-strict-aliasing -fno-common -fshort-wchar -std=gnu11 -fno-PIE -c -o rmtfs_auth.o rmtfs_auth.c

cat > rmtfs_auth.mod.c << 'EOF'
#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);
MODULE_INFO(vermagic, "6.19.14 SMP preempt mod_unload aarch64");

extern int rmtfs_auth_init(void);
extern void rmtfs_auth_exit(void);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.arch = MODULE_ARCH_INIT,
	.init = rmtfs_auth_init,
	.exit = rmtfs_auth_exit,
};

MODULE_INFO(depends, "");
EOF

aarch64-linux-gnu-gcc -nostdinc $KINC -DKBUILD_MODNAME='"rmtfs_auth"' -D__KERNEL__ -DMODULE -fno-strict-aliasing -fno-common -fshort-wchar -std=gnu11 -fno-PIE -c -o rmtfs_auth.mod.o rmtfs_auth.mod.c

aarch64-linux-gnu-ld -r -T $K/scripts/module.lds -o rmtfs_auth.ko rmtfs_auth.o rmtfs_auth.mod.o

aarch64-linux-gnu-readelf -p .modinfo rmtfs_auth.ko | grep -E 'license|vermagic|name='
aarch64-linux-gnu-nm rmtfs_auth.ko | grep -E ' [tTU] rmtfs_auth' 
cp rmtfs_auth.ko $OUT/
echo AUTH_KO_READY
