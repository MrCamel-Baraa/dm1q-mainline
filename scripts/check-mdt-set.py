#!/usr/bin/env python3
"""Check a Qualcomm split firmware set (NAME.mdt + NAME.bNN) in a directory against the ELF program headers in the .mdt (docs/13).

For every program header the segment file NAME.b<index> must exist with exactly p_filesz bytes (index = the position of the header; segments with
p_filesz == 0 have no file). The .mdt is the ELF header + program headers (+ the hash/signature segment content, which is b01 / the hash segment
itself). Prints a summary and exits 0 when everything matches, 1 otherwise.
Usage: check-mdt-set.py <dir> <name> [<name> ...]        e.g. check-mdt-set.py ../_scratch/dm1q-dsp-fw-vendor/apnhlos-image adsp adsp_dtb
"""
import os
import struct
import sys


def read_phdrs(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    is64 = data[4] == 2
    if is64:
        phoff, = struct.unpack_from("<Q", data, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
    else:
        phoff, = struct.unpack_from("<I", data, 0x1C)
        phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
    out = []
    for i in range(phnum):
        o = phoff + i * phentsize
        if is64:
            p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from("<IIQQQQQQ", data, o)
        else:
            p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from("<IIIIIIII", data, o)
        out.append((p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags))
    return is64, len(data), out


def check(d, name):
    mdt = os.path.join(d, name + ".mdt")
    is64, mdt_size, phdrs = read_phdrs(mdt)
    bad = 0
    present = 0
    absent_zero = 0
    total = 0
    for i, (p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags) in enumerate(phdrs):
        seg = os.path.join(d, "%s.b%02d" % (name, i))
        if p_filesz == 0:
            if os.path.exists(seg):
                print("  note: %s exists although p_filesz is 0 (%d bytes)" % (os.path.basename(seg), os.path.getsize(seg)))
            absent_zero += 1
            continue
        if not os.path.exists(seg):
            print("  MISSING %s (p_filesz %d)" % (os.path.basename(seg), p_filesz))
            bad += 1
            continue
        sz = os.path.getsize(seg)
        total += sz
        if sz != p_filesz:
            print("  SIZE MISMATCH %s: file %d, header %d" % (os.path.basename(seg), sz, p_filesz))
            bad += 1
        else:
            present += 1
    print("%s: ELF%d, mdt %d bytes, %d program headers, %d segment files ok, %d zero-size (no file), %d problems, %d bytes of segments"
          % (name, 64 if is64 else 32, mdt_size, len(phdrs), present, absent_zero, bad, total))
    return bad


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    d = sys.argv[1]
    bad = 0
    for name in sys.argv[2:]:
        bad += check(d, name)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
