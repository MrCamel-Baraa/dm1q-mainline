#!/bin/sh
# Device side (TWRP recovery shell, busybox sh) of scripts/pull-dsp-vendor-firmware.sh; docs/13. READ-ONLY on the phone's storage:
# it lists the partition layout, mounts the phone's own vendor partition and its modem (firmware) partition READ-ONLY in RAM-disk directories
# when nothing mounts them already, and prints one line per ADSP firmware file it finds (adsp*, battmgr*). It never writes to a partition and
# never mounts read-write.
#   scan    print the layout, the mounts, the directories that hold ADSP files (ls -l), and  FOUND <real path> <bytes> <sha256> <name>  lines
#           (or NONE); it LEAVES what it had to mount mounted so the files can be pulled
#   umount  unmount what scan mounted ($MNT, $MNTM), if mounted
# Env (the PC-side test uses them): BLOCKDIR (/dev/block) MNT (/mnt/dm1q-vendor) MNTM (/mnt/dm1q-modem)
#   ROOTS ("/vendor /system/vendor /firmware /firmware_mnt /vendor/firmware_mnt") MAXDEPTH (6) SHA PROC_MOUNTS (/proc/mounts)
BLOCKDIR="${BLOCKDIR:-/dev/block}"
MNT="${MNT:-/mnt/dm1q-vendor}"
MNTM="${MNTM:-/mnt/dm1q-modem}"
ROOTS="${ROOTS:-/vendor /system/vendor /firmware /firmware_mnt /vendor/firmware_mnt}"
MAXDEPTH="${MAXDEPTH:-6}"
SHA="${SHA:-sha256sum}"
PROC_MOUNTS="${PROC_MOUNTS:-/proc/mounts}"

is_mounted() { grep -q " $1 " "$PROC_MOUNTS" 2>/dev/null; }

case "${1:-}" in
umount)
	for m in "$MNTM" "$MNT"; do
		if is_mounted "$m"; then
			umount "$m" && echo "unmounted $m" || echo "umount of $m failed"
		else
			echo "$m is not mounted: nothing to do"
		fi
	done
	exit 0
	;;
scan) ;;
*) sed -n '2,12p' "$0"; exit 2 ;;
esac

echo "== layout"
echo "slot suffix: $(getprop ro.boot.slot_suffix 2>/dev/null)"
echo "mapper:"; ls -l "$BLOCKDIR/mapper" 2>&1 | sed 's/^/  /'
echo "by-name (super / vendor / system / modem / firmware / dsp / radio):"
for n in "$BLOCKDIR"/by-name/*; do
	case "$(basename "$n")" in super*|vendor*|system*|modem*|firmware*|dsp*|radio*|apnhlos*|bluetooth*) echo "  $(basename "$n")" ;; esac
done
echo "mounts of interest:"
grep -E ' /vendor| /system| /firmware| /firmware_mnt| /mnt/dm1q-' "$PROC_MOUNTS" 2>/dev/null | sed 's/^/  /'

mount_ro() { # mount_ro <dev> <dir> <fstypes...>; read-only only
	dev="$1"; dir="$2"; shift 2
	[ -e "$dev" ] || return 1
	mkdir -p "$dir" || return 1
	for fs in "$@"; do
		if mount -t "$fs" -o ro "$dev" "$dir" 2>/dev/null; then
			echo "mounted $dev as $fs at $dir (read-only)"
			return 0
		fi
	done
	echo "could not mount $dev read-only as: $*"
	return 1
}

has_vendor_fw() {
	for r in /vendor /system/vendor; do [ -d "$r/firmware" ] && return 0; done
	return 1
}

# 1. the vendor partition (logical partition inside super)
if ! has_vendor_fw; then
	echo "== no mounted vendor firmware directory"
	if command -v twrp >/dev/null 2>&1; then
		echo "trying: twrp mount /vendor"
		twrp mount /vendor 2>&1 | sed 's/^/  /'
	fi
fi
if ! has_vendor_fw; then
	for dev in "$BLOCKDIR/mapper/vendor" "$BLOCKDIR/mapper/vendor_a" "$BLOCKDIR/mapper/vendor_b" "$BLOCKDIR/by-name/vendor" "$BLOCKDIR/by-name/vendor_a"; do
		if mount_ro "$dev" "$MNT" erofs ext4 f2fs; then ROOTS="$ROOTS $MNT"; break; fi
	done
fi

# 2. the modem / firmware partition (Qualcomm keeps adsp.mbn, adsp_dtb.mbn ... in its image/ directory)
have_modem=0
for r in /firmware /firmware_mnt /vendor/firmware_mnt; do
	[ -d "$r/image" ] && have_modem=1
done
if [ "$have_modem" = 0 ]; then
	for dev in "$BLOCKDIR/by-name/modem" "$BLOCKDIR/by-name/modem_a" "$BLOCKDIR/by-name/modem_b" "$BLOCKDIR/by-name/firmware" "$BLOCKDIR/by-name/apnhlos" "$BLOCKDIR/by-name/apnhlos_a"; do
		if mount_ro "$dev" "$MNTM" vfat ext4 erofs; then ROOTS="$ROOTS $MNTM"; break; fi
	done
fi

echo "== search (adsp*, battmgr*) under: $ROOTS"
found=0
for r in $ROOTS; do
	[ -d "$r" ] || continue
	list=$(find "$r" -maxdepth "$MAXDEPTH" \( -type f -o -type l \) \( -name 'adsp*' -o -name 'battmgr*' \) 2>/dev/null | sort)
	[ -n "$list" ] || continue
	echo "-- $r"
	echo "$list" | while read -r f; do dirname "$f"; done | sort -u | while read -r d; do
		echo "DIR $d"; ls -l "$d" 2>&1 | sed 's/^/    /' | head -80
	done
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
