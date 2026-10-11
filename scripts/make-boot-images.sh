#!/usr/bin/env bash
# Assemble dm1q boot images the way the hand-verified v12 boot did (see
# docs/01-phase1-workplan.md 2026-09-21 "attempt 4" and later, and
# docs/06-pmos-userspace-plan.md).
#
# Recipe (recovered by unpacking the booting v12 images + avbtool info):
#   boot.img         header v4, kernel = gzip(Image) with the DTB appended
#                    (ABL rejects the stock DTBO overlay path), no ramdisk,
#                    os_version 16.0.0, patch level 2026-07
#   vendor_boot.img  header v4, stock Samsung vendor ramdisk (unchanged),
#                    our DTB, bring-up cmdline, stock bootconfig
#   init_boot.img    (only with --initramfs) initramfs re-packed as legacy
#                    LZ4, the format that worked from v2 on (gzip did not).
#                    A pmOS initramfs is also fixed up for this device, see
#                    the comments in the initramfs section below.
#   dtbo.img         4096 zero bytes (invalid on purpose)
#   all              avbtool hash footer, algorithm NONE, padded to the real
#                    partition size: boot/vendor_boot 96 MiB, init_boot 8 MiB,
#                    dtbo 16 MiB (sizes read from the restored stock backups)
#
# Usage:
#   scripts/make-boot-images.sh --image <Image or pmOS vmlinuz> \
#       --dtb <sm8550-samsung-dm1q.dtb> --out <dir> \
#       [--initramfs <gzip cpio, e.g. pmOS /boot/initramfs>] \
#       [--stock-dir <dir with vendor_ramdisk00 + bootconfig>] \
#       [--cmdline "<vendor cmdline>"]
#
# --image may be a raw arm64 Image or a pmOS /boot/vmlinuz (EFI zboot
# wrapper; its gzip payload is unwrapped automatically).
# Nothing here flashes anything.
set -euo pipefail

STOCK_DIR="${STOCK_DIR:-$(dirname "$0")/../../_scratch/boot-backup-20260920/unpacked-vendor}"
# v12's vendor cmdline. pmOS userspace may need extra args (see docs/06).
CMDLINE='console=tty0 fbcon=font:TER16x32 loglevel=7 log_buf_len=4M initcall_debug clk_ignore_unused pd_ignore_unused regulator_ignore_unused androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=a600000.dwc3 printk.devkmsg=on loop.max_part=7 bootconfig'
IMAGE="" DTB="" OUT="" INITRAMFS=""

while [ $# -gt 0 ]; do
	case "$1" in
	--image) IMAGE="$2"; shift 2 ;;
	--dtb) DTB="$2"; shift 2 ;;
	--out) OUT="$2"; shift 2 ;;
	--initramfs) INITRAMFS="$2"; shift 2 ;;
	--stock-dir) STOCK_DIR="$2"; shift 2 ;;
	--cmdline) CMDLINE="$2"; shift 2 ;;
	*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done
[ -f "$IMAGE" ] && [ -f "$DTB" ] && [ -n "$OUT" ] || { sed -n '2,30p' "$0"; exit 2; }
[ -f "$STOCK_DIR/vendor_ramdisk00" ] && [ -f "$STOCK_DIR/bootconfig" ] || {
	echo "missing $STOCK_DIR/vendor_ramdisk00 or bootconfig" >&2; exit 1; }

BOOT_SIZE=100663296
VBOOT_SIZE=100663296
INIT_BOOT_SIZE=8388608
DTBO_SIZE=16777216
mkdir -p "$OUT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Unwrap an EFI zboot vmlinuz (magic "zimg" at offset 4) to the raw Image
if [ "$(dd if="$IMAGE" bs=1 skip=4 count=4 2>/dev/null)" = "zimg" ]; then
	python3 - "$IMAGE" "$tmp/Image.raw" <<'PY'
import struct, sys, gzip
d = open(sys.argv[1], "rb").read()
off, size = struct.unpack("<II", d[8:16])
assert d[24:32].rstrip(b"\0") == b"gzip", "unsupported zboot compression"
open(sys.argv[2], "wb").write(gzip.decompress(d[off:off + size]))
PY
	IMAGE="$tmp/Image.raw"
fi

# gzip -n: no timestamp/name, identical inputs give identical output
gzip -9n -c "$IMAGE" > "$tmp/Image.gz"
cat "$tmp/Image.gz" "$DTB" > "$tmp/Image.gz-dtb"

mkbootimg --header_version 4 \
	--kernel "$tmp/Image.gz-dtb" \
	--os_version 16.0.0 --os_patch_level 2026-07 \
	--output "$OUT/boot.img"

mkbootimg --header_version 4 --pagesize 0x1000 \
	--base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
	--dtb_offset 0x1f00000 --tags_offset 0x100 \
	--vendor_ramdisk "$STOCK_DIR/vendor_ramdisk00" \
	--dtb "$DTB" \
	--vendor_cmdline "$CMDLINE" \
	--vendor_bootconfig "$STOCK_DIR/bootconfig" \
	--vendor_boot "$OUT/vendor_boot.img"

head -c 4096 /dev/zero > "$OUT/dtbo.img"

parts="boot vendor_boot dtbo"
if [ -n "$INITRAMFS" ]; then
	gzip -dc "$INITRAMFS" > "$tmp/rd.cpio"
	mkdir "$tmp/rd"
	( cd "$tmp/rd" && cpio -idm --quiet < "$tmp/rd.cpio" )
	repack=0

	# FIX 1: pmOS initramfs is usr-merged (lib -> usr/lib). Samsung's vendor
	# ramdisk, unpacked first, already has /lib as a REAL directory
	# (lib/modules), and the kernel's initramfs unpacker cannot replace a
	# non-empty directory with a symlink -- so the symlink is silently
	# dropped, /lib/ld-musl-* never exists, /bin/busybox cannot exec, and the
	# kernel panics with "No working init found" (found 2026-09-28, see
	# docs/06). Make lib a real directory holding the files, and usr/lib a
	# symlink back to it.
	if [ -L "$tmp/rd/lib" ] && [ "$(readlink "$tmp/rd/lib")" = "usr/lib" ]; then
		rm "$tmp/rd/lib"
		mkdir "$tmp/rd/lib"
		mv "$tmp/rd/usr/lib/"* "$tmp/rd/lib/"
		rmdir "$tmp/rd/usr/lib"
		ln -s ../lib "$tmp/rd/usr/lib"
		echo "initramfs: flattened lib -> usr/lib symlink into a real /lib"
		repack=1
	fi

	# FIX 2: inject a background dmesg -> dtbo flusher into the pmOS stage-1
	# init, so a hang leaves a log readable from recovery (see
	# kernel/initramfs/dtbo-logger.sh).
	LOGGER="$(dirname "$0")/../kernel/initramfs/dtbo-logger.sh"
	if [ -f "$LOGGER" ] && grep -q '^mount_proc_sys_dev$' "$tmp/rd/init"; then
		cp "$LOGGER" "$tmp/rd/dtbo-logger.sh"
		sed -i 's|^mount_proc_sys_dev$|mount_proc_sys_dev\n. /dtbo-logger.sh|' "$tmp/rd/init"
		echo "initramfs: injected dtbo log flusher after mount_proc_sys_dev"
		repack=1
	fi

	# FIX 3: UFS presents 4096-byte logical sectors. pmOS's mount_subpartitions
	# passes deviceinfo_rootfs_image_sector_size to losetup --sector-size; the
	# device package now sets it, this covers an initramfs generated before the
	# device package was rebuilt.
	DI="$tmp/rd/usr/share/deviceinfo/deviceinfo"
	if [ -f "$DI" ] && ! grep -q '^deviceinfo_rootfs_image_sector_size=' "$DI"; then
		echo 'deviceinfo_rootfs_image_sector_size="4096"' >> "$DI"
		echo "initramfs: added deviceinfo_rootfs_image_sector_size=4096"
		repack=1
	fi

	if [ "$repack" = 1 ]; then
		( cd "$tmp/rd" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet ) > "$tmp/rd2.cpio"
		mv "$tmp/rd2.cpio" "$tmp/rd.cpio"
	fi

	lz4 -l -9 -c "$tmp/rd.cpio" > "$tmp/initramfs.lz4"
	mkbootimg --header_version 4 --ramdisk "$tmp/initramfs.lz4" \
		--os_version 16.0.0 --os_patch_level 2026-07 \
		--output "$OUT/init_boot.img"
	avbtool add_hash_footer --image "$OUT/init_boot.img" \
		--partition_size "$INIT_BOOT_SIZE" --partition_name init_boot --algorithm NONE
	parts="$parts init_boot"
fi

avbtool add_hash_footer --image "$OUT/boot.img" --partition_size "$BOOT_SIZE" \
	--partition_name boot --algorithm NONE
avbtool add_hash_footer --image "$OUT/vendor_boot.img" --partition_size "$VBOOT_SIZE" \
	--partition_name vendor_boot --algorithm NONE
avbtool add_hash_footer --image "$OUT/dtbo.img" --partition_size "$DTBO_SIZE" \
	--partition_name dtbo --algorithm NONE

for f in $parts; do
	avbtool verify_image --image "$OUT/$f.img" >/dev/null && echo "$f.img: AVB footer OK"
done
for f in $parts; do sha256sum "$OUT/$f.img"; done
