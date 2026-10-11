#!/usr/bin/env bash
# Assemble ONE pmOS disk image (GPT: pmOS_boot + pmOS_root) from the two
# images `pmbootstrap install --split` produces, using only regular files --
# no loop devices, no sudo. Needed because the host kernel here has
# loop.max_part=0, which breaks pmbootstrap's own non-split install
# (mkfs on /dev/installp2 -> "Device size reported to be zero").
#
# The result is meant to be flashed to the Android `userdata` partition;
# pmOS's initramfs (mount_subpartitions) finds pmOS_boot/pmOS_root inside it.
#
# Usage: scripts/make-pmos-disk.sh <boot.img> <root.img> <out.img> [root_size_MiB]
#   root_size_MiB (default 4096): the root filesystem is grown to this size.
#   pmOS cannot grow it further at first boot (nothing to grow into inside
#   the image), so pick what you want up front.
set -euo pipefail
BOOT="${1:?boot img}"; ROOT="${2:?root img}"; OUT="${3:?out img}"; ROOT_MIB="${4:-4096}"

MiB=$((1024 * 1024))
boot_bytes=$(stat -c %s "$BOOT")
[ $((boot_bytes % MiB)) -eq 0 ] || { echo "boot img not MiB-aligned" >&2; exit 1; }
[ "$ROOT_MIB" -ge $(( ($(stat -c %s "$ROOT") + MiB - 1) / MiB )) ] || {
	echo "root_size_MiB smaller than the root image" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp --reflink=auto "$ROOT" "$tmp/root.img"
truncate -s "${ROOT_MIB}M" "$tmp/root.img"
e2fsck -fy "$tmp/root.img" >/dev/null || [ $? -le 1 ]
resize2fs "$tmp/root.img" >/dev/null

# Auto-apply the initramfs-extra usr-merge fix (see fix-initramfs-extra.sh)
# if the boot image still has the unfixed symlinks -- keeps this script
# correct even when re-run from a freshly re-installed pmOS boot image.
cp --reflink=auto "$BOOT" "$tmp/boot.img"
if debugfs -R 'stat /initramfs-extra' "$tmp/boot.img" 2>/dev/null | grep -q Inode; then
	debugfs -R 'dump /initramfs-extra /dev/stdout' "$tmp/boot.img" 2>/dev/null > "$tmp/extra.orig"
	if gzip -dc "$tmp/extra.orig" 2>/dev/null | cpio -t 2>/dev/null | grep -q -E '^(bin|lib|sbin)$'; then
		"$(dirname "$0")/fix-initramfs-extra.sh" "$tmp/extra.orig" "$tmp/extra.fixed"
		debugfs -w -R 'rm /initramfs-extra' "$tmp/boot.img" >/dev/null
		debugfs -w -R "write $tmp/extra.fixed /initramfs-extra" "$tmp/boot.img" >/dev/null
		echo "boot img: fixed initramfs-extra (stripped bin/lib/sbin symlinks)"
	fi
fi
BOOT="$tmp/boot.img"
boot_bytes=$(stat -c %s "$BOOT")

# Layout in MiB: 1 (GPT) | boot | root | 1 (backup GPT)
boot_start=1
root_start=$((boot_start + boot_bytes / MiB))
total=$((root_start + ROOT_MIB + 1))
# UFS LUs on dm1q report 4096-byte logical sectors (confirmed on hardware,
# 2026-09-28: blockdev --getss /dev/block/by-name/userdata = 4096). The
# initramfs counts subpartitions with `fdisk -l` run directly on the real
# UFS partition, which reads the GPT at the DEVICE's sector size -- a GPT
# built with the sfdisk default (512) sits at the wrong byte offset once
# read that way and is invisible (found 2026-09-28, see docs/06). --sector-
# size here only changes how the 1 MiB head/tail GPT metadata is laid out;
# partition start/size below are given in MiB, so boot/root CONTENT lands
# at the same byte offsets either way. HOWEVER (2026-09-28, tested twice):
# e2fsck/resize2fs above regenerate a few superblock bytes (timestamps etc)
# near the start of root even when nothing else changed, and debugfs -w on
# boot changes which blocks hold what -- so a partial "just patch head/tail"
# reflash is NOT safe here. Always reflash the whole image.
rm -f "$OUT"; truncate -s "${total}M" "$OUT"
sfdisk --quiet --sector-size 4096 "$OUT" <<EOF
label: gpt
start=${boot_start}MiB, size=$((boot_bytes / MiB))MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
start=${root_start}MiB, size=${ROOT_MIB}MiB, type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
EOF
dd if="$BOOT" of="$OUT" bs=1M seek=$boot_start conv=notrunc status=none
dd if="$tmp/root.img" of="$OUT" bs=1M seek=$root_start conv=notrunc status=none

sfdisk --sector-size 4096 -l "$OUT"
echo "labels:"; dumpe2fs -h "$BOOT" 2>/dev/null | grep -i "volume name"
dumpe2fs -h "$tmp/root.img" 2>/dev/null | grep -i "volume name"
sha256sum "$OUT"
