#!/usr/bin/env bash
# PC-side test of scripts/phone-drm-test.sh (docs/06 rule 3): fake sysfs, a stub drm-fill that only logs its
# arguments. Checks the msm_dpu card is picked (not a simple-framebuffer card), the call sequence and arguments,
# that a failing step stops the run with its exit code, and the "no msm_dpu card" path (exit 4, drm-fill never called).
# Usage: bash scripts/test-phone-drm-test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }

mkdir -p "$W/sys/class/drm/card0/device" "$W/sys/class/drm/card1/device" "$W/sys/drv/simple-framebuffer" "$W/sys/drv/msm_dpu" "$W/dev"
ln -s "$W/sys/drv/simple-framebuffer" "$W/sys/class/drm/card0/device/driver"
ln -s "$W/sys/drv/msm_dpu" "$W/sys/class/drm/card1/device/driver"
cat > "$W/drm-fill" <<EOF
#!/bin/sh
echo "CALL \$*" >> "$W/calls"
[ "\$FAIL_ON" = "\$2 \$3" ] && { echo "ERR forced"; exit 3; }
echo "(stub) \$1 ok"
EOF
chmod +x "$W/drm-fill"
run() { env SYSFS="$W/sys" DEV_DIR="$W/dev" HOLD_BARS=2 HOLD_SOLID=1 "$@" sh "$HERE/phone-drm-test.sh" "$W/drm-fill" > "$W/out" 2>&1; }

: > "$W/calls"
run; rc=$?
[ "$rc" = 0 ] && ok "exit 0 on the happy path" || bad "exit status" "$rc"
grep -q "^card: card1$" "$W/out" && ok "picks the msm_dpu card, not card0" || bad "card choice" "$(head -2 "$W/out")"
want="$(printf 'CALL info %s/dev/card1\nCALL fill %s/dev/card1 bars 2\nCALL fill %s/dev/card1 red 1\nCALL fill %s/dev/card1 green 1\nCALL fill %s/dev/card1 blue 1\nCALL fill %s/dev/card1 white 1' "$W" "$W" "$W" "$W" "$W" "$W")"
[ "$(cat "$W/calls")" = "$want" ] && ok "call sequence and arguments" || bad "calls" "$(cat "$W/calls")"
grep -q "^done$" "$W/out" && ok "ends with done" || bad "done line" "$(tail -2 "$W/out")"

: > "$W/calls"
env SYSFS="$W/sys" DEV_DIR="$W/dev" HOLD_BARS=2 HOLD_SOLID=1 FAIL_ON="$W/dev/card1 green" sh "$HERE/phone-drm-test.sh" "$W/drm-fill" > "$W/out" 2>&1; rc=$?
[ "$rc" = 3 ] && ok "a failing step stops the run with its exit code" || bad "failure exit" "$rc"
[ "$(wc -l < "$W/calls")" = 4 ] && ok "no step after the failing one runs" || bad "calls after failure" "$(cat "$W/calls")"

rm "$W/sys/class/drm/card1/device/driver"; ln -s "$W/sys/drv/simple-framebuffer" "$W/sys/class/drm/card1/device/driver"
: > "$W/calls"
run; rc=$?
[ "$rc" = 4 ] && ok "no msm_dpu card -> exit 4" || bad "exit status (no card)" "$rc"
grep -q "no DRM card is bound to msm_dpu" "$W/out" && ok "no-card message" || bad "message" "$(cat "$W/out")"
[ ! -s "$W/calls" ] && ok "drm-fill not called without a card" || bad "unexpected call" "$(cat "$W/calls")"

command -v shellcheck >/dev/null && { shellcheck -s sh "$HERE/phone-drm-test.sh" >/dev/null && ok "shellcheck -s sh clean" || bad "shellcheck" "$(shellcheck -s sh "$HERE/phone-drm-test.sh" | head -5)"; }

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
