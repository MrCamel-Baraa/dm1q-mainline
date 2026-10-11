#!/usr/bin/env bash
# Regenerate evidence.txt next to this script: every number quoted in docs/07 section 14 about the PCIe
# BDF-to-SID table, straight from the sources, the DTBs, the predictor and the logs (nothing retyped).
# Usage: bash make-evidence.sh        (needs unpack_bootimg, python3; reads the cached 7.3-rc3 tree)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TREE="${KSRC:-$HOME/.cache/dm1q-kernel-src/full/linux-7.3-rc3}"
SCR="$REPO/../_scratch"
OUT="$HERE/evidence.txt"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
sec() { printf '\n================================================================================\n== %s\n================================================================================\n' "$*"; }
{
echo "Evidence for docs/07-wlan-bringup.md section 14 (generated $(date -u +%FT%TZ) by $(basename "$0"))"

sec "1. 7.3-rc3 drivers/pci/controller/dwc/pcie-qcom.c: the iommu-map parser (blob $(git hash-object "$TREE/drivers/pci/controller/dwc/pcie-qcom.c" | cut -c1-12); upstream patch pre-image: b58a607b713f)"
cat -n "$TREE/drivers/pci/controller/dwc/pcie-qcom.c" | sed -n '1144,1216p'
echo "   ... call site, ops table, SoC match:"
cat -n "$TREE/drivers/pci/controller/dwc/pcie-qcom.c" | sed -n '1425,1432p;1565,1573p;1598,1600p;2492p'

sec "2. 7.3-rc3 sm8550.dtsi: the PCIe0 node (compatible, maps) and the SMMU's #iommu-cells"
grep -n 'pcie0: pcie@1c00000' -A 3 "$TREE/arch/arm64/boot/dts/qcom/sm8550.dtsi" | head -5
grep -n 'msi-map\|iommu-map' -A 1 "$TREE/arch/arm64/boot/dts/qcom/sm8550.dtsi" | sed -n '1,8p'
grep -n 'apps_smmu: iommu@15000000' -A 24 "$TREE/arch/arm64/boot/dts/qcom/sm8550.dtsi" | grep -E 'apps_smmu|#iommu-cells'

sec "3. OF core: the legacy 4-cell shape it tolerates (drivers/of/base.c)"
n=$(grep -n 'static bool of_check_bad_map' "$TREE/drivers/of/base.c" | cut -d: -f1)
cat -n "$TREE/drivers/of/base.c" | sed -n "${n},$((n+11))p"
grep -n 'treating as 1-cell output' "$TREE/drivers/of/base.c"

sec "4. The DTBs actually flashed: v8 (5-cell, from sm8550.dtsi) and v9 (legacy 4-cell override)"
for s in pmos-v8-r4-rails pmos-v9-r4-iommu-legacy; do
	d="$W/$s"; mkdir -p "$d"
	if [ -f "$SCR/$s/vendor_boot.img" ] && unpack_bootimg --boot_img "$SCR/$s/vendor_boot.img" --out "$d" >/dev/null 2>&1; then
		echo "-- $s  (vendor_boot DTB sha256 $(sha256sum "$d/dtb" | cut -c1-16)...)"
		python3 - "$d/dtb" <<'PYEOF'
import struct, sys
sys.path.insert(0, "/dev/null")
buf = open(sys.argv[1], "rb").read()
magic, total, off_s, off_str, off_r, ver, lc, cpu, sz_str, sz_s = struct.unpack(">10I", buf[:40])
strings, pos, stack, props = buf[off_str:off_str + sz_str], off_s, [], {}
def cstr(b, p):
    e = b.index(b"\0", p); return b[p:e].decode(), e + 1
while True:
    tok = struct.unpack(">I", buf[pos:pos + 4])[0]; pos += 4
    if tok == 1:
        name, pos = cstr(buf, pos); pos = (pos + 3) & ~3
        stack.append("/" if not stack else stack[-1].rstrip("/") + "/" + name)
    elif tok == 2: stack.pop()
    elif tok == 3:
        ln, no = struct.unpack(">II", buf[pos:pos + 8]); pos += 8
        data = buf[pos:pos + ln]; pos = (pos + ln + 3) & ~3
        props[(stack[-1], cstr(strings, no)[0])] = data
    elif tok == 9: break
for node, name in (("/soc@0/pcie@1c00000", "iommu-map"), ("/soc@0/pcie@1c00000", "msi-map"), ("/soc@0/iommu@15000000", "#iommu-cells")):
    d = props.get((node, name))
    w = struct.unpack(">%dI" % (len(d) // 4), d) if d else ()
    print("   %-22s %-13s %2d cells: %s" % (node.split("/")[-1], name, len(w), " ".join("0x%x" % x for x in w)))
PYEOF
	else
		echo "-- $s: image set not available here"
	fi
done

sec "5. What each parser programs into the controller's BDF-to-SID table (scripts/predict-qcom-bdf-sid-table.py)"
for s in pmos-v8-r4-rails pmos-v9-r4-iommu-legacy; do
	[ -f "$W/$s/dtb" ] && { echo "######## $s"; python3 "$REPO/scripts/predict-qcom-bdf-sid-table.py" "$W/$s/dtb"; echo; }
done

sec "6. The three failure signatures, verbatim from the saved logs (power-on -> failure)"
for f in notes/2026-10-03-v7-wlan-boot/phone-probe-v7.txt notes/2026-10-05-v8-wlan-rails/dmesg.txt notes/2026-10-07-v8-fresh/dmesg.txt; do
	echo "-- $f"
	grep -h -E 'mhi mhi0|failed to power up mhi|probe of 0000:01:00.0 with driver ath11k_pci failed' "$REPO/$f" | cut -c1-170 | head -14
done

sec "7. /proc/interrupts around the fresh attempt (notes/2026-10-07-v8-fresh/regdump-load.txt): root port line 0 -> 2, endpoint's 11 vectors stay 0"
grep -E '^#####|--- /proc/interrupts|ITS-PCI-MSI|REGDUMP-MARK' "$REPO/notes/2026-10-07-v8-fresh/regdump-load.txt" | grep -v -E '^#####( AER| config)' | cut -c1-170

sec "8. The carried patch"
P="$REPO/pmaports/device/testing/linux-samsung-dm1q-mainline/pci-qcom-honor-iommu-cells-in-config-sid.patch"
sha512sum "$P" | cut -c1-40 | sed 's/$/... pci-qcom-honor-iommu-cells-in-config-sid.patch/'
grep -n 'index ' "$P"
echo "compile check (notes/2026-10-08-pcie-bdf-sid-regression/compile-check.sh, clang W=1, real dm1q config):"
grep -E 'compile exit code|blob after revert' "$HOME/.cache/dm1q-kernel-src/out-chk/compile-check.log" 2>/dev/null | sort -u

sec "9. Upstream (read 2026-10-08)"
cat <<'EOF'
patch    "PCI: qcom: Honor IOMMU provider's #iommu-cells in qcom_pcie_config_sid_1_9_0()", Manivannan Sadhasivam,
         posted 2026-09-07, Message-ID <20260907143349.317495-1-mani@kernel.org>; thread read at
         https://ratatoskr.run/linux-pci/2026/09/17525884/t
         Tested-by Loic Poulain (Arduino Monza: "ATH11k/WiFi was broken for me. This fixes the issue") and Neil Armstrong
         (SM8650-HDK); applied 2026-09-17 to Mani's pci/controller/qcom tree, commit 626acf6efc69c666ffee50bf18e7b95e68670c6a
DT       "arm64: dts: qcom: Fix the PCIe iommu-map entries" series, [PATCH 00/22], 2026-07-30 (4-cell -> 5-cell entries)
OF core  commit ccb2fd725d41 "of: Respect #{iommu,msi}-cells in maps" (7.2-rc1) -- why the DTs had to change
EOF
} > "$OUT" 2>&1
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
