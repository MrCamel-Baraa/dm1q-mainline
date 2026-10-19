#!/usr/bin/env bash
# PC-side test of scripts/phone-gpu-powerup.sh (docs/06 rule 3). The phone's sysfs, dmesg, DRM node and firmware tree are a
# scratch tree reached through the script's env overrides, and the "kernel" that reacts to the open is a stub (OPEN_CMD) that
# looks at what firmware_class.path points to at the moment of the open and appends dmesg lines accordingly. Run with dash
# (closest to the phone's busybox ash; skipped when not installed) and bash. Checks: refusals (bad mode, not root, GPU not bound,
# wrong/missing firmware, unwritable param) never open the node nor touch the path; the staged set per mode (sqe-gmu has no zap);
# the path is pointed at the staging dir DURING the open and restored afterwards (also on SIGTERM); the run dir is removed;
# only NEW dmesg lines are classified; initramfs-extra change is detected; the built-in opener works on a FIFO; no
# modprobe/insmod/rmmod/mount/umount/reboot/dd is ever called; the pinned hashes in the script match docs/11 and (when present)
# the real downloaded firmware in ../_scratch/dm1q-gpu-fw.
# Usage: bash scripts/test-phone-gpu-powerup.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

OLDPATH_VALUE=/lib/firmware/postmarketos

mk() { # $1 = scratch dir
	local D="$1"
	rm -rf "$D"
	mkdir -p "$D/bin" "$D/sys/drivers-real/adreno" "$D/sys/bus/platform/devices/3d00000.gpu" "$D/sys/module/firmware_class/parameters" \
		"$D/sys/class/devfreq/3d00000.gpu" "$D/proc" "$D/boot" "$D/src/qcom/sm8550" "$D/dri"
	ln -s "$D/sys/drivers-real/adreno" "$D/sys/bus/platform/devices/3d00000.gpu/driver"
	echo "$OLDPATH_VALUE" > "$D/sys/module/firmware_class/parameters/path"
	echo simple_ondemand > "$D/sys/class/devfreq/3d00000.gpu/governor"; echo 0 > "$D/sys/class/devfreq/3d00000.gpu/cur_freq"
	printf ' 332:  0  GICv3 332 Level  gpu-irq\n 337:  0  GICv3 337 Level  gmu\n' > "$D/proc/interrupts"
	printf 'cpio-bytes' > "$D/boot/initramfs-extra"
	printf 'sqe-bytes' > "$D/src/qcom/a740_sqe.fw"; printf 'gmu-bytes' > "$D/src/qcom/gmu_gen70200.bin"; printf 'zap-bytes' > "$D/src/qcom/sm8550/a740_zap.mbn"
	touch "$D/dri/renderD128"
	printf '[ 7.8] [drm] Initialized msm 1.13.0\n[ 7.9] msm_dpu ae01000.display-controller: Direct firmware load for qcom/a740_sqe.fw failed with error -2\n[ 7.9] msm_dpu: failed to load a740_sqe.fw\n' > "$D/dmesg.txt"
	printf '#!/bin/sh\ncat "%s/dmesg.txt"\n' "$D" > "$D/bin/dmesg"
	cat > "$D/bin/fake-open" <<EOF
#!/bin/sh
D="$D"
p=\$(cat "\$D/sys/module/firmware_class/parameters/path")
echo "open node=\$1 hold=\$2 path=\$p" >> "\$D/open.log"
echo "files: \$(find "\$p" -type f 2>/dev/null | sed "s|^\$p/||" | sort | tr '\n' ' ')" >> "\$D/open.log"
sim=\$(cat "\$D/sim" 2>/dev/null)
case "\$sim" in
killme) kill -TERM \$PPID; sleep 1; exit 0 ;;
extra) printf 'changed' > "\$D/boot/initramfs-extra" ;;
esac
if [ "\$sim" = nopath ] || [ ! -f "\$p/qcom/a740_sqe.fw" ]; then
	echo "[ 9.0] msm_dpu ae01000.display-controller: Direct firmware load for qcom/a740_sqe.fw failed with error -2" >> "\$D/dmesg.txt"
	exit 0
fi
echo "[ 9.1] [drm] Loaded GMU firmware v4.1.9" >> "\$D/dmesg.txt"
if [ ! -f "\$p/qcom/sm8550/a740_zap.mbn" ]; then
	echo "[ 9.2] adreno 3d00000.gpu: Direct firmware load for qcom/sm8550/a740_zap.mbn failed with error -2" >> "\$D/dmesg.txt"
	echo "[ 9.2] msm_dpu ae01000.display-controller: [drm:zap_shader_load_mdt [msm]] *ERROR* Unable to load qcom/sm8550/a740_zap.mbn" >> "\$D/dmesg.txt"
	echo "[ 9.2] msm_dpu ae01000.display-controller: gpu hw init failed: -2" >> "\$D/dmesg.txt"
	exit 0
fi
[ "\$sim" = pasfail ] && echo "[ 9.3] adreno 3d00000.gpu: Unable to authorize the image" >> "\$D/dmesg.txt"
[ "\$sim" = gmufail ] && echo "[ 9.3] adreno 3d6a000.gmu: GMU watchdog timeout while waiting for HFI" >> "\$D/dmesg.txt"
exit 0
EOF
	chmod +x "$D/bin/dmesg" "$D/bin/fake-open"
	for t in modprobe insmod rmmod mount umount reboot dd; do
		printf '#!/bin/sh\necho "%s $*" >> "%s/CALLED"\nexit 99\n' "$t" "$D" > "$D/bin/$t"; chmod +x "$D/bin/$t"
	done
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

run() { # $1 = shell, $2 = scratch dir, rest = script args; extra env via $ENVX
	local sh="$1" D="$2"; shift 2
	timeout 30 env PATH="$D/bin:$PATH" SYSFS="$D/sys" DEBUGFS="$D/dbg" PROC="$D/proc" DMESG="$D/bin/dmesg" SRC="$D/src" RUN="$D/run" \
		DEVDRI="$D/dri" HOLD=1 BOOTDIR="$D/boot" OPEN_CMD="${OPEN_CMD_T-$D/bin/fake-open}" ID_U="${ID_U_T-0}" TMPDIR="$D" \
		FW_SQE_SHA="${SQE_T-$(sha "$D/src/qcom/a740_sqe.fw")}" FW_GMU_SHA="$(sha "$D/src/qcom/gmu_gen70200.bin")" FW_ZAP_SHA="$(sha "$D/src/qcom/sm8550/a740_zap.mbn")" \
		"$sh" "$HERE/phone-gpu-powerup.sh" "$@" > "$D/out" 2>&1
}

path_is_old() { [ "$(cat "$1/sys/module/firmware_class/parameters/path")" = "$OLDPATH_VALUE" ]; }

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	echo "== $sh: sqe-gmu"
	D="$W/a-$sh"; mk "$D"
	before=$(cd "$D/src" && find . -type f -exec cksum {} + | sort)
	run "$sh" "$D" sqe-gmu; rc=$?
	O="$D/out"
	[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
	expect "$O" "gpu bound check" "3d00000\\.gpu driver: adreno"
	expect "$O" "sqe pin ok" "ok  qcom/a740_sqe\\.fw 9 bytes sha256 [0-9a-f]{64}"
	expect "$O" "gmu pin ok" "ok  qcom/gmu_gen70200\\.bin 9 bytes"
	reject "$O" "no zap check in sqe-gmu mode" "a740_zap\\.mbn [0-9]+ bytes sha256"
	grep -q "path=$D/run" "$D/open.log" && ok "path pointed at the run dir during the open" || bad "path during open: $(cat "$D/open.log" 2>/dev/null)"
	grep -q "files: qcom/a740_sqe.fw qcom/gmu_gen70200.bin $" "$D/open.log" && ok "only sqe + gmu staged (no zap)" || bad "staged set: $(grep files: "$D/open.log")"
	path_is_old "$D" && ok "firmware_class.path restored" || bad "path now: $(cat "$D/sys/module/firmware_class/parameters/path")"
	[ ! -e "$D/run" ] && ok "run dir removed" || bad "run dir still there"
	expect "$O" "path restored line" "firmware_class\\.path now: '$OLDPATH_VALUE' \\(was '$OLDPATH_VALUE'\\)"
	expect "$O" "new-lines slicing: old boot-time sqe failure not counted" "^sqe_missing=no$"
	expect "$O" "gmu loaded" "^gmu_firmware_loaded=yes$"
	expect "$O" "zap missing" "^zap_missing=yes$"
	expect "$O" "hw init failed (expected here)" "^hw_init_failed=yes$"
	expect "$O" "no pas error" "^pas_error=no$"
	expect "$O" "initramfs-extra unchanged" "^initramfs_extra_unchanged=yes$"
	expect "$O" "path_restored verdict" "^path_restored=yes$"
	expect "$O" "gpu irq printed" "gpu-irq"
	expect "$O" "result line" "^RESULT: stage sqe-gmu as designed"
	[ ! -e "$D/CALLED" ] && ok "no forbidden command called" || bad "forbidden command: $(cat "$D/CALLED")"
	[ "$before" = "$(cd "$D/src" && find . -type f -exec cksum {} + | sort)" ] && ok "staging source untouched" || bad "source changed"

	echo "== $sh: full"
	D="$W/b-$sh"; mk "$D"; run "$sh" "$D" full; rc=$?; O="$D/out"
	[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
	expect "$O" "zap pin ok" "ok  qcom/sm8550/a740_zap\\.mbn 9 bytes sha256 [0-9a-f]{64}"
	grep -q "files: qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/sm8550/a740_zap.mbn $" "$D/open.log" && ok "all three staged" || bad "staged set: $(grep files: "$D/open.log")"
	path_is_old "$D" && ok "path restored" || bad "path not restored"
	expect "$O" "zap present" "^zap_missing=no$"
	expect "$O" "no hw init failure" "^hw_init_failed=no$"
	expect "$O" "full result" "^RESULT: full: no error line seen"

	echo "== $sh: failure simulations"
	D="$W/c-$sh"; mk "$D"; echo pasfail > "$D/sim"; run "$sh" "$D" full; O="$D/out"
	expect "$O" "PAS error detected" "^pas_error=yes$"
	expect "$O" "FAILED result" "^RESULT: FAILED"
	path_is_old "$D" && ok "path restored after PAS failure" || bad "path not restored"
	D="$W/d-$sh"; mk "$D"; echo gmufail > "$D/sim"; run "$sh" "$D" full; O="$D/out"
	expect "$O" "GMU error detected" "^gmu_error=yes$"
	expect "$O" "FAILED result (gmu)" "^RESULT: FAILED"
	D="$W/e-$sh"; mk "$D"; echo nopath > "$D/sim"; run "$sh" "$D" sqe-gmu; O="$D/out"
	expect "$O" "sqe not found detected" "^sqe_missing=yes$"
	expect "$O" "path-not-honoured result" "^RESULT: the SQE file was not found"
	D="$W/f-$sh"; mk "$D"; echo extra > "$D/sim"; run "$sh" "$D" full; O="$D/out"
	expect "$O" "initramfs-extra change detected" "^initramfs_extra_unchanged=no$"
	D="$W/g-$sh"; mk "$D"; echo killme > "$D/sim"; run "$sh" "$D" full; rc=$?; O="$D/out"
	[ "$rc" = 130 ] && ok "SIGTERM during the open: exit 130" || bad "exit $rc after SIGTERM"
	path_is_old "$D" && ok "path restored after SIGTERM" || bad "path NOT restored after SIGTERM"
	[ ! -e "$D/run" ] && ok "run dir removed after SIGTERM" || bad "run dir left after SIGTERM"

	echo "== $sh: refusals (the node must never be opened, the path never touched)"
	D="$W/h-$sh"; mk "$D"; run "$sh" "$D" bogus; rc=$?
	[ "$rc" = 2 ] && ok "bad mode: exit 2" || bad "bad mode exit $rc"
	expect "$D/out" "usage printed" "Usage: phone-gpu-powerup\\.sh"
	D="$W/i-$sh"; mk "$D"; ID_U_T=1 run "$sh" "$D" full; rc=$?
	[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root exit $rc"
	D="$W/j-$sh"; mk "$D"; rm "$D/sys/bus/platform/devices/3d00000.gpu/driver"; run "$sh" "$D" full; rc=$?
	[ "$rc" = 3 ] && ok "gpu not bound: exit 3" || bad "gpu not bound exit $rc"
	expect "$D/out" "reason printed" "REFUSING: 3d00000\\.gpu is not bound to adreno"
	[ ! -e "$D/open.log" ] && path_is_old "$D" && ok "nothing opened, path untouched" || bad "side effects after refusal"
	D="$W/k-$sh"; mk "$D"; SQE_T=0000 run "$sh" "$D" sqe-gmu; rc=$?
	[ "$rc" = 3 ] && ok "wrong sqe hash: exit 3" || bad "wrong hash exit $rc"
	expect "$D/out" "pin mismatch printed" "is not the pinned"
	[ ! -e "$D/open.log" ] && path_is_old "$D" && ok "nothing opened, path untouched (hash)" || bad "side effects after hash refusal"
	D="$W/l-$sh"; mk "$D"; rm "$D/src/qcom/sm8550/a740_zap.mbn"
	timeout 30 env PATH="$D/bin:$PATH" SYSFS="$D/sys" DMESG="$D/bin/dmesg" SRC="$D/src" RUN="$D/run" DEVDRI="$D/dri" HOLD=1 BOOTDIR="$D/boot" OPEN_CMD="$D/bin/fake-open" ID_U=0 TMPDIR="$D" \
		FW_SQE_SHA="$(sha "$D/src/qcom/a740_sqe.fw")" FW_GMU_SHA="$(sha "$D/src/qcom/gmu_gen70200.bin")" FW_ZAP_SHA=abc "$sh" "$HERE/phone-gpu-powerup.sh" full > "$D/out" 2>&1; rc=$?
	[ "$rc" = 3 ] && ok "full without a zap file: exit 3" || bad "missing zap exit $rc"
	expect "$D/out" "missing file printed" "missing .*a740_zap\\.mbn"
	timeout 30 env PATH="$D/bin:$PATH" SYSFS="$D/sys" DMESG="$D/bin/dmesg" SRC="$D/src" RUN="$D/run" DEVDRI="$D/dri" HOLD=1 BOOTDIR="$D/boot" OPEN_CMD="$D/bin/fake-open" ID_U=0 TMPDIR="$D" \
		FW_SQE_SHA="$(sha "$D/src/qcom/a740_sqe.fw")" FW_GMU_SHA="$(sha "$D/src/qcom/gmu_gen70200.bin")" FW_ZAP_SHA=abc "$sh" "$HERE/phone-gpu-powerup.sh" sqe-gmu > "$D/out2" 2>&1; rc=$?
	[ "$rc" = 0 ] && ok "sqe-gmu without a zap file works" || bad "sqe-gmu without zap exit $rc"
	D="$W/m-$sh"; mk "$D"; chmod a-w "$D/sys/module/firmware_class/parameters/path"
	if [ "$(id -u)" != 0 ]; then
		run "$sh" "$D" full; rc=$?
		[ "$rc" = 3 ] && ok "unwritable path param: exit 3" || bad "unwritable param exit $rc"
		[ ! -e "$D/open.log" ] && ok "nothing opened (unwritable)" || bad "opened despite unwritable param"
	else
		echo "  skip  unwritable-param refusal (running as root)"
	fi

	echo "== $sh: built-in opener on a FIFO (O_RDWR open must not block) and the tripwires"
	D="$W/n-$sh"; mk "$D"; rm "$D/dri/renderD128"; mkfifo "$D/dri/renderD128"
	OPEN_CMD_T="" run "$sh" "$D" sqe-gmu; rc=$?
	[ "$rc" = 0 ] && ok "built-in opener: exit 0 (no hang)" || bad "built-in opener exit $rc (124 = blocked)"
	expect "$D/out" "open/hold finished" "open/hold finished, status 0"
	path_is_old "$D" && ok "path restored (built-in opener)" || bad "path not restored (built-in opener)"
	[ ! -e "$D/CALLED" ] && ok "no forbidden command (built-in opener)" || bad "forbidden command called"
done

echo "== pinned hashes: script vs docs/11 vs the real files"
for name in FW_SQE_SHA FW_GMU_SHA FW_ZAP_SHA; do
	pin=$(grep -oE "^${name}=\"\\\$\{${name}:-[0-9a-f]{64}" "$HERE/phone-gpu-powerup.sh" | grep -oE '[0-9a-f]{64}')
	[ -n "$pin" ] || { bad "no default pin for $name in the script"; continue; }
	grep -q "$pin" "$REPO/docs/11-gpu-bringup.md" && ok "$name default pin is recorded in docs/11" || bad "$name pin $pin is not in docs/11"
done
FWD="$REPO/../_scratch/dm1q-gpu-fw"
if [ -d "$FWD" ]; then
	for pair in "FW_SQE_SHA:qcom/a740_sqe.fw" "FW_GMU_SHA:qcom/gmu_gen70200.bin" "FW_ZAP_SHA:qcom/sm8550/a740_zap.mbn"; do
		name="${pair%%:*}"; rel="${pair#*:}"
		pin=$(grep -oE "^${name}=\"\\\$\{${name}:-[0-9a-f]{64}" "$HERE/phone-gpu-powerup.sh" | grep -oE '[0-9a-f]{64}')
		[ "$(sha "$FWD/$rel")" = "$pin" ] && ok "real $rel matches the pin" || bad "real $rel does NOT match the pin"
	done
else
	echo "  skip  real firmware check (no $FWD)"
fi

echo "== static checks"
bash --posix -n "$HERE/phone-gpu-powerup.sh" && ok "bash --posix -n" || bad "bash --posix -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$HERE/phone-gpu-powerup.sh" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
