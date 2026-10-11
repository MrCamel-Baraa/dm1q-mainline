#!/usr/bin/env bash
# Re-apply scripts/fix-initramfs-extra.sh to the /boot/initramfs-extra that lives INSIDE the phone's
# userdata partition (the nested pmOS_boot filesystem), from TWRP recovery.
#
# Why this exists (docs/07 section 12, 2026-10-03): any `apk` operation on the phone that touches
# /lib/firmware, /usr/lib/udev, /usr/share/kernel, /usr/share/deviceinfo, /lib/modules, ... fires
# postmarketos-mkinitfs, which regenerates /boot/initramfs-extra WITH the usr-merge symlinks
# bin/lib/sbin. Our stage 1 has a REAL /lib, so extraction dies with
# "cpio: can't remove old file lib: Is a directory", stage 2 has no udev/e2fsck/parted, and the
# phone never switches root (stage-1 log ends in an endless "couldn't open /dev/input/" loop).
# The boot images are fine; the file on the phone is what broke.
#
# Default is a DRY RUN. It only READS from the phone: saves a full backup of the nested boot
# partition (512 MiB) to $DM1Q_PHONE_WORK, extracts initramfs-extra from that copy, builds the fixed
# file and checks it. With --yes it then replaces /boot/initramfs-extra on the phone (read-only
# `e2fsck -fn` first, loop mount limited to the nested boot partition's byte range, copy to a
# temporary name, sha256 check, atomic rename, sync) and verifies the result on the phone.
#
# Usage: scripts/fix-phone-initramfs-extra.sh [--yes] [--file <initramfs-extra.gz>]
#   --file   install this file instead of the freshly fixed one (use the saved
#            extra-phone-<stamp>.gz to roll back to what the phone had before)
# Needs: phone in TWRP recovery with root adbd; gzip, cpio, debugfs, python3 on the PC.
set -euo pipefail

YES=0; FILE=""
while [ $# -gt 0 ]; do
	case "$1" in
	--yes) YES=1 ;;
	--file) FILE="${2:?--file needs a path}"; shift ;;
	*) sed -n '2,28p' "$0"; exit 2 ;;
	esac
	shift
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${DM1Q_PHONE_WORK:-$HOME/.cache/dm1q-phone}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEV=/dev/block/by-name/userdata
mkdir -p "$WORK"

[ "$(adb get-state 2>/dev/null || true)" = recovery ] || { echo "phone is not in recovery" >&2; exit 2; }
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "adbd is not running as root" >&2; exit 2; }

# --- locate the nested pmOS_boot partition from the GPT in the first sectors of userdata (4096-byte sectors)
SIG="$(adb exec-out "dd if=$DEV bs=4096 skip=1 count=1 2>/dev/null | head -c 8")"
[ "$SIG" = "EFI PART" ] || { echo "no nested GPT at the start of userdata ('$SIG')" >&2; exit 1; }
read -r OFF SIZE < <(adb exec-out "dd if=$DEV bs=4096 skip=2 count=1 2>/dev/null" | python3 -c '
import sys, struct
e = sys.stdin.buffer.read(128)
s, l = struct.unpack("<QQ", e[32:48])
print(s * 4096, (l - s + 1) * 4096)')
[ "$OFF" = 1048576 ] && [ "$SIZE" = 536870912 ] || { echo "unexpected nested boot partition layout: offset $OFF size $SIZE" >&2; exit 1; }
echo "nested pmOS_boot: offset $OFF, size $SIZE (read from the GPT on the phone)"

# --- backup the whole nested boot partition (read only) and pull initramfs-extra out of the copy
BK="$WORK/p1-boot-backup-$STAMP.img"
adb exec-out "dd if=$DEV bs=1M skip=1 count=512 2>/dev/null" > "$BK"
[ "$(stat -c %s "$BK")" = "$SIZE" ] || { echo "short backup read" >&2; exit 1; }
echo "backup: $BK  sha256 $(sha256sum "$BK" | cut -c1-16)"
CUR="$WORK/extra-phone-$STAMP.gz"
debugfs -R "dump /initramfs-extra $CUR" "$BK" >/dev/null 2>&1
[ -s "$CUR" ] || { echo "could not extract /initramfs-extra from the backup" >&2; exit 1; }
echo "phone's current initramfs-extra: $(stat -c %s "$CUR") bytes  sha256 $(sha256sum "$CUR" | cut -c1-16)  (saved as $CUR)"

SYMS="$(gzip -dc "$CUR" | cpio -tv 2>/dev/null | grep -E ' (bin|lib|sbin) ->' || true)"
if [ -n "$FILE" ]; then
	NEW="$FILE"; echo "using --file $NEW (no fix applied)"
elif [ -z "$SYMS" ]; then
	echo "the phone's initramfs-extra has no top-level bin/lib/sbin symlinks -- nothing to fix"; exit 0
else
	echo "top-level symlinks present (these break stage 2):"; echo "$SYMS" | sed 's/^/    /'
	NEW="$WORK/extra-phone-$STAMP.FIXED.gz"
	"$REPO/scripts/fix-initramfs-extra.sh" "$CUR" "$NEW"
	if gzip -dc "$NEW" | cpio -tv 2>/dev/null | grep -qE ' (bin|lib|sbin) ->'; then echo "fix did not remove the symlinks" >&2; exit 1; fi
	echo "fixed file: $NEW ($(stat -c %s "$NEW") bytes, $(gzip -dc "$NEW" | cpio -t 2>/dev/null | wc -l) entries; was $(gzip -dc "$CUR" | cpio -t 2>/dev/null | wc -l))"
fi
HOST="$(sha256sum "$NEW" | cut -d' ' -f1)"

if [ "$YES" != 1 ]; then
	echo
	echo "DRY RUN: nothing was written to the phone. To install $NEW:"
	echo "    scripts/fix-phone-initramfs-extra.sh --yes"
	echo "Rollback to what the phone has now:"
	echo "    scripts/fix-phone-initramfs-extra.sh --yes --file $CUR"
	exit 0
fi

# --- install: push, verify, loop-mount ONLY the nested boot partition, atomic replace, verify
adb push "$NEW" /tmp/initramfs-extra.new >/dev/null
DEVSUM="$(adb shell "sha256sum /tmp/initramfs-extra.new" | cut -d' ' -f1)"
[ "$DEVSUM" = "$HOST" ] || { echo "PUSH CORRUPTED ($DEVSUM != $HOST) -- nothing was written" >&2; adb shell "rm -f /tmp/initramfs-extra.new"; exit 1; }
echo "push verified (device sha256 == host)"

adb shell "OFF=$OFF SIZE=$SIZE DEV=$DEV HOST=$HOST sh -s" <<'EOS' | tr -d '\r'
set -e
LO=$(losetup -f)
losetup -o "$OFF" -S "$SIZE" "$LO" "$DEV"
cleanup() { umount /mnt/p1rw 2>/dev/null || true; losetup -d "$LO" 2>/dev/null || true; }
trap cleanup EXIT
e2fsck -fn "$LO" > /tmp/p1-fsck.out 2>&1 && RC=0 || RC=$?
tail -3 /tmp/p1-fsck.out
if [ "$RC" != 0 ]; then
  # tolerate only the cosmetic summary-count complaints an unclean shutdown leaves behind
  OTHER=$(grep -v -E '^(e2fsck |Pass [1-5]:|Free (blocks|inodes) count wrong|Fix\? no|pmOS_boot: |[*]+)' /tmp/p1-fsck.out | grep -v '^[[:space:]]*$' || true)
  [ -z "$OTHER" ] || { echo "e2fsck -fn reports problems (rc=$RC) -- aborting, nothing was written:"; echo "$OTHER"; exit 1; }
fi
mkdir -p /mnt/p1rw
mount -t ext2 "$LO" /mnt/p1rw
cp /tmp/initramfs-extra.new /mnt/p1rw/initramfs-extra.new
sync
GOT=$(sha256sum /mnt/p1rw/initramfs-extra.new | cut -d' ' -f1)
[ "$GOT" = "$HOST" ] || { echo "COPY MISMATCH on the phone ($GOT) -- leaving the old file in place"; rm -f /mnt/p1rw/initramfs-extra.new; exit 1; }
mv /mnt/p1rw/initramfs-extra.new /mnt/p1rw/initramfs-extra
sync
ls -la /mnt/p1rw/initramfs-extra
EOS

# --- independent verification: fresh read-only mount, hash what is really in /boot now
VER="$(adb shell '
LO=$(losetup -f); losetup -r -o '"$OFF"' -S '"$SIZE"' "$LO" '"$DEV"' && mkdir -p /mnt/p1ro &&
mount -t ext2 -o ro "$LO" /mnt/p1ro && sha256sum /mnt/p1ro/initramfs-extra | cut -d" " -f1
umount /mnt/p1ro 2>/dev/null; losetup -d "$LO" 2>/dev/null; true' | tr -d '\r' | tail -1)"
adb shell "rm -f /tmp/initramfs-extra.new"
if [ "$VER" = "$HOST" ]; then
	echo "VERIFIED: /boot/initramfs-extra on the phone == $(basename "$NEW") (sha256 ${HOST:0:16}..)"
else
	echo "VERIFY MISMATCH: phone has $VER, expected $HOST -- restore with --file $CUR" >&2
	exit 1
fi
