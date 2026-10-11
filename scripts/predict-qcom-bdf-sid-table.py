#!/usr/bin/env python3
"""What does pcie-qcom.c's qcom_pcie_config_sid_1_9_0() put into the PCIe controller's
BDF-to-SID table for a given DTB?  (docs/07 section 14)

The Qualcomm PCIe controller tags every inbound transaction of an endpoint (DMA *and* MSI
writes) with a stream ID looked up by the endpoint's BDF in a 256-slot hash table in the PARF
block (PARF + 0x2000).  The driver fills that table from the DT's "iommu-map".  This script
models, bit for bit, the table-programming loop of drivers/pci/controller/dwc/pcie-qcom.c
(7.3-rc3) in two variants:

  old    the 7.3-rc3 parser: reads "iommu-map" as fixed four-word {rid, phandle, sid, len}
         entries.  Correct only for 4-cell entries; sm8550.dtsi has 5-cell entries since the
         "Fix the PCIe iommu-map entries" DT series (the SMMU has #iommu-cells = <2>).
  fixed  the parser of the upstream fix "PCI: qcom: Honor IOMMU provider's #iommu-cells in
         qcom_pcie_config_sid_1_9_0()" (applied 2026-09-17): stride 3 + #iommu-cells, with a
         4-cell fallback for legacy DTs.

and it can decode a table dump read from the phone (scripts/phone-mhi-regdump.sh prints one
between BDF2SID-TABLE-BEGIN / BDF2SID-TABLE-END).

Usage:
  predict-qcom-bdf-sid-table.py <dtb> [--node /soc@0/pcie@1c00000]
  predict-qcom-bdf-sid-table.py --decode <file>
Python 3 standard library only; the DTB is parsed here, no dtc needed.
"""
import struct
import sys

ROOT_PORT_RID = 0x0000
ENDPOINT_RID = 0x0100   # 0000:01:00.0, the QCA6490


# ---------------------------------------------------------------- kernel's crc8 (lib/crc8.c)
def crc8_populate_msb(poly):
    table = [0] * 256
    t = 0x80
    i = 1
    while i < 256:
        t = ((t << 1) ^ (poly if (t & 0x80) else 0)) & 0xFF
        for j in range(i):
            table[i + j] = table[j] ^ t
        i *= 2
    return table


CRC8 = crc8_populate_msb(0x07)   # QCOM_PCIE_CRC8_POLYNOMIAL = BIT(2)|BIT(1)|BIT(0)


def slot_of(bdf):
    crc = 0
    for b in struct.pack(">H", bdf & 0xFFFF):      # cpu_to_be16(u16)
        crc = CRC8[(crc ^ b) & 0xFF]
    return crc


# ---------------------------------------------------------------- the driver's programming loop
def program(entries, sid_base):
    """entries: [(bdf, sid)] as the driver read them.  Returns the 256-word table."""
    table = [0] * 256
    for bdf, sid in entries:
        h = slot_of(bdf)
        val = table[h]
        while val:                                  # slot taken: chain through the next free one
            cur = h
            h = (h + 1) & 0xFF
            if not (val & 0xFF):                    # NEXT field empty: point it at the new slot
                val |= h
                table[cur] = val
            val = table[h]
        table[h] = (((bdf << 16) & 0xFFFFFFFF) |
                    ((((sid - sid_base) & 0xFFFFFFFF) << 8) & 0xFFFFFFFF))
    return table


def parse_old(words):
    n = len(words) * 4 // 16                        # nr_map = size / sizeof(4 x u32)
    units = [words[4 * k:4 * k + 4] for k in range(n)]
    return [(u[0], u[2]) for u in units], words[2], units


def parse_fixed(words, iommu_cells):
    cells = len(words)
    entry = 3 + iommu_cells
    note = ""
    if iommu_cells == 2 and cells % 4 == 0:
        if all(words[i + 1] == words[1] and words[i + 3] == 1 for i in range(0, cells, 4)):
            entry = 4
            note = " (legacy 4-cell entries recognised)"
    if cells % entry:
        raise SystemExit("malformed iommu-map: %d cells, stride %d" % (cells, entry))
    n = cells // entry
    return [(words[i * entry], words[i * entry + 2]) for i in range(n)], words[2], note


# ---------------------------------------------------------------- lookup as the hardware is documented to do it
def lookup(table, bdf):
    h = slot_of(bdf)
    for _ in range(256):
        val = table[h]
        if (val >> 16) == bdf and val != 0:
            return (val >> 8) & 0xFF, h
        if bdf == 0 and val == 0:
            return 0, h                             # slot 0 / BDF 0 / SID offset 0 reads as empty either way
        nxt = val & 0xFF
        if not nxt:
            return None, h
        h = nxt
    return None, h


def show_table(title, table, sid_base=None):
    print(title)
    used = [(i, v) for i, v in enumerate(table) if v]
    if not used:
        print("   (all 256 slots are zero)")
    for i, v in used:
        bdf = v >> 16
        print("   slot 0x%02x = 0x%08x   BDF field 0x%04x (%02x:%02x.%x)  SID offset 0x%02x  NEXT 0x%02x"
              % (i, v, bdf, (bdf >> 8) & 0xFF, (bdf >> 3) & 0x1F, bdf & 7, (v >> 8) & 0xFF, v & 0xFF))
    for name, rid in (("root port 00:00.0 (RID 0x0000)", ROOT_PORT_RID),
                      ("endpoint 01:00.0 (RID 0x0100)", ENDPOINT_RID)):
        sid, slot = lookup(table, rid)
        if sid is None:
            print("   lookup %-32s: NO ENTRY (hashes to slot 0x%02x, unprogrammed) -> hardware default SID" % (name, slot))
        else:
            tail = ("  = SID 0x%04x" % (sid_base + sid)) if sid_base is not None else ""
            print("   lookup %-32s: entry in slot 0x%02x, SID offset 0x%02x%s" % (name, slot, sid, tail))


# ---------------------------------------------------------------- minimal FDT reader
def parse_fdt(buf):
    (magic, _total, off_struct, off_strings, _off_rsv, _ver, _lc, _cpu, size_strings, _size_struct) = \
        struct.unpack(">10I", buf[:40])
    if magic != 0xD00DFEED:
        raise SystemExit("not a DTB")
    strings = buf[off_strings:off_strings + size_strings]
    nodes, stack, pos = {}, [], off_struct

    def cstr(b, p):
        e = b.index(b"\0", p)
        return b[p:e].decode(), e + 1

    while True:
        tok = struct.unpack(">I", buf[pos:pos + 4])[0]
        pos += 4
        if tok == 1:                                # FDT_BEGIN_NODE
            name, pos = cstr(buf, pos)
            pos = (pos + 3) & ~3
            path = "/" if not stack else stack[-1].rstrip("/") + "/" + name
            nodes[path] = {}
            stack.append(path)
        elif tok == 2:                              # FDT_END_NODE
            stack.pop()
        elif tok == 3:                              # FDT_PROP
            ln, nameoff = struct.unpack(">II", buf[pos:pos + 8])
            pos += 8
            data = buf[pos:pos + ln]
            pos = (pos + ln + 3) & ~3
            nodes[stack[-1]][cstr(strings, nameoff)[0]] = data
        elif tok == 4:
            continue
        elif tok == 9:
            break
        else:
            raise SystemExit("bad FDT token %d" % tok)
    return nodes


def words_of(b):
    return list(struct.unpack(">%dI" % (len(b) // 4), b))


def predict(dtb_path, node):
    nodes = parse_fdt(open(dtb_path, "rb").read())
    if node not in nodes or "iommu-map" not in nodes[node]:
        raise SystemExit("%s has no iommu-map in %s" % (node, dtb_path))
    words = words_of(nodes[node]["iommu-map"])
    ph = words[1]
    target = next((p for p, props in nodes.items()
                   if ("phandle" in props and words_of(props["phandle"])[0] == ph)), None)
    cells = words_of(nodes[target]["#iommu-cells"])[0] if target and "#iommu-cells" in nodes[target] else 1
    print("DTB        : %s" % dtb_path)
    print("node       : %s" % node)
    print("iommu-map  : %s" % " ".join("0x%x" % w for w in words))
    if len(words) % (3 + cells) == 0:
        shape = "well-formed, %d cells per entry" % (3 + cells)
    elif len(words) % 4 == 0:
        shape = "legacy 4-cell entries (the shape drivers/of/base.c of_check_bad_map() tolerates)"
    else:
        shape = "MALFORMED"
    print("IOMMU      : phandle 0x%x = %s, #iommu-cells = %d -> %s; the property has %d cells"
          % (ph, target, cells, shape, len(words)))
    print()
    entries, base, units = parse_old(words)
    print("7.3-rc3 parser (four-word units): %d units" % len(units))
    for k, u in enumerate(units):
        print("   unit %d = {bdf=0x%x, phandle=0x%x, smmu_sid=0x%x, smmu_sid_len=0x%x}" % ((k,) + tuple(u)))
    show_table("-> table the 7.3-rc3 driver programs (smmu_sid_base = 0x%x):" % base,
               program(entries, base), base)
    print()
    entries, base, note = parse_fixed(words, cells)
    print("fixed parser (stride 3 + #iommu-cells)%s: %d entries" % (note, len(entries)))
    for k, (bdf, sid) in enumerate(entries):
        print("   entry %d = {rid=0x%x, sid=0x%x}" % (k, bdf, sid))
    show_table("-> table the fixed driver programs (smmu_sid_base = 0x%x):" % base,
               program(entries, base), base)


def decode(path):
    text = open(path, errors="replace").read()
    if "BDF2SID-TABLE-BEGIN" in text:
        text = text.split("BDF2SID-TABLE-BEGIN", 1)[1].split("BDF2SID-TABLE-END", 1)[0]
    toks = [t for t in text.replace("\r", "").split() if len(t) == 8 and all(c in "0123456789abcdefABCDEF" for c in t)]
    if len(toks) != 256:
        raise SystemExit("expected 256 eight-digit hex words, found %d" % len(toks))
    show_table("PARF BDF-to-SID table as read from the phone:", [int(t, 16) for t in toks])


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "--decode":
        decode(a[1])
    elif a and not a[0].startswith("-"):
        predict(a[0], a[a.index("--node") + 1] if "--node" in a else "/soc@0/pcie@1c00000")
    else:
        print(__doc__)
        sys.exit(2)
