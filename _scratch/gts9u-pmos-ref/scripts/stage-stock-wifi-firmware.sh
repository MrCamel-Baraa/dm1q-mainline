#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
vendor_image="${STOCK_VENDOR_IMAGE:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/port/firmware-extracted/super-parts/vendor.img}"
extracted="${STOCK_VENDOR_EXTRACTED:-$base/stock-vendor-extracted}"
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"

if [ ! -f "$extracted/firmware/kiwi/amss20.bin" ]; then
	command -v fsck.erofs >/dev/null || {
		echo "fsck.erofs is required (Ubuntu package: erofs-utils)" >&2
		exit 2
	}
	test -f "$vendor_image"
	rm -rf -- "$extracted"
	mkdir -p "$extracted"
	fsck.erofs --extract="$extracted" "$vendor_image"
fi

mkdir -p "$target"
for file in amss20.bin phy_ucode20.elf bdwlan.elf regdb.bin; do
	install -m 0644 "$extracted/firmware/kiwi/$file" "$target/$file"
done

# Bluetooth shares the Kiwi/WCN7850 module but uses QUP SE14 plus hci_qca.
# Preserve Samsung's board-specific NVM variants for comparison; the X910 DTS
# explicitly selects the validated b21 image after loading hmtbtfw20.tlv.
for file in hmtbtfw20.tlv hmtnv20.bin hmtnv20.b21 hmtnv20.b22 hmtnv20.b38; do
	install -m 0644 "$extracted/firmware/$file" "$target/$file"
done

# Keep the old payload extraction for historical comparison only. The
# official amss requires the complete ELF wrapper and hangs on the final QMI
# segment when it receives this stripped payload as bdf_type 0.
python3 - "$target/bdwlan.elf" "$target/bdwlan-payload.bin" <<'PYEOF'
import struct
import sys

elf = open(sys.argv[1], 'rb').read()
assert elf[:4] == b'\x7fELF' and elf[4] == 1
e_phoff, = struct.unpack_from('<I', elf, 0x1c)
e_phentsize, e_phnum = struct.unpack_from('<HH', elf, 0x2a)
assert e_phnum == 1, e_phnum
p_type, p_offset, _, _, p_filesz = struct.unpack_from('<IIIII', elf, e_phoff)
assert p_type == 1
open(sys.argv[2], 'wb').write(elf[p_offset:p_offset + p_filesz])
PYEOF

# Build an API-2 container for the exact PCI/QMI identity reported by the
# physical X910. The BDF remains the complete Samsung ELF so ath12k selects
# the ELF QMI bdf_type. qrd-board.bin remains the independent API-1 fallback.
x910_board_name='bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255'
python3 "$project/scripts/make-ath12k-board2.py" \
	"$x910_board_name" "$target/bdwlan.elf" "$target/samsung-board-2.bin"

# WCN7850 hw2.0 uses ath12k_m3_fw_loader_driver, so m3.bin is mandatory.
# Samsung's kiwi directory ships no m3; use the canonical linux-firmware one.
# Samsung's amss (WLAN.HMT downstream branch) also stalls WLAN start under
# mainline ath12k — cnss2 feeds it phy_ucode20.elf over a QMI channel that
# mainline does not implement — so stage the official amss/board-2 as well.
lf='https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath12k/WCN7850/hw2.0'
if [ ! -f "$target/m3.bin" ]; then
	curl -fL --retry 3 -o "$target/m3.bin" "$lf/m3.bin"
fi
for f in amss.bin board-2.bin; do
	if [ ! -f "$target/official-$f" ]; then
		curl -fL --retry 3 -o "$target/official-$f" "$lf/$f"
	fi
done

# The official board-2.bin has no entry for the X910 (subsystem 17cb:1107,
# qmi-board-id 255).  Extract the QRD entry (subsystem 17cb:3378, same chip,
# same unprogrammed board-id 255) as the API-1 fallback: WCN7850 BDFs are
# distributed as ELF containers and ath12k selects the QMI bdf_type from the
# magic, so the entry is shipped verbatim.
python3 - "$target/official-board-2.bin" "$target/qrd-board.bin" <<'PYEOF'
import struct
import sys

WANT = ("bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,"
        "subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255")

blob = open(sys.argv[1], 'rb').read()
assert blob.startswith(b"QCA-ATH12K-BOARD")
off = (len(b"QCA-ATH12K-BOARD\0") + 3) & ~3
found = None
while off + 8 <= len(blob) and not found:
    ie_id, ie_len = struct.unpack_from('<II', blob, off)
    payload = blob[off + 8:off + 8 + ie_len]
    if ie_id == 0:
        sub = 0
        name = None
        while sub + 8 <= len(payload):
            sid, slen = struct.unpack_from('<II', payload, sub)
            sdata = payload[sub + 8:sub + 8 + slen]
            if sid == 0:
                name = sdata.split(b'\0')[0].decode()
            elif sid == 1 and name == WANT:
                found = sdata
                break
            sub += 8 + ((slen + 3) & ~3)
    off += 8 + ((ie_len + 3) & ~3)
assert found, 'QRD entry not found'
open(sys.argv[2], 'wb').write(found)
PYEOF

cd "$target"
sha256sum -c <<'EOF'
4529e42c3e6798db7060e16c646f6f81ecf463e44552115c6a91656cf4bf7915  amss20.bin
67396ffa89db6a1378c0d1d41362d33831dd6163d96849a4bcbd865b7cecda19  phy_ucode20.elf
9cade90ae22d7df1c44850bf55c6231bf99b4303f406eca9775d920bb6d4313e  bdwlan.elf
191ac306aa56e016ace5f0d3406376c6078e92c850644cd1c1d69753e4d3c16d  bdwlan-payload.bin
0e72f44df7defc269fe92dcea25d4d409046c04b77d41c510c52879b3dfc1055  m3.bin
43aadfd3df887f27de74020273aee484bac6a31dd53068f91baf2a9b094d6a68  official-amss.bin
1abee7132dbccb523cca44a8de4e8968aa7bf5a5fcc032c338f687f94ea5bf4e  official-board-2.bin
9886957c549c1dfa8d48ec80f23a0af0d524389054a74aeb85fd21de4ce4fb70  samsung-board-2.bin
0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3  qrd-board.bin
75cc107536d3bd03fa2e29f369a4e6d997d2cf090c50620424a9ab1a749c7546  regdb.bin
b91f0af74413a8c93cbba956b46227a38446ea6bba8a79691cf365c22ed6e9f3  hmtbtfw20.tlv
ba9ef0865764cbdba0e76c9655f07e2290e1759ac5187be93556d90d586eae17  hmtnv20.bin
864476ed6cea427003f2806ab27203d7615b8760a0849fd24905935671c59769  hmtnv20.b21
9f23113db6263269a7a3bfb1f3c70dcc23dec68716ecabd50fcc2447c34b9323  hmtnv20.b22
9f23113db6263269a7a3bfb1f3c70dcc23dec68716ecabd50fcc2447c34b9323  hmtnv20.b38
EOF
