#!/bin/sh
# Device side (TWRP recovery shell, busybox sh) of scripts/pull-gpu-vendor-firmware.sh; docs/11 section 7. READ-ONLY on the phone's storage:
# it lists, mounts the phone's own vendor partition READ-ONLY in a RAM-disk directory when nothing mounts it already, and prints one
# line per Adreno 740 firmware file it finds. It never writes to a partition and never mounts read-write.
#   scan    print the partition/mount layout, find the files, print  FOUND <real path> <bytes> <sha256> <name>  lines (or NONE);
#           when it had to mount the vendor partition it LEAVES it mounted so the files can be pulled
#   umount  unmount what scan mounted ($MNT), if it is mounted
# Env (the PC-side test uses them): BLOCKDIR (/dev/block) MNT (/mnt/dm1q-vendor) ROOTS ("/vendor /system/vendor") MAXDEPTH (6) SHA
#   PROC_MOUNTS (/proc/mounts)
BLOCKDIR="${BLOCKDIR:-/dev/block}"
MNT="${MNT:-/mnt/dm1q-vendor}"
ROOTS="${ROOTS:-/vendor /system/vendor}"
MAXDEPTH="${MAXDEPTH:-6}"
SHA="${SHA:-sha256sum}"
PROC_MOUNTS="${PROC_MOUNTS:-/proc/mounts}"

is_mounted() { grep -q " $1 " "$PROC_MOUNTS" 2>/dev/null; }

case "${1:-}" in
umount)
	if is_mounted "$MNT"; then
		umount "$MNT" && echo "unmounted $MNT" || echo "umount of $MNT failed"
	else
		echo "$MNT is not mounted: nothing to do"
	fi
	exit 0
	;;
scan) ;;
*) sed -n '2,12p' "$0"; exit 2 ;;
esac

echo "== layout"
echo "slot suffix: $(getprop ro.boot.slot_suffix 2>/dev/null)"
echo "mapper:"; ls -l "$BLOCKDIR/mapper" 2>&1 | sed 's/^/  /'
echo "by-name (super / vendor / system / firmware / modem):"
for n in "$BLOCKDIR"/by-name/*; do
	case "$(basename "$n")" in super*|vendor*|system*|firmware*|modem*) echo "  $(basename "$n")" ;; esac
done
echo "mounts of interest:"
grep -E ' /vendor| /system| /vendor/firmware| /mnt/dm1q-vendor' "$PROC_MOUNTS" 2>/dev/null | sed 's/^/  /'

has_fw() { # any root with a firmware directory?
	for r in $ROOTS; do [ -d "$r/firmware" ] && return 0; done
	return 1
}

if ! has_fw; then
	echo "== no mounted vendor firmware directory under: $ROOTS"
	if command -v twrp >/dev/null 2>&1; then
		echo "trying: twrp mount /vendor"
		twrp mount /vendor 2>&1 | sed 's/^/  /'
	fi
fi
if ! has_fw; then
	for dev in "$BLOCKDIR/mapper/vendor" "$BLOCKDIR/mapper/vendor_a" "$BLOCKDIR/mapper/vendor_b" "$BLOCKDIR/by-name/vendor" "$BLOCKDIR/by-name/vendor_a"; do
		[ -e "$dev" ] || continue
		mkdir -p "$MNT" || continue
		for fs in erofs ext4 f2fs; do
			if mount -t "$fs" -o ro "$dev" "$MNT" 2>/dev/null; then
				echo "mounted $dev as $fs at $MNT (read-only)"
				ROOTS="$ROOTS $MNT"
				break 2
			fi
		done
		echo "could not mount $dev read-only as erofs / ext4 / f2fs"
	done
fi

echo "== search"
found=0
for r in $ROOTS; do
	[ -d "$r" ] || continue
	list=$(find "$r" -maxdepth "$MAXDEPTH" \( -type f -o -type l \) \( -name 'a7*_zap*' -o -name 'a740*' -o -name 'gmu_gen70*' -o -name 'a7*_sqe*' \) 2>/dev/null | sort)
	[ -n "$list" ] || continue
	echo "$list" | while read -r f; do
		real=$(readlink -f "$f" 2>/dev/null)
		[ -n "$real" ] || real="$f"
		[ -f "$real" ] || continue
		echo "FOUND $real $(wc -c < "$real") $("$SHA" "$real" | cut -d' ' -f1) $(basename "$f")"
	done
	found=1
done
[ "$found" = 1 ] || echo "NONE"
exit 0
