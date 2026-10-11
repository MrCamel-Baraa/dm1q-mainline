#!/usr/bin/env bash
# Flash ONE small boot-chain partition from TWRP recovery, the proven way (docs/06, 2026-09-28):
#
#   adb push image -> recovery /tmp
#   sha256 on the device == sha256 on the host            (catches a bad push)
#   dd conv=fsync into /dev/block/by-name/<part>, sync
#   drop caches, read the partition back with `adb exec-out`
#   sha256 of the readback == sha256 of the image          (catches a bad write)
#
# It never streams a write with `adb exec-in`: that once corrupted the boot partition
# (19 of 96 MiB matched neither old nor new image) and was only caught by the readback.
# Only boot / vendor_boot / init_boot / dtbo are accepted -- the images
# make-boot-images.sh produces, each padded to its exact partition size. userdata, the
# bootloader partitions and everything else are refused on purpose.
#
# Usage: scripts/flash-recovery.sh <boot|vendor_boot|init_boot|dtbo> <image>
# Needs the phone in TWRP recovery with root adbd (`adb get-state` == recovery).
set -euo pipefail

PART="${1:-}"; IMG="${2:-}"
case "$PART" in
boot|vendor_boot|init_boot|dtbo) ;;
*) sed -n '2,20p' "$0"; echo "refusing partition '${PART}'" >&2; exit 2 ;;
esac
[ -f "$IMG" ] || { echo "no such image: $IMG" >&2; exit 2; }

[ "$(adb get-state 2>/dev/null || true)" = recovery ] || { echo "phone is not in recovery" >&2; exit 2; }
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adbd is not running as root" >&2; exit 2; }

DEV="/dev/block/by-name/$PART"
SIZE=$(stat -c %s "$IMG")
PSIZE=$(adb shell "blockdev --getsize64 $DEV" | tr -d '\r')
[ -n "$PSIZE" ] || { echo "cannot size $DEV" >&2; exit 2; }
[ "$SIZE" -le "$PSIZE" ] || { echo "image ($SIZE B) is larger than $PART ($PSIZE B)" >&2; exit 1; }
[ $((SIZE % 4096)) -eq 0 ] || { echo "image size is not a multiple of 4096" >&2; exit 1; }

HOST=$(sha256sum "$IMG" | cut -d' ' -f1)
echo "== $PART  <-  $IMG"
echo "   image   $SIZE bytes  sha256 $HOST"
echo "   target  $DEV -> $(adb shell "readlink -f $DEV" | tr -d '\r')  ($PSIZE bytes)"
echo "   now flashing: $(adb shell "sha256sum $DEV" | cut -d' ' -f1)"

adb push "$IMG" /tmp/flash.img >/dev/null
DEVSUM=$(adb shell "sha256sum /tmp/flash.img" | cut -d' ' -f1)
if [ "$DEVSUM" != "$HOST" ]; then
	echo "PUSH CORRUPTED: device $DEVSUM != host $HOST -- nothing was written" >&2
	adb shell "rm -f /tmp/flash.img"
	exit 1
fi
echo "   push verified (device sha256 == host)"

adb shell "dd if=/tmp/flash.img of=$DEV bs=1M conv=fsync 2>&1 && sync" | tail -3
adb shell "sync; echo 3 > /proc/sys/vm/drop_caches; blockdev --flushbufs $DEV 2>/dev/null; true"

BS=4096
BACK=$(adb exec-out "dd if=$DEV bs=$BS count=$((SIZE / BS)) 2>/dev/null" | sha256sum | cut -d' ' -f1)
adb shell "rm -f /tmp/flash.img"
if [ "$BACK" = "$HOST" ]; then
	echo "   READBACK VERIFIED: $PART now == $(basename "$IMG") (sha256 ${HOST:0:16}..)"
else
	echo "READBACK MISMATCH: partition $BACK != image $HOST -- $PART is NOT what you intended; reflash before rebooting" >&2
	exit 1
fi
