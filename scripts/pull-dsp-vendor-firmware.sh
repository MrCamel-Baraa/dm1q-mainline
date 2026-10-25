#!/usr/bin/env bash
# Pull the phone's OWN ADSP firmware (adsp.mbn / adsp_dtb.mbn or the .mdt + .bNN split form, plus adsp*.jsn and battmgr*) from its vendor and modem
# partitions while it is in TWRP (docs/13: without the ADSP there is no audio, no sensors, no USB-C role handling). READ-ONLY on the phone: it pushes
# scripts/twrp-find-dsp-fw.sh to /tmp, which mounts the vendor and modem partitions read-only in RAM-disk directories if TWRP has not, prints what it
# finds, and this script pulls every file (verifying size and sha256 against the device's own numbers) and unmounts again. Nothing is flashed or
# written to a partition. The blobs are Samsung's / Qualcomm's proprietary firmware: they go to a directory OUTSIDE the repo and are never committed.
# Usage: bash scripts/pull-dsp-vendor-firmware.sh [outdir]      (default ../_scratch/dm1q-dsp-fw-vendor)
# Needs: the phone in TWRP with root adbd (like flash-recovery.sh). Exit 0 = the ADSP image and its DTB pulled and verified; 1 = nothing/partial; 2 = not ready.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="${1:-$REPO/../_scratch/dm1q-dsp-fw-vendor}"

[ "$(adb get-state 2>/dev/null || true)" = recovery ] || { echo "phone is not in recovery" >&2; exit 2; }
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adbd is not running as root" >&2; exit 2; }

mkdir -p "$OUT" || exit 2
adb push "$HERE/twrp-find-dsp-fw.sh" /tmp/twrp-find-dsp-fw.sh >/dev/null || { echo "adb push failed" >&2; exit 2; }
cleanup() { adb shell "sh /tmp/twrp-find-dsp-fw.sh umount; rm -f /tmp/twrp-find-dsp-fw.sh" 2>&1 | tr -d '\r' | sed 's/^/device: /'; }
trap cleanup EXIT

echo "== scanning the phone (read-only)"
adb shell "sh /tmp/twrp-find-dsp-fw.sh scan" | tr -d '\r' > "$OUT/scan.txt"
cat "$OUT/scan.txt"

echo
echo "== pulling to $OUT"
npulled=0; bad=0; main=0; dtb=0
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
	case "${name,,}" in
	adsp.mbn|adsp.mdt) main=1 ;;
	adsp_dtb.mbn|adsp_dtb.mdt) dtb=1 ;;
	esac
done < <(grep '^FOUND ' "$OUT/scan.txt")

if [ "$npulled" -gt 0 ]; then
	( cd "$OUT" && for f in *; do case "$f" in scan.txt|SHA256SUMS) continue ;; esac; sha256sum -- "$f"; done > SHA256SUMS )
fi

echo
if [ "$npulled" = 0 ]; then echo "no ADSP firmware found: read $OUT/scan.txt (layout) and tell Claude"; exit 1; fi
if [ "$main" = 0 ]; then echo "files pulled but NO adsp.mbn / adsp.mdt: read $OUT/scan.txt"; exit 1; fi
if [ "$dtb" = 0 ]; then echo "adsp image pulled but NO adsp_dtb.*: read $OUT/scan.txt"; exit 1; fi
if [ "$bad" != 0 ]; then echo "some files failed verification: see above"; exit 1; fi
echo "ADSP image and DTB pulled and verified. Reboot to system; then tell Claude."
exit 0
