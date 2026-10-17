#!/bin/sh
# Phone-side backlight/brightness sweep (docs/09 section 17). POSIX sh, run as root
# (collect-phone-state.sh --backlight does that; by hand: sudo sh phone-backlight-test.sh /tmp/drm-fill).
# The panel driver registers a RAW backlight (max 0x07ff = 2047, DCS 0x51, no PWM). Those numbers are assumptions
# carried over from gts9uwifi; this script checks them by eye. It
#   1. lists /sys/class/backlight/* (type, max_brightness, brightness, actual_brightness; read-only),
#   2. puts a solid WHITE screen on the panel with drm-fill (so brightness steps are easy to see; if drm-fill or the
#      msm card is missing it carries on with the console showing),
#   3. writes a sweep of values to the panel's `brightness`: coarse (100, 75, 50, 25, 12, 6 %), then a fine run of
#      raw values at the dark end (64 .. 1), then 0, then back to the original value,
#   4. prints what it wrote and what sysfs read back, and any panel/dsi/backlight dmesg lines that appeared.
# WATCH THE PHONE, note for each "step N" line: did the brightness change, is it monotonic, where is the lowest value
# that is still visibly lit, is there flicker/flash/colour shift at the low end, does 0 turn the panel black.
# The original brightness is restored on exit, also on Ctrl-C / error.
# usage: phone-backlight-test.sh [DRMFILL_BINARY]       default /tmp/drm-fill
# Env overrides (the PC-side test uses them): SYSFS DEV_DIR DMESG HOLD_COARSE HOLD_FINE SETTLE
# Exit: 0 ok, 5 no backlight device, 6 a write to brightness failed (original value still restored).
SYSFS="${SYSFS:-/sys}"
DEV_DIR="${DEV_DIR:-/dev/dri}"
DMESG="${DMESG:-dmesg}"
BIN="${1:-/tmp/drm-fill}"
HOLD_COARSE="${HOLD_COARSE:-4}"
HOLD_FINE="${HOLD_FINE:-2}"

echo "== backlight devices"
bl=""
for d in "$SYSFS"/class/backlight/*; do
	[ -e "$d/brightness" ] || continue
	echo "$(basename "$d"): type=$(cat "$d/type" 2>/dev/null) max=$(cat "$d/max_brightness" 2>/dev/null) brightness=$(cat "$d/brightness" 2>/dev/null) actual=$(cat "$d/actual_brightness" 2>/dev/null)"
	case "$(basename "$d")" in
	*dsi*) bl="$d" ;;
	*) [ -n "$bl" ] || bl="$d" ;;
	esac
done
if [ -z "$bl" ]; then
	echo "no backlight device under $SYSFS/class/backlight (is panel-samsung-s6e3fac-amb606aw01 loaded and bound? see display.txt)"
	exit 5
fi
echo "using: $(basename "$bl")"
max="$(cat "$bl/max_brightness")"
orig="$(cat "$bl/brightness")"
echo "max_brightness=$max original brightness=$orig"

# solid white behind the sweep
card=""
for c in "$SYSFS"/class/drm/card[0-9]; do
	[ -e "$c/device/driver" ] || continue
	if [ "$(basename "$(readlink "$c/device/driver")")" = msm_dpu ]; then card="$(basename "$c")"; fi
done
fillpid=""
total=$((6 * HOLD_COARSE + 12 * HOLD_FINE + HOLD_COARSE + 6))
if [ -n "$card" ] && [ -f "$BIN" ]; then
	chmod +x "$BIN" 2>/dev/null
	echo "white screen on $card for ~${total}s (drm-fill)"
	"$BIN" fill "$DEV_DIR/$card" white "$total" >/dev/null 2>&1 &
	fillpid=$!
	sleep "${SETTLE:-2}"
else
	echo "no msm_dpu card or no drm-fill binary: sweeping with the console showing (harder to judge)"
fi

restore() {
	echo "$orig" > "$bl/brightness" 2>/dev/null
	echo "restored brightness=$(cat "$bl/brightness" 2>/dev/null)"
}
trap 'restore; [ -n "$fillpid" ] && kill "$fillpid" 2>/dev/null; exit 130' INT TERM

before="$($DMESG 2>/dev/null | wc -l)"
n=0
rc=0
set_bl() {
	# $1 = value, $2 = hold seconds, $3 = label
	n=$((n + 1))
	if ! echo "$1" > "$bl/brightness"; then
		echo "step $n: write of $1 FAILED"
		rc=6
		return 1
	fi
	sleep "$2"
	echo "step $n: wrote $1 ($3) -> brightness=$(cat "$bl/brightness") actual=$(cat "$bl/actual_brightness" 2>/dev/null)"
	return 0
}

echo "== coarse sweep (${HOLD_COARSE}s each)"
for pct in 100 75 50 25 12 6; do
	set_bl $((max * pct / 100)) "$HOLD_COARSE" "${pct}%" || break
done
if [ "$rc" = 0 ]; then
	echo "== fine run at the dark end (${HOLD_FINE}s each)"
	for v in 64 48 32 24 16 12 8 6 4 3 2 1; do
		set_bl "$v" "$HOLD_FINE" "raw $v" || break
	done
fi
[ "$rc" = 0 ] && { set_bl 0 "$HOLD_COARSE" "off?" || true; }

echo "== back to the original"
restore
trap - INT TERM
# drm-fill ends by itself a few seconds after the sweep and hands the console back
[ -n "$fillpid" ] && wait "$fillpid" 2>/dev/null

echo "== new kernel lines about the panel (none is good)"
$DMESG 2>/dev/null | tail -n +$((before + 1)) | grep -i -E "s6e3fac|ae94000|dsi|panel|backlight" || echo "(none)"
echo "done"
exit "$rc"
