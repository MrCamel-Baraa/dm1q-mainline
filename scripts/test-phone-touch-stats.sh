#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-stats.sh (docs/06 rule 3), on a fake debugfs directory: printing, SET (values written, in order, bad names and
# values refused without writing), RESET, the missing-knob abort, the write-error path, the per-1000 maths, and the static checks.
# Usage: bash scripts/test-phone-touch-stats.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-stats.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (found: $3)"; else ok "$2"; fi; }

mk() {
	local D="$1/kernel/debug/spi0.0"
	mkdir -p "$D"
	printf 'irqs 5000\npolls 40\nevents 4900\npress 400\nmove 4100\nrelease 400\noverflow 2\nerrors 0\nstalls 3\nstall_after_none 0\nstall_after_press 1\nstall_after_move 1\nstall_after_release 1\n' > "$D/stats"
	echo 0 > "$D/poll_ms"; echo 0 > "$D/read_delay_us"; echo 10000000 > "$D/speed_hz"; : > "$D/stats_reset"
}
run() { local R="$1"; shift; env ID_U=0 DEBUGFS="$R/kernel/debug" "$@" sh "$SCRIPT" > "$R.out" 2>&1; }

echo "== print only"
mk "$W/a"; run "$W/a"; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$W/a.out" "knobs line" "^knobs: poll_ms=0 read_delay_us=0 speed_hz=10000000"
expect "$W/a.out" "counters are shown" "^  stalls 3"
expect "$W/a.out" "per 1000 touch-downs" "per 1000 touch-downs \(400 touch-downs\): stalls 7.50, overflow 5.00"
[ "$(cat "$W/a/kernel/debug/spi0.0/poll_ms")" = 0 ] && ok "nothing was written" || bad "knob changed without SET"

echo "== SET, in order"
mk "$W/b"; run "$W/b" SET=poll_ms=150,read_delay_us=300,speed_hz=5000000; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
[ "$(cat "$W/b/kernel/debug/spi0.0/poll_ms")" = 150 ] && ok "poll_ms written" || bad "poll_ms"
[ "$(cat "$W/b/kernel/debug/spi0.0/read_delay_us")" = 300 ] && ok "read_delay_us written" || bad "read_delay_us"
[ "$(cat "$W/b/kernel/debug/spi0.0/speed_hz")" = 5000000 ] && ok "speed_hz written" || bad "speed_hz"
expect "$W/b.out" "set lines" "^set poll_ms=150"
expect "$W/b.out" "knobs line shows the new values" "^knobs: poll_ms=150 read_delay_us=300 speed_hz=5000000"

echo "== bad names and values are refused, the good one still goes through"
mk "$W/c"; run "$W/c" SET=bogus=1,poll_ms=x,read_delay_us=-5,speed_hz=2000000; rc=$?
[ "$rc" = 2 ] && ok "exit 2" || bad "exit $rc"
expect "$W/c.out" "unknown knob named" "unknown knob 'bogus'"
expect "$W/c.out" "bad number named" "poll_ms needs a number \(got 'x'\)"
expect "$W/c.out" "negative refused" "read_delay_us needs a number \(got '-5'\)"
[ "$(cat "$W/c/kernel/debug/spi0.0/poll_ms")" = 0 ] && [ "$(cat "$W/c/kernel/debug/spi0.0/read_delay_us")" = 0 ] && ok "refused values were not written" || bad "a refused value was written"
[ "$(cat "$W/c/kernel/debug/spi0.0/speed_hz")" = 2000000 ] && ok "the valid knob was written" || bad "valid knob not written"

echo "== RESET"
mk "$W/d"; run "$W/d" RESET=1; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$W/d.out" "counters printed before the reset" "^  press 400"
expect "$W/d.out" "reset reported" "^counters reset"
[ -s "$W/d/kernel/debug/spi0.0/stats_reset" ] && ok "stats_reset was written" || bad "stats_reset untouched"

echo "== no touch-downs yet"
mk "$W/e"; printf 'irqs 0\npolls 0\nevents 0\npress 0\nmove 0\nrelease 0\noverflow 0\nerrors 0\nstalls 0\n' > "$W/e/kernel/debug/spi0.0/stats"
run "$W/e"
expect "$W/e.out" "no division by zero" "^no touch-downs counted yet"

echo "== the kernel without the instruments"
mk "$W/f"; rm -f "$W/f/kernel/debug/spi0.0/stats"
run "$W/f"; rc=$?
[ "$rc" = 3 ] && ok "missing stats: exit 3" || bad "missing stats: exit $rc"
expect "$W/f.out" "ABORT names the package" "ABORT: .*stats is missing .*r11"

echo "== a write error is reported"
mk "$W/g"; rm -f "$W/g/kernel/debug/spi0.0/poll_ms"; mkdir "$W/g/kernel/debug/spi0.0/poll_ms"
run "$W/g" SET=poll_ms=100; rc=$?
[ "$rc" = 4 ] && ok "exit 4" || bad "exit $rc"
expect "$W/g.out" "the error is shown" "^ERROR: writing 100 to poll_ms failed"

echo "== not root"
env ID_U=1 DEBUGFS="$W/a/kernel/debug" sh "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"

echo "== static checks"
sh -n "$SCRIPT" && ok "sh -n" || bad "sh -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
