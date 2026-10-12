#!/usr/bin/env bash
# Build a boot + vendor_boot + dtbo image set from a DTS WITHOUT a kernel build (no sudo, no pmbootstrap).
#
# It re-uses the kernel of an already built APK and the vendor command line of a reference
# vendor_boot image, so the ONLY thing that changes is the DTB. Recipe from the 2026-10-05 handoff
# (docs/06 process rules), scripted so it stops being a manual checklist:
#
#   1. copy the DTS into the cached 7.3-rc3 tree and compile it with the KERNEL's own dtc
#      (it enforces "properties must precede subnodes"); the tree's own copy is restored afterwards
#   2. scripts/check-wlan-dtb.py on the DTB
#   3. extract vmlinuz from the APK, read the cmdline of the reference vendor_boot
#   4. scripts/make-boot-images.sh (the same code path that produced v8)
#   5. verify against the reference: vendor ramdisk, bootconfig and cmdline must be identical,
#      the kernel part of boot.img must be byte-identical, and the DTB inside both images must be
#      the one just compiled; show what differs from the reference DTB
#
# Usage: scripts/make-dtb-image-set.sh --dts <file.dts> --out <dir> [--ref-set <dir with vendor_boot.img + boot.img>]
#        [--apk <kernel apk>] [--new-kernel]
#   --apk         default: the r5 APK (kernel #6, carries the PCIe BDF-to-SID fix; since 2026-10-11 the baseline,
#                 and the rootfs' module tree is r5's -- an r4 kernel would refuse every module, docs/07 15.12)
#   --new-kernel  the kernel is EXPECTED to differ from the reference's (reported, not a failure)
# Defaults: --ref-set ../_scratch/pmos-v10-r5-pcifix
# The last lines report whether the kernel in the new boot.img contains the PCIe BDF-to-SID fix
# (docs/07 section 14): r4 = no, r5 = yes.
# Nothing here flashes anything.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
KSRC="${KSRC:-$HOME/.cache/dm1q-kernel-src/full/linux-7.3-rc3}"
KOUT="${KOUT:-$HOME/.cache/dm1q-kernel-src/out-real}"
APK="${APK:-$HOME/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r5.apk}"
REF="$REPO/../_scratch/pmos-v10-r5-pcifix"
DTS="" OUT="" NEWK=0
while [ $# -gt 0 ]; do
	case "$1" in
	--dts) DTS="$2"; shift 2 ;;
	--out) OUT="$2"; shift 2 ;;
	--ref-set) REF="$2"; shift 2 ;;
	--apk) APK="$2"; shift 2 ;;
	--new-kernel) NEWK=1; shift ;;
	*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done
[ -f "$DTS" ] && [ -n "$OUT" ] || { sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 2; }
for f in "$APK" "$REF/vendor_boot.img" "$REF/boot.img"; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done

W="$(mktemp -d)"
TREE_DTS="$KSRC/arch/arm64/boot/dts/qcom/sm8550-samsung-dm1q.dts"
cp "$TREE_DTS" "$W/tree-dts.orig"
restore() { cp "$W/tree-dts.orig" "$TREE_DTS"; rm -rf "$W"; }
trap restore EXIT

echo "== 1. compile $DTS with the kernel's dtc"
grep -q 'sm8550-samsung-dm1q.dtb' "$KSRC/arch/arm64/boot/dts/qcom/Makefile" || { echo "tree Makefile lacks the dm1q dtb line" >&2; exit 1; }
cp "$DTS" "$TREE_DTS"
make -C "$KSRC" -s O="$KOUT" ARCH=arm64 qcom/sm8550-samsung-dm1q.dtb
DTB="$KOUT/arch/arm64/boot/dts/qcom/sm8550-samsung-dm1q.dtb"
[ -f "$DTB" ] && [ "$DTB" -nt "$DTS" ] || { echo "DTB was not rebuilt" >&2; exit 1; }
mkdir -p "$OUT"; cp "$DTB" "$OUT/sm8550-samsung-dm1q.dtb"; DTB="$OUT/sm8550-samsung-dm1q.dtb"

echo "== 2. check-wlan-dtb.py"
python3 "$HERE/check-wlan-dtb.py" "$DTB"

echo "== 3. kernel from $(basename "$APK"), cmdline from the reference vendor_boot"
mkdir -p "$W/apk"; tar -xzf "$APK" -C "$W/apk" --wildcards 'boot/vmlinuz*' 2>/dev/null || true
VMLINUZ="$(ls "$W"/apk/boot/vmlinuz* 2>/dev/null | head -1)"
[ -f "$VMLINUZ" ] || { echo "no boot/vmlinuz* in $APK" >&2; exit 1; }
mkdir -p "$W/ref"; unpack_bootimg --boot_img "$REF/vendor_boot.img" --out "$W/ref" > "$W/ref/unpack.txt"
CMDLINE="$(sed -n 's/^vendor command line args: //p' "$W/ref/unpack.txt")"
[ -n "$CMDLINE" ] || { echo "could not read the reference cmdline" >&2; exit 1; }
echo "cmdline: $CMDLINE"

echo "== 4. make-boot-images.sh"
bash "$HERE/make-boot-images.sh" --image "$VMLINUZ" --dtb "$DTB" --out "$OUT" --cmdline "$CMDLINE"

echo "== 5. verify against $REF"
mkdir -p "$W/new"; unpack_bootimg --boot_img "$OUT/vendor_boot.img" --out "$W/new" > "$W/new/unpack.txt"
fail=0
chk() { if cmp -s "$2" "$3"; then echo "  same      $1"; else echo "  DIFFERENT $1"; fail=1; fi; }
chk "vendor ramdisk" "$W/ref/vendor_ramdisk00" "$W/new/vendor_ramdisk00"
chk "bootconfig"     "$W/ref/bootconfig"       "$W/new/bootconfig"
[ "$(sed -n 's/^vendor command line args: //p' "$W/new/unpack.txt")" = "$CMDLINE" ] && echo "  same      vendor cmdline" || { echo "  DIFFERENT vendor cmdline"; fail=1; }
cmp -s "$W/new/dtb" "$DTB" && echo "  ok        vendor_boot carries the new DTB" || { echo "  DIFFERENT vendor_boot DTB != compiled DTB"; fail=1; }
mkdir -p "$W/bref" "$W/bnew"
unpack_bootimg --boot_img "$REF/boot.img" --out "$W/bref" >/dev/null; unpack_bootimg --boot_img "$OUT/boot.img" --out "$W/bnew" >/dev/null
# boot.img kernel = gzip(Image) ++ DTB: compare the gzip part (reference size minus the reference DTB)
REFDTB_SIZE="$(sed -n 's/^dtb size: //p' "$W/ref/unpack.txt")"
KB=$(( $(stat -c %s "$W/bref/kernel") - REFDTB_SIZE ))
if [ "$(head -c "$KB" "$W/bref/kernel" | sha256sum | cut -c1-64)" = "$(head -c "$KB" "$W/bnew/kernel" | sha256sum | cut -c1-64)" ]; then
	echo "  same      boot.img kernel (gzip Image, $KB bytes)"
elif [ "$NEWK" = 1 ]; then echo "  differs   boot.img kernel (expected: --new-kernel)"
else echo "  DIFFERENT boot.img kernel"; fail=1; fi
tail -c "$(stat -c %s "$DTB")" "$W/bnew/kernel" | cmp -s - "$DTB" && echo "  ok        boot.img carries the new DTB appended" || { echo "  DIFFERENT boot.img DTB"; fail=1; }

echo "== DTB differences vs the reference (dtc -I dtb -O dts, diff)"
dtc -I dtb -O dts -q "$W/ref/dtb" 2>/dev/null > "$W/ref.dts" || true
dtc -I dtb -O dts -q "$DTB" 2>/dev/null > "$W/new.dts" || true
diff -u "$W/ref.dts" "$W/new.dts" | sed -n '1,60p' || true
# does the kernel inside the new boot.img carry the PCIe fix? (a string only the fixed qcom_pcie_config_sid_1_9_0() has)
nfix="$(gzip -dc < "$W/bnew/kernel" 2>/dev/null | grep -c -a -F 'Malformed iommu-map property' || true)"
if [ "${nfix:-0}" -ge 1 ]; then echo "PCIe BDF-to-SID fix in this kernel: YES"; else echo "PCIe BDF-to-SID fix in this kernel: no"; fi
[ "$fail" = 0 ] && echo "RESULT: image set OK in $OUT" || { echo "RESULT: verification FAILED"; exit 1; }
