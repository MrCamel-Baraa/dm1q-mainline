#!/usr/bin/env bash
# Compile-check the carried PCI fix against the real dm1q config WITHOUT a pmbootstrap build (no sudo):
# apply the patch to the cached 7.3-rc3 tree, build ONLY drivers/pci/controller/dwc/pcie-qcom.o with
# clang for arm64 in a scratch output dir, then revert the tree and prove it is pristine again.
# Usage: bash compile-check.sh        (about 2-4 minutes; log: $OUT/compile-check.log)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TREE="${KSRC:-$HOME/.cache/dm1q-kernel-src/full/linux-7.3-rc3}"
OUT="${OUT:-$HOME/.cache/dm1q-kernel-src/out-chk}"
PATCH="$REPO/pmaports/device/testing/linux-samsung-dm1q-mainline/pci-qcom-honor-iommu-cells-in-config-sid.patch"
F=drivers/pci/controller/dwc/pcie-qcom.c
mkdir -p "$OUT"; LOG="$OUT/compile-check.log"; : > "$LOG"

cleanup() {
	( cd "$TREE" && patch -p1 -R --quiet < "$PATCH" ) >>"$LOG" 2>&1
	echo "tree pcie-qcom.c blob after revert: $(git hash-object "$TREE/$F" | cut -c1-12) (pristine is b58a607b713f)" | tee -a "$LOG"
}
[ "$(git hash-object "$TREE/$F" | cut -c1-12)" = b58a607b713f ] || { echo "tree file is not pristine" >&2; exit 1; }
( cd "$TREE" && patch -p1 --quiet < "$PATCH" ) || { echo "patch did not apply" >&2; exit 1; }
trap cleanup EXIT

cp "$HOME/.cache/dm1q-kernel-src/out-real/.config" "$OUT/.config"
M=(make -C "$TREE" O="$OUT" ARCH=arm64 LLVM=1 -j"$(nproc)")
echo "== olddefconfig + prepare" | tee -a "$LOG"
"${M[@]}" olddefconfig prepare >>"$LOG" 2>&1 || { echo "prepare FAILED, see $LOG"; tail -20 "$LOG"; exit 1; }
echo "== compile pcie-qcom.o (patched)" | tee -a "$LOG"
"${M[@]}" W=1 drivers/pci/controller/dwc/pcie-qcom.o >>"$LOG" 2>&1
RC=$?
grep -n -E "pcie-qcom\.c.*(warning|error)" "$LOG" | head -20
echo "compile exit code: $RC" | tee -a "$LOG"
[ -f "$OUT/drivers/pci/controller/dwc/pcie-qcom.o" ] && ls -l "$OUT/drivers/pci/controller/dwc/pcie-qcom.o"
exit $RC
