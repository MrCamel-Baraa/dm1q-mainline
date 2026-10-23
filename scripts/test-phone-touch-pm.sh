#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-pm.sh (docs/06 rule 3). A fake sysfs / procfs / debugfs tree. Checks: the hold-awake sequence, the
# restore of the power/control values, NO-CHANGE when the interrupt count is flat, PM-HOLD-AWAKE when it rises while held (a background
# writer raises the count), NO-IRQ-LINE, the abort when a control file is missing (nothing changed), refusals (not root, bad WAIT),
# and the POSIX / shellcheck static checks. Run with bash.
# Usage: bash scripts/test-phone-touch-pm.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-pm.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
check()  { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

make_tree() {
	local D="$1"
	mkdir -p "$D/sys/bus/platform/devices/a90000.spi/power" "$D/sys/bus/spi/devices/spi0.0/power" "$D/proc" "$D/sys/kernel/debug"
	echo auto > "$D/sys/bus/platform/devices/a90000.spi/power/control"
	echo auto > "$D/sys/bus/spi/devices/spi0.0/power/control"
	echo suspended > "$D/sys/bus/platform/devices/a90000.spi/power/runtime_status"
	echo suspended > "$D/sys/bus/spi/devices/spi0.0/power/runtime_status"
	printf ' 181:       500          0          0          0          0          0          0          0  msmgpio                    25 Level     fts2ba61y\n' > "$D/proc/interrupts"
	echo "gpio25 (fts2ba61y) in hi" > "$D/sys/kernel/debug/gpio"
}

run() {
	local D="$1"; shift
	env ID_U=0 SYSFS="$D/sys" PROC="$D/proc" DEBUGFS="$D/sys/kernel/debug" WAIT=2 "$@" sh "$SCRIPT" > "$D.out" 2>&1
}
control_is() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; }

echo "== hold, flat interrupts"
make_tree "$W/flat"
run "$W/flat"; rc=$?
[ "$rc" = 0 ] && ok "flat run: exit 0" || bad "flat run: exit $rc"
expect "$W/flat.out" "the bus is held on while watching" "control now: a90000.spi=on spi0.0=on"
expect "$W/flat.out" "NO-CHANGE with a flat count" "RESULT pm irq_before=500 irq_after=500 delta=0 verdict=NO-CHANGE"
check "the serial engine control is restored" "control_is '$W/flat/sys/bus/platform/devices/a90000.spi/power/control' auto"
check "the SPI device control is restored" "control_is '$W/flat/sys/bus/spi/devices/spi0.0/power/control' auto"

echo "== interrupts rise while held"
make_tree "$W/rise"
( sleep 1; printf ' 181:       520          0          0          0          0          0          0          0  msmgpio                    25 Level     fts2ba61y\n' > "$W/rise/proc/interrupts" ) &
run "$W/rise" WAIT=3; rc=$?
wait
[ "$rc" = 0 ] && ok "rise run: exit 0" || bad "rise run: exit $rc"
expect "$W/rise.out" "PM-HOLD-AWAKE when the count rises" "RESULT pm irq_before=500 irq_after=520 delta=20 verdict=PM-HOLD-AWAKE"
check "the controls are restored after the rise too" "control_is '$W/rise/sys/bus/spi/devices/spi0.0/power/control' auto"

echo "== no touch interrupt line"
make_tree "$W/noirq"
: > "$W/noirq/proc/interrupts"
run "$W/noirq"
expect "$W/noirq.out" "NO-IRQ-LINE when the line is absent" "verdict=NO-IRQ-LINE"

echo "== missing control file"
make_tree "$W/nocontrol"
rm -f "$W/nocontrol/sys/bus/spi/devices/spi0.0/power/control"
run "$W/nocontrol"; rc=$?
[ "$rc" = 3 ] && ok "missing control: exit 3" || bad "missing control: exit $rc"
expect "$W/nocontrol.out" "the abort names the problem" "ABORT: power/control of a90000.spi or spi0.0 is not writable"
check "the serial engine control was not changed" "control_is '$W/nocontrol/sys/bus/platform/devices/a90000.spi/power/control' auto"

echo "== refusals"
make_tree "$W/refuse"
env ID_U=1 SYSFS="$W/refuse/sys" PROC="$W/refuse/proc" DEBUGFS="$W/refuse/sys/kernel/debug" sh "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
run "$W/refuse" WAIT=x; rc=$?
[ "$rc" = 2 ] && ok "non-numeric WAIT: exit 2" || bad "non-numeric WAIT: exit $rc"
check "a refused run changed no control" "control_is '$W/refuse/sys/bus/spi/devices/spi0.0/power/control' auto"

echo "== static checks"
sh -n "$SCRIPT" && ok "sh -n" || bad "sh -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
