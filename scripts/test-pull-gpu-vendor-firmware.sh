#!/usr/bin/env bash
# PC-side test of scripts/pull-gpu-vendor-firmware.sh + scripts/twrp-find-gpu-fw.sh (docs/06 rule 3). `adb` is a stub that runs the "device"
# commands locally against a scratch tree (the device script's env overrides point BLOCKDIR / MNT / ROOTS / PROC_MOUNTS there, and /tmp/ in
# adb arguments is mapped into the scratch tree); mount / umount are stubs that log their arguments. Scenarios:
#   A vendor already mounted: all files pulled by name (a symlink is resolved to its real file), sha256 verified, SHA256SUMS written, no mount, no umount
#   B vendor not mounted: erofs fails, ext4 works, EVERY mount is "-o ro", the partition is unmounted again at the end
#   C nothing found: exit 1 with the layout hint;  D phone not in recovery: exit 2, nothing done
#   E corrupted pull: detected (exit 1, file removed) and the cleanup still runs
#   F SQE/GMU but no zap shader: exit 1;  G comparison with the linux-firmware copies (identical / DIFFERS)
#   plus static checks (shellcheck, bash --posix -n, no write-capable commands in either script)
# Usage: bash scripts/test-pull-gpu-vendor-firmware.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

mkstub() { # $1 = scenario dir
	local S="$1"
	mkdir -p "$S/bin" "$S/tmp" "$S/blk/mapper" "$S/mnt"
	: > "$S/proc-mounts"
	cat > "$S/bin/adb" <<EOF
#!/bin/bash
S="$S"
case "\$1" in
get-state) echo "\${FAKE_STATE:-recovery}" ;;
push) cp "\$2" "\${3/#\/tmp\//\$S/tmp/}" ;;
pull)
	cp "\$2" "\$3" || exit 1
	[ -n "\${FAKE_CORRUPT:-}" ] && printf 'x' >> "\$3"
	exit 0 ;;
shell)
	shift
	if [ "\$*" = "id -u" ]; then echo 0; exit 0; fi
	cmd="\$*"; cmd="\${cmd//\/tmp\//\$S/tmp/}"
	PATH="\$S/bin:\$PATH" BLOCKDIR="\$S/blk" MNT="\$S/mnt" PROC_MOUNTS="\$S/proc-mounts" ROOTS="\${FAKE_ROOTS:-\$S/none}" sh -c "\$cmd" ;;
esac
EOF
	cat > "$S/bin/mount" <<EOF
#!/bin/sh
echo "mount \$*" >> "$S/mount.log"
# mount -t <fs> -o ro <dev> <mnt>
fs=\$2; mnt=\$6
[ "\$fs" = erofs ] && exit 1
mkdir -p "\$mnt/firmware"; cp "$S"/fixture/* "\$mnt/firmware/" 2>/dev/null
echo "\$5 \$mnt \$fs ro 0 0" >> "$S/proc-mounts"
exit 0
EOF
	cat > "$S/bin/umount" <<EOF
#!/bin/sh
echo "umount \$*" >> "$S/mount.log"
grep -v " \$1 " "$S/proc-mounts" > "$S/proc-mounts.new"; mv "$S/proc-mounts.new" "$S/proc-mounts"
rm -rf "\$1/firmware"
exit 0
EOF
	chmod +x "$S/bin/adb" "$S/bin/mount" "$S/bin/umount"
}
mkfixture() { # $1 = directory to fill with the firmware set; $2 = "nozap" to leave the zap out
	mkdir -p "$1"
	printf 'sqe-vendor' > "$1/a740_sqe.fw"; printf 'gmu-vendor-bytes' > "$1/gmu_gen70200.bin"; printf 'unrelated' > "$1/other.bin"
	if [ "${2:-}" != nozap ]; then
		printf 'mdt' > "$1/a740_zap.mdt"; printf 'b00' > "$1/a740_zap.b00"; printf 'b01' > "$1/a740_zap.b01"; printf 'b02-bytes' > "$1/a740_zap.b02"
	fi
}
runpull() { # $1 = scenario dir, rest: extra env assignments are taken from the caller's environment
	local S="$1"
	( cd "$S" && PATH="$S/bin:$PATH" timeout 60 bash "$HERE/pull-gpu-vendor-firmware.sh" "$S/out" > "$S/log" 2>&1 )
}

echo "== A: vendor already mounted, a symlink in firmware/"
S="$W/A"; mkstub "$S"; mkdir -p "$S/vendor/firmware" "$S/vendor/firmware_mnt/image"
mkfixture "$S/vendor/firmware"; mv "$S/vendor/firmware/a740_sqe.fw" "$S/vendor/firmware_mnt/image/a740_sqe.fw"; ln -s ../firmware_mnt/image/a740_sqe.fw "$S/vendor/firmware/a740_sqe.fw"
FAKE_ROOTS="$S/vendor" GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$S/log"; }
for f in a740_zap.mdt a740_zap.b00 a740_zap.b01 a740_zap.b02 a740_sqe.fw gmu_gen70200.bin; do
	[ -f "$S/out/$f" ] && ok "pulled $f" || bad "missing $f"
done
[ ! -e "$S/out/other.bin" ] && ok "unrelated file not pulled" || bad "other.bin was pulled"
[ "$(cat "$S/out/a740_sqe.fw")" = sqe-vendor ] && ok "symlink resolved to the real file's bytes" || bad "symlink content wrong"
expect "$S/log" "FOUND lines printed" "^FOUND .* a740_zap\\.mdt$"
expect "$S/log" "verified lines" "^ok  a740_zap\\.b02  9 bytes  sha256 [0-9a-f]{64}"
expect "$S/log" "final message" "zap shader pulled and verified"
[ -f "$S/out/SHA256SUMS" ] && (cd "$S/out" && sha256sum -c SHA256SUMS >/dev/null 2>&1) && ok "SHA256SUMS written and valid" || bad "SHA256SUMS missing or invalid"
reject "$S/out/SHA256SUMS" "SHA256SUMS lists only firmware" "scan\\.txt"
[ ! -e "$S/mount.log" ] && ok "no mount / umount call when already mounted" || bad "mount log: $(cat "$S/mount.log")"
expect "$S/log" "umount mode says nothing to do" "is not mounted: nothing to do"

echo "== B: vendor not mounted (erofs fails, ext4 works)"
S="$W/B"; mkstub "$S"; mkfixture "$S/fixture"; touch "$S/blk/mapper/vendor_a"
GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$S/log"; }
[ "$(wc -l < "$S/mount.log")" = 3 ] && ok "erofs try, ext4 try, umount" || bad "mount log: $(cat "$S/mount.log")"
reject "$S/mount.log" "no read-write mount" " rw|remount"
[ "$(grep -c '^mount ' "$S/mount.log")" = 2 ] && [ "$(grep -c -- '-o ro' "$S/mount.log")" = 2 ] && ok "every mount is -o ro" || bad "mounts not all -o ro"
expect "$S/mount.log" "unmounted at the end" "^umount $S/mnt$"
reject "$S/proc-mounts" "mount table clean again" "$S/mnt"
expect "$S/log" "mounted line" "mounted .*vendor_a as ext4 at .* \\(read-only\\)"
[ -f "$S/out/a740_zap.b00" ] && ok "files pulled from the mounted partition" || bad "files not pulled"

echo "== C: nothing found"
S="$W/C"; mkstub "$S"
GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 1 ] && ok "exit 1" || bad "exit $rc"
expect "$S/log" "NONE printed" "^NONE$"
expect "$S/log" "layout hint" "no Adreno 740 firmware found: read .*scan\\.txt"

echo "== D: phone not in recovery"
S="$W/D"; mkstub "$S"
FAKE_STATE=device GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 2 ] && ok "exit 2" || bad "exit $rc"
expect "$S/log" "refusal message" "phone is not in recovery"
[ ! -d "$S/out" ] && ok "nothing created" || bad "out dir created"

echo "== E: corrupted pull is detected, cleanup still runs"
S="$W/E"; mkstub "$S"; mkfixture "$S/fixture"; touch "$S/blk/mapper/vendor"
FAKE_CORRUPT=1 GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 1 ] && ok "exit 1" || bad "exit $rc"
expect "$S/log" "mismatch reported" "^MISMATCH: "
[ ! -e "$S/out/a740_zap.mdt" ] && ok "corrupt file removed" || bad "corrupt file kept"
expect "$S/mount.log" "partition still unmounted at the end" "^umount $S/mnt$"

echo "== F: no zap shader on the phone"
S="$W/F"; mkstub "$S"; mkdir -p "$S/vendor/firmware"; mkfixture "$S/vendor/firmware" nozap
FAKE_ROOTS="$S/vendor" GPU_FW_REF="$S/noref" runpull "$S"; rc=$?
[ "$rc" = 1 ] && ok "exit 1" || bad "exit $rc"
expect "$S/log" "no-zap message" "NO zap shader"
[ -f "$S/out/gmu_gen70200.bin" ] && ok "SQE/GMU still pulled" || bad "SQE/GMU not pulled"

echo "== G: comparison with the linux-firmware copies"
S="$W/G"; mkstub "$S"; mkdir -p "$S/vendor/firmware" "$S/ref/qcom"; mkfixture "$S/vendor/firmware"
cp "$S/vendor/firmware/a740_sqe.fw" "$S/ref/qcom/a740_sqe.fw"; printf 'different' > "$S/ref/qcom/gmu_gen70200.bin"
FAKE_ROOTS="$S/vendor" GPU_FW_REF="$S/ref" runpull "$S"; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$S/log" "sqe identical" "a740_sqe\\.fw: identical to the linux-firmware copy"
expect "$S/log" "gmu differs" "gmu_gen70200\\.bin: DIFFERS from the linux-firmware copy"

echo "== static checks"
for f in pull-gpu-vendor-firmware.sh twrp-find-gpu-fw.sh; do
	reject "$HERE/$f" "$f: no write-capable commands" "(^|[^a-z])(dd |mkfs|mke2fs|fastboot|remount|flash_image)|-o rw|of=/dev"
done
bash --posix -n "$HERE/twrp-find-gpu-fw.sh" && ok "device script: bash --posix -n" || bad "device script syntax"
bash -n "$HERE/pull-gpu-vendor-firmware.sh" && ok "pull script: bash -n" || bad "pull script syntax"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$HERE/twrp-find-gpu-fw.sh" && ok "shellcheck -s sh (device script)" || bad "shellcheck device script"
	shellcheck -S warning "$HERE/pull-gpu-vendor-firmware.sh" && ok "shellcheck (pull script)" || bad "shellcheck pull script"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
