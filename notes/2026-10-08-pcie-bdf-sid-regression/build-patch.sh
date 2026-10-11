#!/usr/bin/env bash
# Build pmaports/device/testing/linux-samsung-dm1q-mainline/pci-qcom-honor-iommu-cells-in-config-sid.patch
# from the pristine 7.3-rc3 tree, and verify it three ways:
#   1. the post-image is byte-identical to the upstream patch's post-image (blob 42cbeef083ca, in mkpatch.py)
#   2. the pre-image is the pristine 7.3-rc3 file (blob b58a607b713f, the upstream index line)
#   3. `patch -p1` of the finished file on a pristine copy reproduces the post-image blob
# Usage: bash build-patch.sh        (from anywhere)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TREE="${KSRC:-$HOME/.cache/dm1q-kernel-src/full/linux-7.3-rc3}"
F=drivers/pci/controller/dwc/pcie-qcom.c
OUT="$REPO/pmaports/device/testing/linux-samsung-dm1q-mainline/pci-qcom-honor-iommu-cells-in-config-sid.patch"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

[ "$(git hash-object "$TREE/$F" | cut -c1-12)" = b58a607b713f ] || { echo "pre-image is not upstream's b58a607b713f" >&2; exit 1; }
python3 "$HERE/mkpatch.py" "$TREE/$F" "$W/patched.c"

mkdir -p "$W/g/$(dirname $F)"; cd "$W/g"
git init -q; git config user.email dm1q@example.invalid; git config user.name dm1q
cp "$TREE/$F" "$F"; git add -A; git commit -qm base
cp "$W/patched.c" "$F"; git diff > "$W/body.diff"

cat > "$OUT" <<'HDR'
From: Manivannan Sadhasivam <mani@kernel.org>
Subject: [PATCH] PCI: qcom: Honor IOMMU provider's #iommu-cells in qcom_pcie_config_sid_1_9_0()

Carried unchanged from upstream. Applied 2026-09-17 to Manivannan Sadhasivam's
PCI qcom tree as commit 626acf6efc69c666ffee50bf18e7b95e68670c6a; posted as
Message-ID <20260907143349.317495-1-mani@kernel.org> on linux-pci (thread read at
https://ratatoskr.run/linux-pci/2026/09/17525884/t). Tested-by: Loic Poulain
(Arduino Monza, ath11k WiFi was broken without it) and Neil Armstrong (SM8650-HDK).
Not in 7.3-rc3. Drop this patch once the kernel is a release that has it.
Why dm1q needs it: docs/07-wlan-bringup.md section 14.

qcom_pcie_config_sid_1_9_0() reads the "iommu-map" property as an array
of fixed four-word {rid-base, phandle, sid, rid-len} entries to program
the BDF to SID translation table. But that layout only holds for an
IOMMU with '#iommu-cells = <1>'. The PCIe SMMUs on these SoCs use
'#iommu-cells = <2>' (SID and mask), so per the pci-iommu binding each
entry is really five cells long.

This used to work only because the DTs were themselves broken. They
described iommu-map with four-cell entries that omitted the SID mask,
which of_map_id() tolerated via its of_check_bad_map() fallback, and the
four-word parsing coincidentally matched that malformed shape.

Since commit ccb2fd725d41 ("of: Respect #{iommu,msi}-cells in maps") the
OF core parses such maps correctly, so the device trees were converted
to proper five-cell entries, e.g. commit c41749e9554d ("arm64: dts:
qcom: sm8250: Fix the PCIe iommu-map entries"). With five-cell entries
the fixed four-word stride slips by one cell for each entry after the
first, so qcom_pcie_config_sid_1_9_0() reads the endpoint mapping's RID
from the preceding entry's length cell and its SID from the phandle cell.
As the RID is the hash key, the endpoint's real RID is never programmed
into the BDF to SID table. Its DMA then hashes to an unprogrammed slot,
gets tagged with SID 0 and the SMMU faults like below on QCS8300:

  arm-smmu 15200000.iommu: Unhandled context fault: fsr=0x402, iova=0xffa00000, cbfrsynra=0x0, cb=1

To fix this, walk the map with a stride of 3 + '#iommu-cells' of the
referenced IOMMU and take the SID from the first specifier cell, which is
all the BDF to SID table needs. Validate the layout instead of trusting
the array size. Also, preserve the legacy behavior of the old DTs by
detecting the same pattern that of_check_bad_map() recognizes and
falling back to a stride of four.

Fixes: 4c9398822106 ("PCI: qcom: Add support for configuring BDF to SID mapping for SM8250")
Reported-by: Loic Poulain <loic.poulain@oss.qualcomm.com>
Signed-off-by: Manivannan Sadhasivam <mani@kernel.org>
---
HDR
cat "$W/body.diff" >> "$OUT"

# 3. the finished file applies to a pristine copy and gives the upstream post-image
mkdir -p "$W/t/$(dirname $F)"; cp "$TREE/$F" "$W/t/$F"
( cd "$W/t" && patch -p1 --quiet < "$OUT" )
H="$(git hash-object "$W/t/$F" | cut -c1-12)"
[ "$H" = 42cbeef083ca ] || { echo "applied post-image is $H, expected 42cbeef083ca" >&2; exit 1; }
( cd "$TREE" && patch -p1 --dry-run --quiet < "$OUT" ) && echo "dry-run against the kernel tree: clean"
grep -c '^[-+][^-+]' "$OUT" | sed 's/^/changed lines: /'
echo "wrote $OUT"
sha512sum "$OUT"
