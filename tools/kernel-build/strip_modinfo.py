#!/usr/bin/env python3
"""strip KBUILD modinfo object-name prefix (rmtfs_mem.) from .o so modpost finds license="""
import struct, sys

p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.o"
data = bytearray(open(p, "rb").read())
e_shoff = struct.unpack_from("<Q", data, 40)[0]
e_shentsize = struct.unpack_from("<H", data, 58)[0]
e_shnum = struct.unpack_from("<H", data, 60)[0]
e_shstrndx = struct.unpack_from("<H", data, 62)[0]
sh0 = e_shoff + e_shstrndx * e_shentsize
shstr_off = struct.unpack_from("<Q", data, sh0 + 24)[0]
shstr_size = struct.unpack_from("<Q", data, sh0 + 32)[0]
shstr = bytes(data[shstr_off:shstr_off + shstr_size])
done = False
for i in range(e_shnum):
    sh = e_shoff + i * e_shentsize
    name_off = struct.unpack_from("<I", data, sh)[0]
    name = shstr[name_off:name_off + 40].split(b"\0")[0]
    if name == b".modinfo":
        off = struct.unpack_from("<Q", data, sh + 24)[0]
        size = struct.unpack_from("<Q", data, sh + 32)[0]
        blob = bytes(data[off:off + size])
        entries = [e for e in blob.split(b"\0") if e]
        out = []
        for e in entries:
            if e.startswith(b"rmtfs_mem."):
                e = e[len(b"rmtfs_mem."):]
            out.append(e)
        newblob = b"\0".join(out) + b"\0"
        if len(newblob) > size:
            print("cannot shrink in place"); sys.exit(1)
        data[off:off + size] = newblob + b"\0" * (size - len(newblob))
        struct.pack_into("<Q", data, sh + 32, len(newblob))
        print("stripped:", blob[:60], "->", newblob[:40])
        done = True
if not done:
    print(".modinfo not found"); sys.exit(1)
open(p, "wb").write(bytes(data))
print("OK")
