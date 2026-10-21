#!/bin/bash
K=/root/k619/linux-6.19.14
cd $K/drivers/soc/qcom || exit 1
# 0) 入口函数重命名为内核 loader 约定名（幂等）
aarch64-linux-gnu-objcopy --redefine-sym init_module=qcom_rmtfs_mem_init --redefine-sym cleanup_module=qcom_rmtfs_mem_exit rmtfs_mem.o 2>/dev/null || true
aarch64-linux-gnu-objcopy --redefine-sym qcom_rmtfs_mem_init=init_module --redefine-sym qcom_rmtfs_mem_exit=cleanup_module rmtfs_mem.o
# 1) strip modinfo 前缀（modpost license 检查需要）
python3 /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/strip_modinfo.py || true
# 2) make: modpost 生成 .mod.c（modfinal 可能失败，忽略）
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_MODPOST_WARN=1 M=drivers/soc/qcom rmtfs_mem.ko > /tmp/mk1.log 2>&1 || true
# 3) patch .mod.c 注入 init/exit 指针
python3 - << 'PYEOF'
p = "rmtfs_mem.mod.c"
s = open(p).read()
changed = False
if ".init =" not in s:
    s = s.replace('MODULE_INFO(depends, "");',
                  'extern int init_module(void);\nextern void cleanup_module(void);\n\nMODULE_INFO(depends, "");')
    s = s.replace(".name = KBUILD_MODNAME,",
                  ".name = KBUILD_MODNAME,\n\t.init = init_module,\n\t.exit = cleanup_module,")
    changed = True
if 'vermagic' not in s:
    s = s.replace("MODULE_INFO(name, KBUILD_MODNAME);",
                  'MODULE_INFO(name, KBUILD_MODNAME);\nMODULE_INFO(vermagic, "6.19.14 SMP preempt mod_unload aarch64");')
    changed = True
if changed:
    open(p, "w").write(s)
    print("mod.c patched")
else:
    print("mod.c already patched")
PYEOF
# 4) make 增量: 重编 .mod.o + ld .ko
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_MODPOST_WARN=1 M=drivers/soc/qcom rmtfs_mem.ko > /tmp/mk2.log 2>&1 || true
ls -la rmtfs_mem.ko 2>/dev/null || { tail -6 /tmp/mk2.log; exit 1; }
aarch64-linux-gnu-readelf -p .modinfo rmtfs_mem.ko | grep -E 'vermagic|license'
aarch64-linux-gnu-nm rmtfs_mem.ko | grep -E ' [tT] init_module'
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO7_READY
