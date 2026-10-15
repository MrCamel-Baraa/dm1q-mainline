#!/bin/sh
# Phone-side display pixel test (docs/09). POSIX sh, run as root (collect-phone-state.sh --drm-test does that).
# Finds the DRM card bound to msm_dpu, lists its connectors/modes (read-only), then shows test patterns on the
# panel with drm-fill (a modeset: it bypasses fbcon, the console comes back when each run ends). WATCH THE PHONE:
#   bars (12 s): 8 vertical bars white yellow cyan green magenta red blue black, a black-to-white gradient strip
#                along the bottom tenth, a 1-pixel white frame around the edge
#   red green blue white (5 s each): solid colours
# usage: phone-drm-test.sh [DRMFILL_BINARY]       default /tmp/drm-fill
# Env overrides (the PC-side test uses them): SYSFS DEV_DIR HOLD_BARS HOLD_SOLID
# Exit: 0 ok, 4 no msm_dpu card, otherwise drm-fill's code of the first failing step.
SYSFS="${SYSFS:-/sys}"
DEV_DIR="${DEV_DIR:-/dev/dri}"
BIN="${1:-/tmp/drm-fill}"
HOLD_BARS="${HOLD_BARS:-12}"
HOLD_SOLID="${HOLD_SOLID:-5}"

card=""
for c in "$SYSFS"/class/drm/card[0-9]; do
	[ -e "$c/device/driver" ] || continue
	if [ "$(basename "$(readlink "$c/device/driver")")" = msm_dpu ]; then card="$(basename "$c")"; fi
done
if [ -z "$card" ]; then
	echo "no DRM card is bound to msm_dpu (is msm loaded? see display.txt)"
	exit 4
fi
echo "card: $card"
chmod +x "$BIN" 2>/dev/null
echo "== info"
"$BIN" info "$DEV_DIR/$card" || exit $?
echo "== bars (watch the panel)"
"$BIN" fill "$DEV_DIR/$card" bars "$HOLD_BARS" || exit $?
for p in red green blue white; do
	echo "== $p"
	"$BIN" fill "$DEV_DIR/$card" "$p" "$HOLD_SOLID" || exit $?
done
echo "done"
