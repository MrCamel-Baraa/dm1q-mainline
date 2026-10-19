#!/usr/bin/env bash
# Pull the phone's OWN Adreno 740 firmware (zap shader, SQE, GMU) from its vendor partition while it is in TWRP (docs/11 section 7, the
# fallback of R1: the secure world refused the generic linux-firmware zap). READ-ONLY on the phone: it pushes scripts/twrp-find-gpu-fw.sh to
# /tmp, which mounts the vendor partition read-only in a RAM-disk directory if TWRP has not, prints what it finds, and this script pulls every
# file (verifying size and sha256 against the device's own numbers) and unmounts again. Nothing is flashed or written to a partition.
# The blobs are Samsung's proprietary firmware: they go to a directory OUTSIDE the repo and are never committed.
# Usage: bash scripts/pull-gpu-vendor-firmware.sh [outdir]      (default ../_scratch/dm1q-gpu-fw-vendor)
# Needs: the phone in TWRP with root adbd (like flash-recovery.sh). Exit 0 = zap shader pulled and verified; 1 = nothing/partial; 2 = not ready.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="${1:-$REPO/../_scratch/dm1q-gpu-fw-vendor}"
REF="${GPU_FW_REF:-$REPO/../_scratch/dm1q-gpu-fw}"

[ "$(adb get-state 2>/dev/null || true)" = recovery ] || { echo "phone is not in recovery" >&2; exit 2; }
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adbd is not running as root" >&2; exit 2; }

mkdir -p "$OUT" || exit 2
adb push "$HERE/twrp-find-gpu-fw.sh" /tmp/twrp-find-gpu-fw.sh >/dev/null || { echo "adb push failed" >&2; exit 2; }
cleanup() { adb shell "sh /tmp/twrp-find-gpu-fw.sh umount; rm -f /tmp/twrp-find-gpu-fw.sh" 2>&1 | tr -d '\r' | sed 's/^/device: /'; }
trap cleanup EXIT

echo "== scanning the phone (read-only)"
adb shell "sh /tmp/twrp-find-gpu-fw.sh scan" | tr -d '\r' > "$OUT/scan.txt"
cat "$OUT/scan.txt"

echo
echo "== pulling to $OUT"
npulled=0; bad=0; zap=0
declare -A seen
while read -r _ rpath size sum name; do
	if [ -n "${seen[$name]:-}" ]; then
		[ "${seen[$name]}" = "$sum" ] || { echo "CONFLICT: two different files named $name"; bad=1; }
		continue
	fi
	seen[$name]="$sum"
	if ! adb pull "$rpath" "$OUT/$name" >/dev/null 2>&1; then echo "PULL FAILED: $rpath"; bad=1; continue; fi
	hsum=$(sha256sum "$OUT/$name" | cut -d' ' -f1)
	hsize=$(stat -c %s "$OUT/$name")
	if [ "$hsum" != "$sum" ] || [ "$hsize" != "$size" ]; then
		echo "MISMATCH: $name host $hsize B $hsum, device $size B $sum"; rm -f "$OUT/$name"; bad=1; continue
	fi
	echo "ok  $name  $size bytes  sha256 $sum"
	npulled=$((npulled + 1))
	case "$name" in a7*_zap*) zap=1 ;; esac
done < <(grep '^FOUND ' "$OUT/scan.txt")

if [ "$npulled" -gt 0 ]; then
	( cd "$OUT" && for f in *; do case "$f" in scan.txt|SHA256SUMS) continue ;; esac; sha256sum -- "$f"; done > SHA256SUMS )
fi

echo
if [ -d "$REF" ]; then
	for f in a740_sqe.fw gmu_gen70200.bin; do
		ref=$(find "$REF" -name "$f" -type f | head -n 1)
		[ -n "$ref" ] && [ -f "$OUT/$f" ] || continue
		if [ "$(sha256sum "$ref" | cut -d' ' -f1)" = "$(sha256sum "$OUT/$f" | cut -d' ' -f1)" ]; then
			echo "$f: identical to the linux-firmware copy"
		else
			echo "$f: DIFFERS from the linux-firmware copy (note it in docs/11)"
		fi
	done
fi
if [ "$npulled" = 0 ]; then echo "no Adreno 740 firmware found: read $OUT/scan.txt (layout) and tell Claude"; exit 1; fi
if [ "$zap" = 0 ]; then echo "SQE/GMU pulled but NO zap shader (a*_zap*) found: read $OUT/scan.txt"; exit 1; fi
if [ "$bad" != 0 ]; then echo "some files failed verification: see above"; exit 1; fi
echo "zap shader pulled and verified. Reboot to system; then Claude stages it for S3."
exit 0
