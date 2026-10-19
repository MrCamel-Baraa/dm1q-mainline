#!/bin/sh
# Phone-side, ON-DEMAND Adreno 740 power-up test (docs/11-gpu-bringup.md section 7, step S3). POSIX sh, run as root
# (collect-phone-state.sh --gpu-powerup=MODE does that and pushes the firmware). It CHANGES the running system's GPU
# state: it powers the GPU up once, which boots the GMU and, in "full" mode, makes the secure world authenticate the zap
# shader (the step that could reset the phone). Nothing is installed: the firmware never touches /lib/firmware (an apk
# trigger dir, docs/06 rule 3) and the default search path stays as it was, so a reset costs one reboot, not a boot loop.
#
# Usage: phone-gpu-powerup.sh sqe-gmu|full
#   sqe-gmu  stage only a740_sqe.fw + gmu_gen70200.bin: the GMU boots, then hw_init stops cleanly at the missing zap
#            file (expected "Direct firmware load ... a740_zap.mbn failed with error -2"); proves rails/clocks/GMU/SMMU
#            without the secure-world authentication.
#   full     stage the zap shader too: PAS authenticates it and hw_init runs; a wrong signature only logs an error.
# How: the powering up happens in msm_open() -> load_gpu() on the first open of a DRM node of the unified device (the
# in-kernel fbdev client's open at boot already tried, and failed on the missing SQE). So the script (1) checks that
# 3d00000.gpu is bound to adreno and that the staged files are the pinned linux-firmware ones, (2) copies the files for
# this mode to $RUN, (3) saves firmware_class.path (pmOS sets it to /lib/firmware/postmarketos, NOT empty) and points it
# at $RUN, (4) opens $NODE read/write for $HOLD seconds, (5) restores the saved path (also on INT/TERM/HUP/exit),
# (6) prints the new kernel log lines and a key=value verdict. It never writes anywhere else and removes $RUN at the end.
# Env (the PC-side test uses them): SYSFS DEBUGFS PROC DMESG SRC RUN DEVDRI NODE HOLD BOOTDIR SHA OPEN_CMD ID_U
#   FW_SQE_SHA FW_GMU_SHA FW_ZAP_SHA (default: the linux-firmware files of docs/11 section 9.2; override only for a
#   vendor-signed set) READ_GPU_DEBUGFS=1 (also print debugfs dri/*/gpu: it resumes the GPU once more)
SYSFS="${SYSFS:-/sys}"
DEBUGFS="${DEBUGFS:-/sys/kernel/debug}"
PROC="${PROC:-/proc}"
DMESG="${DMESG:-dmesg}"
SRC="${SRC:-/root/dm1q-gpu-fw}"
RUN="${RUN:-/root/dm1q-gpu-fw-run}"
DEVDRI="${DEVDRI:-/dev/dri}"
NODE="${NODE:-$DEVDRI/renderD128}"
HOLD="${HOLD:-5}"
BOOTDIR="${BOOTDIR:-/boot}"
SHA="${SHA:-sha256sum}"
OPEN_CMD="${OPEN_CMD:-}"
FW_SQE_SHA="${FW_SQE_SHA:-96fee336424b139100fc60b5b45a907360e4b3936d7e1d00406b9bd80ca48473}"
FW_GMU_SHA="${FW_GMU_SHA:-1a2a419c39046d3141fc5fed5aa7f971de2db40cc7a1d89693c3e26fad64dd98}"
FW_ZAP_SHA="${FW_ZAP_SHA:-386bbdc25ae94a9398e33e7580eecfdcef6c472682a1e3123e1374bcffe7cde3}"
READ_GPU_DEBUGFS="${READ_GPU_DEBUGFS:-0}"
TMPD="${TMPDIR:-/tmp}"

MODE="${1:-}"
case "$MODE" in sqe-gmu|full) ;; *) sed -n '2,16p' "$0"; exit 2 ;; esac
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

PARAM="$SYSFS/module/firmware_class/parameters/path"
GPUDEV="$SYSFS/bus/platform/devices/3d00000.gpu"
say() { echo; echo "== $*"; }
refuse() { echo "REFUSING: $*"; exit 3; }
yn() { if grep -qiE "$1" "$NEWLOG" 2>/dev/null; then echo yes; else echo no; fi; }

say "0. preflight (mode $MODE)"
drv=none
[ -L "$GPUDEV/driver" ] && drv=$(basename "$(readlink "$GPUDEV/driver")")
echo "3d00000.gpu driver: $drv"
[ "$drv" = adreno ] || refuse "3d00000.gpu is not bound to adreno (flash the &gpu image set first, docs/11 step S2)"
[ -r "$PARAM" ] && [ -w "$PARAM" ] || refuse "$PARAM is not readable and writable"
[ -e "$NODE" ] || refuse "no $NODE"
bad=0
checkfile() { # relpath expected_sha
	f="$SRC/$1"
	if [ ! -f "$f" ]; then echo "missing $f"; bad=1; return 0; fi
	got=$("$SHA" "$f" | cut -d' ' -f1)
	if [ "$got" != "$2" ]; then echo "$1: sha256 $got is not the pinned $2"; bad=1; return 0; fi
	echo "ok  $1 $(wc -c < "$f") bytes sha256 $got"
}
checkfile qcom/a740_sqe.fw "$FW_SQE_SHA"
checkfile qcom/gmu_gen70200.bin "$FW_GMU_SHA"
if [ "$MODE" = full ]; then checkfile qcom/sm8550/a740_zap.mbn "$FW_ZAP_SHA"; fi
[ "$bad" = 0 ] || refuse "firmware files missing or not the pinned linux-firmware ones under $SRC"

OLD=$(cat "$PARAM")
EXTRA_BEFORE=$("$SHA" "$BOOTDIR/initramfs-extra" 2>/dev/null | cut -d' ' -f1)
N0=$("$DMESG" | wc -l)
echo "firmware_class.path before: '$OLD'"
echo "initramfs-extra sha256 before: ${EXTRA_BEFORE:-none}"
echo "dmesg lines before: $N0"

RESTORED=""
restore() {
	[ -z "$RESTORED" ] || return 0
	RESTORED=1
	echo "$OLD" > "$PARAM" 2>/dev/null
	rm -rf "$RUN"
}
trap restore EXIT
trap 'restore; exit 130' INT TERM HUP

say "1. stage the firmware for this mode under $RUN"
rm -rf "$RUN"
mkdir -p "$RUN/qcom/sm8550" || refuse "cannot create $RUN"
cp "$SRC/qcom/a740_sqe.fw" "$SRC/qcom/gmu_gen70200.bin" "$RUN/qcom/" || refuse "copy failed"
if [ "$MODE" = full ]; then cp "$SRC/qcom/sm8550/a740_zap.mbn" "$RUN/qcom/sm8550/" || refuse "copy failed"; fi
sync
find "$RUN" -type f | sort | sed 's/^/  /'

say "2. point firmware_class.path at it and open $NODE"
echo "$RUN" > "$PARAM"
now=$(cat "$PARAM")
[ "$now" = "$RUN" ] || { restore; refuse "firmware_class.path did not take the new value (reads '$now')"; }
echo ">>> opening $NODE for $HOLD s NOW: the GPU powers up (mode $MODE)"
sync
if [ -n "$OPEN_CMD" ]; then
	"$OPEN_CMD" "$NODE" "$HOLD"
	rc=$?
else
	( exec 3<>"$NODE" && sleep "$HOLD" )
	rc=$?
fi
echo "open/hold finished, status $rc"

say "3. restore firmware_class.path"
restore
echo "firmware_class.path now: '$(cat "$PARAM")' (was '$OLD')"
rm -rf "$RUN"

say "4. new kernel log lines"
NEWLOG="$TMPD/gpu-powerup.$$"
"$DMESG" | tail -n +"$((N0 + 1))" > "$NEWLOG"
echo "new dmesg lines: $(wc -l < "$NEWLOG")"
cut -c1-300 "$NEWLOG" | head -n 300

say "5. interrupts, devfreq"
grep -E 'gpu-irq|gmu' "$PROC/interrupts" 2>/dev/null || echo "(no gpu / gmu interrupt lines)"
DF="$SYSFS/class/devfreq/3d00000.gpu"
if [ -e "$DF" ]; then
	echo "devfreq 3d00000.gpu: governor=$(cat "$DF/governor" 2>/dev/null) cur=$(cat "$DF/cur_freq" 2>/dev/null)"
fi
if [ "$READ_GPU_DEBUGFS" = 1 ]; then
	for g in "$DEBUGFS"/dri/*/gpu; do
		[ -f "$g" ] || continue
		echo "--- $g"
		head -n 40 "$g"
	done
fi

say "6. verdict"
EXTRA_AFTER=$("$SHA" "$BOOTDIR/initramfs-extra" 2>/dev/null | cut -d' ' -f1)
echo "mode=$MODE"
echo "open_status=$rc"
echo "path_restored=$([ "$(cat "$PARAM")" = "$OLD" ] && echo yes || echo no)"
echo "initramfs_extra_unchanged=$([ "$EXTRA_BEFORE" = "$EXTRA_AFTER" ] && echo yes || echo no)"
sqe_missing=$(yn 'Direct firmware load for .*a740_sqe\.fw failed|failed to load a740_sqe')
gmu_loaded=$(yn 'Loaded GMU firmware')
zap_missing=$(yn 'Direct firmware load for .*a740_zap.* failed|Unable to load .*a740_zap')
pas_error=$(yn 'Unable to authorize|PAS is not available|auth_and_reset.* (fail|error)|failed to authenticate')
hwinit_failed=$(yn 'gpu hw init failed')
gmu_error=$(yn 'gmu.*(timeout|timed out|fail|error)|hfi.*(timeout|fail|error)|CM3 fault')
hang=$(yn 'hangcheck|gpu hang|lockup')
faults=$(grep -c 'Unhandled context fault' "$NEWLOG")
echo "sqe_missing=$sqe_missing"
echo "gmu_firmware_loaded=$gmu_loaded"
echo "zap_missing=$zap_missing"
echo "pas_error=$pas_error"
echo "hw_init_failed=$hwinit_failed"
echo "gmu_error=$gmu_error"
echo "hang=$hang"
echo "smmu_faults=$faults"
if [ "$sqe_missing" = yes ]; then
	echo "RESULT: the SQE file was not found: firmware_class.path was not honoured (or the file name differs)"
elif [ "$gmu_error" = yes ] || [ "$pas_error" = yes ] || [ "$hang" = yes ] || [ "$faults" != 0 ]; then
	echo "RESULT: FAILED, read the new kernel log lines above"
elif [ "$MODE" = sqe-gmu ] && [ "$zap_missing" = yes ] && [ "$gmu_loaded" = yes ]; then
	echo "RESULT: stage sqe-gmu as designed: the GMU firmware loaded, hw_init stopped at the missing zap shader"
elif [ "$MODE" = full ] && [ "$hwinit_failed" = no ] && [ "$zap_missing" = no ]; then
	echo "RESULT: full: no error line seen (not proof of a working GPU: check the devfreq/interrupt lines and run the probe)"
else
	echo "RESULT: unclassified, read the new kernel log lines above"
fi
rm -f "$NEWLOG"
echo
echo "done"
