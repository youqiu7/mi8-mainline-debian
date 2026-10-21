#!/usr/bin/env python
"""
mkboot_v1.py — 小米 8 屏幕指纹版 (equuleus / SDM845) Android boot.img 打包/解包器
只支持 header_version 0/1（本机 bootloader 实测原厂为 v1, page_size=4096）。

原厂 boot.img 实测字段（本脚本的默认值来源）：
  kernel_addr  0x00008000
  ramdisk_addr 0x01000000
  second_addr  0x00f00000
  tags_addr    0x00000100
  page_size    4096
  os_version   0x1400014c
  header_version 1, recovery_dtbo_size 0, header_size 1648

用法:
  # 解包
  python mkboot_v1.py unpack boot.img -o outdir
  # 打包（kernel 后可选 append dtb，主线 sdm845 需要 Image.gz+dtb 拼接）
  python mkboot_v1.py pack --kernel Image.gz --ramdisk initramfs.cpio.gz \
         --append-dtb sdm845-xiaomi-equuleus.dtb --cmdline "console=ttyMSM0,115200n8" \
         -o boot-linux.img
  # 校验
  python mkboot_v1.py verify boot-linux.img

安全检查：打包后自动 verify；verify 失败返回非 0，调用方必须拒绝刷写。
"""
import argparse, hashlib, os, struct, sys

MAGIC = b'ANDROID!'
HDR_COMMON = 1648          # v1 header 总长
PAGE = 4096

DEFAULTS = dict(
    kernel_addr=0x00008000,
    ramdisk_addr=0x01000000,
    second_addr=0x00f00000,
    tags_addr=0x00000100,
    dtb_addr=0x01f00000,
    page_size=4096,
    os_version=0x1400014c,
    header_version=1,
)


def pad(n, page=PAGE):
    return (n + page - 1) // page * page


def parse(img):
    if img[:8] != MAGIC:
        raise SystemExit(f"不是 Android boot 镜像: magic={img[:8]!r}")
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
     second_size, second_addr, tags_addr, page_size,
     header_version, os_version) = struct.unpack_from('<10I', img, 8)
    name = img[48:64]
    cmdline = img[64:64 + 512].split(b'\0')[0]
    extra = img[608:608 + 1024].split(b'\0')[0]
    h = dict(kernel_size=kernel_size, kernel_addr=kernel_addr,
             ramdisk_size=ramdisk_size, ramdisk_addr=ramdisk_addr,
             second_size=second_size, second_addr=second_addr,
             tags_addr=tags_addr, page_size=page_size,
             header_version=header_version, os_version=os_version,
             name=name, cmdline=cmdline, extra_cmdline=extra)
    if header_version >= 1:
        rec_size, rec_off, hdr_size = struct.unpack_from('<IQI', img, 1632)
        h.update(rec_dtbo_size=rec_size, rec_dtbo_offset=rec_off, header_size=hdr_size)
    if header_version >= 2:
        dtb_size, dtb_addr = struct.unpack_from('<IQ', img, 1648)
        h.update(dtb_size=dtb_size, dtb_addr=dtb_addr)
    # 定位各段
    off = page_size
    h['kernel_off'] = off
    off += pad(kernel_size, page_size)
    h['ramdisk_off'] = off
    off += pad(ramdisk_size, page_size)
    h['second_off'] = off if second_size else None
    off += pad(second_size, page_size) if second_size else 0
    if header_version >= 1 and h.get('rec_dtbo_size'):
        h['rec_dtbo_off'] = off
        off += pad(h['rec_dtbo_size'], page_size)
    if header_version >= 2 and h.get('dtb_size'):
        h['dtb_off'] = off
        off += pad(h['dtb_size'], page_size)
    h['payload_end'] = off
    return h


def extract(img, h):
    k = img[h['kernel_off']:h['kernel_off'] + h['kernel_size']]
    r = img[h['ramdisk_off']:h['ramdisk_off'] + h['ramdisk_size']]
    s = img[h['second_off']:h['second_off'] + h['second_size']] if h['second_size'] else b''
    return k, r, s


def cmd_unpack(args):
    img = open(args.image, 'rb').read()
    h = parse(img)
    k, r, s = extract(img, h)
    os.makedirs(args.outdir, exist_ok=True)
    for nm, data in (('kernel', k), ('ramdisk', r), ('second', s)):
        if data:
            p = os.path.join(args.outdir, nm)
            open(p, 'wb').write(data)
            print(f"  {nm:8s} {len(data):10d} B  -> {p}")
    open(os.path.join(args.outdir, 'cmdline.txt'), 'wb').write(
        h['cmdline'] + (b' ' + h['extra_cmdline'] if h['extra_cmdline'] else b''))
    print("  header:", {k2: (hex(v) if isinstance(v, int) else v) for k2, v in h.items()
                        if k2 not in ('name', 'cmdline', 'extra_cmdline')})
    print(f"  payload_end={h['payload_end']}  镜像总长={len(img)}")
    return 0


def build_header(hs, kernel_size, ramdisk_size, second_size,
                 cmdline, name, os_version, header_version, extra_cmdline=b'',
                 dtb_size=0):
    page = hs['page_size']
    hdr = bytearray(page)
    struct.pack_into('<8s10I', hdr, 0, MAGIC,
                     kernel_size, hs['kernel_addr'],
                     ramdisk_size, hs['ramdisk_addr'],
                     second_size, hs['second_addr'],
                     hs['tags_addr'], page, header_version, os_version)
    nm = (name.encode() if isinstance(name, str) else name)[:15]
    hdr[48:48 + len(nm)] = nm
    cmd = (cmdline.encode() if isinstance(cmdline, str) else cmdline)[:511]
    hdr[64:64 + len(cmd)] = cmd
    ex = (extra_cmdline.encode() if isinstance(extra_cmdline, str) else extra_cmdline)[:1023]
    hdr[608:608 + len(ex)] = ex
    if header_version >= 1:
        struct.pack_into('<IQI', hdr, 1632, 0, 0, 1648)
    if header_version >= 2:
        # v2: dtb_size@1648 (u32), dtb_addr@1652 (u64)，header_size 1660
        struct.pack_into('<IQ', hdr, 1648, dtb_size, hs['dtb_addr'])
        struct.pack_into('<I', hdr, 1644, 1660)
    return hdr


def cmd_pack(args):
    hs = dict(DEFAULTS)
    kernel = open(args.kernel, 'rb').read()
    ramdisk = open(args.ramdisk, 'rb').read()
    if args.append_dtb:
        dtb = open(args.append_dtb, 'rb').read()
        if dtb[:4] != b'\xd0\x0d\xfe\xed':
            raise SystemExit("append-dtb 不是合法 FDT (magic 0xd00dfeed)")
        kernel = kernel + dtb
        print(f"  kernel += dtb  ({len(dtb)} B)  => {len(kernel)} B")
    dtb_sep = b''
    if args.dtb:
        dtb_sep = open(args.dtb, 'rb').read()
        if dtb_sep[:4] != b'\xd0\x0d\xfe\xed':
            raise SystemExit("--dtb 不是合法 FDT (magic 0xd00dfeed)")
        print(f"  dtb 独立段 v2 ({len(dtb_sep)} B) @0x{hs['dtb_addr']:x}")
    hv = args.header_version
    if hv >= 2 and not dtb_sep:
        raise SystemExit("header v2 需要 --dtb")
    cmdline = args.cmdline or (
        'console=ttyMSM0,115200n8 earlycon=qcom_geni '
        'root=PARTLABEL=debian-root rootwait rw')
    hdr = build_header(hs, len(kernel), len(ramdisk), 0, cmdline, args.name,
                       hs['os_version'], hv, dtb_size=len(dtb_sep))

    body = bytearray()
    body += kernel + b'\0' * (pad(len(kernel)) - len(kernel))
    body += ramdisk + b'\0' * (pad(len(ramdisk)) - len(ramdisk))
    if dtb_sep:
        body += dtb_sep + b'\0' * (pad(len(dtb_sep)) - len(dtb_sep))
    img = bytes(hdr) + bytes(body)
    # id = sha1(kernel || ramdisk || second) —— AOSP mkbootimg 的 update_sha()
    # 只对负载内容顺序哈希，不掺入长度字段
    sha = hashlib.sha1(kernel + ramdisk).digest()
    # id 字段 32 字节：前 20 字节 sha1，其余补 0（AOSP mkbootimg 行为）
    img = img[:576] + sha + b'\0' * (32 - len(sha)) + img[608:]

    open(args.output, 'wb').write(img)
    print(f"  已写入 {args.output}  {len(img)} B")

    # ---- 自校验：重新解析并与输入比对 ----
    h = parse(open(args.output, 'rb').read())
    back = open(args.output, 'rb').read()
    k2, r2, _ = extract(back, h)
    ok = (h['kernel_size'] == len(kernel) and h['ramdisk_size'] == len(ramdisk)
          and hashlib.sha256(k2).digest() == hashlib.sha256(kernel).digest()
          and hashlib.sha256(r2).digest() == hashlib.sha256(ramdisk).digest()
          and back[64:64 + len(cmdline)] == cmdline.encode()
          and h['page_size'] == PAGE and h['header_version'] == hv)
    if dtb_sep:
        d_off = h['payload_end'] - pad(len(dtb_sep))
        ok = ok and h.get('dtb_size') == len(dtb_sep) \
             and back[d_off:d_off + 4] == b'\xd0\x0d\xfe\xed'
    print("  自校验:", "OK" if ok else "FAILED")
    if not ok:
        os.remove(args.output)
        raise SystemExit("打包自校验失败，已删除输出，禁止刷写")
    if args.partition_size and len(img) != args.partition_size:
        raise SystemExit(f"镜像长度 {len(img)} != 分区大小 {args.partition_size}")
    return 0


def cmd_verify(args):
    img = open(args.image, 'rb').read()
    h = parse(img)
    k, r, _ = extract(img, h)
    print(f"[verify] {args.image} 总长={len(img)} payload_end={h['payload_end']}")
    print(f"  header_version={h['header_version']} page_size={h['page_size']} "
          f"kernel={h['kernel_size']} ramdisk={h['ramdisk_size']}")
    print(f"  cmdline={h['cmdline'].decode('utf-8', 'replace')}")
    print(f"  kernel sha256={hashlib.sha256(k).hexdigest()[:16]}  "
          f"ramdisk sha256={hashlib.sha256(r).hexdigest()[:16]}")
    problems = []
    if h['header_version'] not in (0, 1):
        problems.append("header_version 非 0/1")
    if h['page_size'] != PAGE:
        problems.append(f"page_size={h['page_size']} != 4096")
    if len(img) < h['payload_end']:
        problems.append("镜像长度小于负载长度（截断）")
    if r[:2] != b'\x1f\x8b' and r[:6] != b'\xfd7zXZ\x00' and r[:4] != b'070701':
        problems.append("ramdisk 既非 gzip/xz 也非裸 cpio，疑似损坏")
    # kernel 尾部应有 FDT (append-dtb 情况下)
    km = k.rfind(b'\xd0\x0d\xfe\xed')
    print(f"  kernel 内 FDT magic 位置: {km if km >= 0 else '无'}")
    if problems:
        print("  问题:", problems)
        return 1
    print("  verify OK")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)

    u = sub.add_parser('unpack')
    u.add_argument('image')
    u.add_argument('-o', '--outdir', default='unpacked')
    u.set_defaults(func=cmd_unpack)

    p = sub.add_parser('pack')
    p.add_argument('--kernel', required=True)
    p.add_argument('--ramdisk', required=True)
    p.add_argument('--append-dtb')
    p.add_argument('--dtb', help='独立 dtb 段（header v2 需要）')
    p.add_argument('--header-version', type=int, default=1)
    p.add_argument('--cmdline')
    p.add_argument('--name', default='')
    p.add_argument('--partition-size', type=int, default=0)
    p.add_argument('-o', '--output', required=True)
    p.set_defaults(func=cmd_pack)

    v = sub.add_parser('verify')
    v.add_argument('image')
    v.set_defaults(func=cmd_verify)

    a = ap.parse_args()
    sys.exit(a.func(a))


if __name__ == '__main__':
    main()
