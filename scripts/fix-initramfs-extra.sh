#!/usr/bin/env bash
# Strip the top-level bin/lib/sbin usr-merge symlinks from a pmOS
# initramfs-extra so it can extract onto a stage-1 ramdisk that has already
# turned lib into a REAL directory (see make-boot-images.sh's FIX 1, and
# docs/06-pmos-userspace-plan.md 2026-09-28: without this, stage-2
# extraction fails with "cpio: can't remove old file lib: Is a directory",
# and every binary that only exists in initramfs-extra -- udevd, e2fsck,
# parted, modprobe, etc -- silently never gets installed).
# The other usr/* paths inside initramfs-extra are unaffected: only the bare
# top-level bin/lib/sbin symlink entries are removed, since the real
# directories they'd point to already exist by the time this extracts.
#
# Usage: scripts/fix-initramfs-extra.sh <in initramfs-extra (gzip cpio)> <out>
set -euo pipefail
IN="${1:?in}"; OUT="${2:?out}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/t"
gzip -dc "$IN" > "$tmp/extra.cpio"
( cd "$tmp/t" && cpio -idm --quiet < "$tmp/extra.cpio" )
for l in bin lib sbin; do
	[ -L "$tmp/t/$l" ] && rm "$tmp/t/$l"
done
( cd "$tmp/t" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet ) | gzip -9n > "$OUT"
