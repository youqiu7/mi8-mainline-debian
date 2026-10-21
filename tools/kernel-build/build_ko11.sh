#!/bin/bash
K=/root/k619/linux-6.19.14
SRC=$K/drivers/soc/qcom/rmtfs_mem.c
python3 - << 'PYEOF'
p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.c"
s = open(p).read()
if "of_address_to_resource(node, 0, &res)" in s:
    print("probe patch already applied")
else:
    old = '''	rmem = of_reserved_mem_lookup(node);
	if (!rmem) {
		dev_err(&pdev->dev, "failed to acquire memory region\\n");
		return -EINVAL;
	}
'''
    new = '''	struct resource res;

	rmem = of_reserved_mem_lookup(node);
	if (rmem) {
		res.start = rmem->base;
		res.end = rmem->base + rmem->size - 1;
	} else if (!of_address_to_resource(node, 0, &res)) {
		dev_info(&pdev->dev, "rmtfs region from DT reg: %pr\\n", &res);
	} else {
		dev_err(&pdev->dev, "failed to acquire memory region\\n");
		return -EINVAL;
	}
'''
    if old not in s:
        raise SystemExit("anchor1 missing")
    s = s.replace(old, new, 1)
    s = s.replace("	rmtfs_mem->addr = rmem->base;\n	rmtfs_mem->client_id = client_id;\n	rmtfs_mem->size = rmem->size;",
                  "	rmtfs_mem->addr = res.start;\n	rmtfs_mem->client_id = client_id;\n	rmtfs_mem->size = resource_size(&res);", 1)
    open(p, "w").write(s)
    print("probe patched")
PYEOF
cd $K || exit 1
rm -f drivers/soc/qcom/rmtfs_mem.o
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o > /tmp/ko11.log 2>&1 || { tail -5 /tmp/ko11.log; exit 1; }
python3 /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/strip_modinfo.py > /dev/null
cd drivers/soc/qcom || exit 1
aarch64-linux-gnu-objcopy --globalize-symbol=qcom_rmtfs_mem_init --globalize-symbol=qcom_rmtfs_mem_exit rmtfs_mem.o
cat > rmtfs_mem.mod.c << 'EOF'
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
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO11_READY
