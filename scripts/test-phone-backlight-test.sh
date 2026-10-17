#!/usr/bin/env bash
# PC-side test of scripts/phone-backlight-test.sh (docs/06 rule 3): fake sysfs with a backlight device, a stub drm-fill
# and a stub dmesg. Checks the device choice (the dsi one, not another), the exact sweep order and values for max=2047,
# that the original brightness is restored, that drm-fill is asked for a white fill on the msm_dpu card, the
# "no backlight" path (exit 5), a failing write (exit 6, original restored, no later step), and the no-drm-fill fallback.
# Usage: bash scripts/test-phone-backlight-test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }

mk_bl() { # name type max brightness
	mkdir -p "$W/sys/class/backlight/$1"
	echo "$2" > "$W/sys/class/backlight/$1/type"
	echo "$3" > "$W/sys/class/backlight/$1/max_brightness"
	echo "$4" > "$W/sys/class/backlight/$1/brightness"
	echo "$4" > "$W/sys/class/backlight/$1/actual_brightness"
}
mkdir -p "$W/sys/class/drm/card0/device" "$W/sys/class/drm/card1/device" "$W/sys/drv/simple-framebuffer" "$W/sys/drv/msm_dpu" "$W/dev"
ln -s "$W/sys/drv/simple-framebuffer" "$W/sys/class/drm/card0/device/driver"
ln -s "$W/sys/drv/msm_dpu" "$W/sys/class/drm/card1/device/driver"
mk_bl other-bl raw 255 100
mk_bl ae94000.dsi.0 raw 2047 1500
cat > "$W/drm-fill" <<EOF
#!/bin/sh
echo "CALL \$*" >> "$W/calls"
EOF
chmod +x "$W/drm-fill"
cat > "$W/dmesg" <<EOF
#!/bin/sh
cat "$W/dmesg.txt"
EOF
chmod +x "$W/dmesg"
: > "$W/dmesg.txt"
run() { env SYSFS="$W/sys" DEV_DIR="$W/dev" DMESG="$W/dmesg" HOLD_COARSE=0 HOLD_FINE=0 SETTLE=0 sh "$HERE/phone-backlight-test.sh" "$@" > "$W/out" 2>&1; }

: > "$W/calls"
run "$W/drm-fill"; rc=$?
[ "$rc" = 0 ] && ok "exit 0 on the happy path" || bad "exit status" "$rc"
grep -q "^using: ae94000.dsi.0$" "$W/out" && ok "picks the dsi backlight, not the other one" || bad "device choice" "$(grep -E '^using|^no ' "$W/out")"
grep -q "^max_brightness=2047 original brightness=1500$" "$W/out" && ok "reads max and original" || bad "max/original" "$(grep max_brightness "$W/out")"
want="1 2047
2 1535
3 1023
4 511
5 245
6 122
7 64
8 48
9 32
10 24
11 16
12 12
13 8
14 6
15 4
16 3
17 2
18 1
19 0"
got="$(grep -E '^step [0-9]+: wrote' "$W/out" | sed -E 's/^step ([0-9]+): wrote ([0-9]+) .*/\1 \2/')"
[ "$got" = "$want" ] && ok "sweep order and values (coarse, fine, 0)" || bad "sweep" "$(echo "$got" | tr '\n' ' ')"
grep -q "step 1: wrote 2047 (100%) -> brightness=2047 actual=1500" "$W/out" && ok "read-back printed (brightness re-read; actual_brightness is a static fake here)" || bad "read-back" "$(grep 'step 1:' "$W/out")"
[ "$(cat "$W/sys/class/backlight/ae94000.dsi.0/brightness")" = 1500 ] && ok "original brightness restored" || bad "restore" "$(cat "$W/sys/class/backlight/ae94000.dsi.0/brightness")"
[ "$(cat "$W/sys/class/backlight/other-bl/brightness")" = 100 ] && ok "other backlight untouched" || bad "other backlight" "$(cat "$W/sys/class/backlight/other-bl/brightness")"
grep -q "^CALL fill $W/dev/card1 white [0-9]*$" "$W/calls" && ok "white fill on the msm_dpu card" || bad "drm-fill call" "$(cat "$W/calls")"
grep -q "^(none)$" "$W/out" && ok "no new dmesg lines reported as none" || bad "dmesg section" "$(tail -4 "$W/out")"
grep -q "^done$" "$W/out" && ok "ends with done" || bad "done" "$(tail -2 "$W/out")"

# new panel lines in dmesg during the run are shown (stub appends a line on its second call)
cat > "$W/dmesg" <<EOF
#!/bin/sh
n=\$(cat "$W/dmesg.calls" 2>/dev/null || echo 0); echo \$((n+1)) > "$W/dmesg.calls"
echo "[ 1.0] unrelated old line"
[ "\$n" -ge 1 ] && echo "[ 9.0] panel-samsung-s6e3fac-amb606aw01 ae94000.dsi.0: failed to set brightness: -22"
exit 0
EOF
rm -f "$W/dmesg.calls"
run "$W/drm-fill"
grep -q "failed to set brightness" "$W/out" && ok "new panel dmesg line is shown" || bad "dmesg lines" "$(tail -4 "$W/out")"
grep -q "unrelated old line" "$W/out" && bad "old dmesg line leaked" "$(tail -4 "$W/out")" || ok "old dmesg lines are not repeated"

# a failing write: a read-only brightness file (chmod does not stop root, so skipped there)
mk_bl ae94000.dsi.0 raw 2047 1500
if [ "$(id -u)" != 0 ]; then
	chmod 444 "$W/sys/class/backlight/ae94000.dsi.0/brightness"
	: > "$W/calls"
	run "$W/drm-fill"; rc=$?
	chmod 644 "$W/sys/class/backlight/ae94000.dsi.0/brightness"
	[ "$rc" = 6 ] && ok "failing write -> exit 6" || bad "exit status (write fails)" "$rc"
	grep -q "step 1: write of 2047 FAILED" "$W/out" && ok "failure message" || bad "failure message" "$(grep -E '^step' "$W/out")"
	[ "$(grep -c '^step' "$W/out")" = 1 ] && ok "no step after the failing one" || bad "steps after failure" "$(grep -c '^step' "$W/out")"
else
	echo "skip failing-write test (running as root, chmod does not block writes)"
fi

# no backlight at all
rm -rf "$W/sys/class/backlight"; mkdir -p "$W/sys/class/backlight"
: > "$W/calls"
run "$W/drm-fill"; rc=$?
[ "$rc" = 5 ] && ok "no backlight -> exit 5" || bad "exit status (no backlight)" "$rc"
grep -q "no backlight device" "$W/out" && ok "no-backlight message" || bad "message" "$(cat "$W/out")"
[ ! -s "$W/calls" ] && ok "drm-fill not called without a backlight" || bad "unexpected call" "$(cat "$W/calls")"

# no drm-fill binary: still sweeps, says so
mk_bl ae94000.dsi.0 raw 2047 1500
: > "$W/dmesg.txt"; cat > "$W/dmesg" <<EOF
#!/bin/sh
cat "$W/dmesg.txt"
EOF
run "$W/does-not-exist"; rc=$?
[ "$rc" = 0 ] && ok "no drm-fill: exit 0" || bad "exit status (no drm-fill)" "$rc"
grep -q "sweeping with the console showing" "$W/out" && ok "fallback message" || bad "fallback message" "$(head -8 "$W/out")"
[ "$(grep -c '^step' "$W/out")" = 19 ] && ok "all 19 steps still run" || bad "step count" "$(grep -c '^step' "$W/out")"

command -v shellcheck >/dev/null && { shellcheck -s sh "$HERE/phone-backlight-test.sh" >/dev/null && ok "shellcheck -s sh clean" || bad "shellcheck" "$(shellcheck -s sh "$HERE/phone-backlight-test.sh" | head -8)"; }
if command -v dash >/dev/null; then
	: > "$W/calls"; mk_bl ae94000.dsi.0 raw 2047 1500
	env SYSFS="$W/sys" DEV_DIR="$W/dev" DMESG="$W/dmesg" HOLD_COARSE=0 HOLD_FINE=0 SETTLE=0 dash "$HERE/phone-backlight-test.sh" "$W/drm-fill" > "$W/out" 2>&1 && ok "runs under dash" || bad "dash" "$(tail -3 "$W/out")"
else
	echo "skip dash (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
