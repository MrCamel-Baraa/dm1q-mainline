#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-scanmode.sh (docs/06 rule 3). A fake sysfs / procfs / debugfs / dev tree and a stub spi-xfer
# that logs its arguments and answers with a record. Checks: the normal swap-send-watch-restore path, the RESULT line, the send
# command, that the touch driver is bound back at the end, the abort when a rail loses its users (the restore still runs), the abort
# when the spidev node is missing, refusals (not root, bad WAIT), and the POSIX / shellcheck static checks. Run with bash.
# Usage: bash scripts/test-phone-touch-scanmode.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-scanmode.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
check()  { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# A fake tree: $1 = directory
make_tree() {
	local D="$1"
	mkdir -p "$D/sys/bus/spi/devices/spi0.0" "$D/sys/bus/spi/drivers/fts2ba61y" "$D/sys/bus/spi/drivers/spidev" \
		"$D/sys/class/regulator/regulator.1" "$D/sys/class/regulator/regulator.2" "$D/sys/kernel/debug" "$D/proc" "$D/dev"
	ln -s "$D/sys/bus/spi/drivers/fts2ba61y" "$D/sys/bus/spi/devices/spi0.0/driver"
	: > "$D/sys/bus/spi/drivers/fts2ba61y/unbind"
	: > "$D/sys/bus/spi/drivers/fts2ba61y/bind"
	: > "$D/sys/bus/spi/drivers/spidev/bind"
	: > "$D/sys/bus/spi/drivers/spidev/unbind"
	echo l12b > "$D/sys/class/regulator/regulator.1/name"
	echo 1 > "$D/sys/class/regulator/regulator.1/num_users"
	echo l16b > "$D/sys/class/regulator/regulator.2/name"
	echo 1 > "$D/sys/class/regulator/regulator.2/num_users"
	printf ' 25:       1000          0  GICv3  25 Level  fts2ba61y\n' > "$D/proc/interrupts"
	echo "gpio25 (fts2ba61y) in hi" > "$D/sys/kernel/debug/gpio"
	: > "$D/dev/spidev0.0"
	printf '#!/bin/sh\necho "xfer $*" >> "%s/xfer.log"\necho "RX 00 87 80 49 00 10 00 00"\n' "$D" > "$D/spi-xfer.sh"
	chmod +x "$D/spi-xfer.sh"
}

# Run the script on a tree: $1 = directory, rest = extra env assignments (later ones win)
run() {
	local D="$1"; shift
	env ID_U=0 ALLOW_UNBIND=1 SYSFS="$D/sys" PROC="$D/proc" DEVDIR="$D/dev" DEBUGFS="$D/sys/kernel/debug" MODPROBE=true \
		SPI_XFER="$D/spi-xfer.sh" WAIT=2 "$@" sh "$SCRIPT" > "$D.out" 2>&1
}
bound_back() { grep -qx spi0.0 "$1/sys/bus/spi/drivers/fts2ba61y/bind" 2>/dev/null; }
override_clear() { [ -z "$(cat "$1/sys/bus/spi/devices/spi0.0/driver_override" 2>/dev/null)" ]; }

echo "== normal run"
make_tree "$W/ok"
run "$W/ok"; rc=$?
[ "$rc" = 0 ] && ok "normal run: exit 0" || bad "normal run: exit $rc"
expect "$W/ok.out" "the RESULT line" "^RESULT scanmode irq_before=1000 irq_after=1000 gpio_before=hi gpio_after=hi gpio_low_samples=0/2 send_rc=0 answered_reads=2/2$"
expect "$W/ok.out" "gpio25 read right after the swap" "gpio25 right after the swap: hi"
expect "$W/ok.out" "rails after unbind shown" "rails after unbind: l12b:users=1 l16b:users=1"
expect "$W/ok.out" "restore binds the touch driver again" "bound spi0.0 to fts2ba61y again"
check "the scan-mode command was sent to the spidev node" "grep -q 'xfer $W/ok/dev/spidev0.0 1000000 A00001' '$W/ok/xfer.log'"
check "the watch read the chip record" "grep -q 'xfer $W/ok/dev/spidev0.0 1000000 87+17' '$W/ok/xfer.log'"
check "the touch driver was rebound at the end" "bound_back '$W/ok'"
check "driver_override is cleared at the end" "override_clear '$W/ok'"

echo "== rail loses its users after the swap"
make_tree "$W/rail"
echo 0 > "$W/rail/sys/class/regulator/regulator.2/num_users"
run "$W/rail"; rc=$?
[ "$rc" = 4 ] && ok "rail abort: exit 4" || bad "rail abort: exit $rc"
expect "$W/rail.out" "the abort names the rail" "ABORT: no touch rail found, or one has no users"
check "nothing was sent to the chip" "[ ! -e '$W/rail/xfer.log' ] || ! grep -q A00001 '$W/rail/xfer.log'"
check "the touch driver is still rebound after the abort" "bound_back '$W/rail'"

echo "== spidev node missing"
make_tree "$W/node"
rm -f "$W/node/dev/spidev0.0"
run "$W/node"; rc=$?
[ "$rc" = 4 ] && ok "node abort: exit 4" || bad "node abort: exit $rc"
expect "$W/node.out" "the abort names the node" "ABORT: .*spidev0.0 is missing"
check "the touch driver is rebound after the node abort" "bound_back '$W/node'"

echo "== no interrupt line while spidev is bound"
make_tree "$W/noirq"
: > "$W/noirq/proc/interrupts"
run "$W/noirq"
expect "$W/noirq.out" "the IRQ count is n/a, not -1" "RESULT scanmode irq_before=n/a irq_after=n/a"
echo "== no touch rail found"
make_tree "$W/norail"
rm -rf "$W/norail/sys/class/regulator"
run "$W/norail"; rc=$?
[ "$rc" = 4 ] && ok "no rail: exit 4" || bad "no rail: exit $rc"
expect "$W/norail.out" "the abort says no rail was found" "ABORT: no touch rail found"
check "nothing was sent with no rail found" "[ ! -e '$W/norail/xfer.log' ] || ! grep -q A00001 '$W/norail/xfer.log'"
check "the touch driver is rebound after the no-rail abort" "bound_back '$W/norail'"

echo "== blocked by default"
make_tree "$W/blocked"
env ID_U=0 SYSFS="$W/blocked/sys" PROC="$W/blocked/proc" DEVDIR="$W/blocked/dev" DEBUGFS="$W/blocked/sys/kernel/debug" MODPROBE=true \
	SPI_XFER="$W/blocked/spi-xfer.sh" WAIT=2 sh "$SCRIPT" > "$W/blocked.out" 2>&1; rc=$?
[ "$rc" = 5 ] && ok "no ALLOW_UNBIND: exit 5" || bad "no ALLOW_UNBIND: exit $rc"
expect "$W/blocked.out" "the block says why" "BLOCKED: unbinding the touch driver"
check "nothing was unbound or sent when blocked" "[ ! -e '$W/blocked/xfer.log' ] && [ ! -s '$W/blocked/sys/bus/spi/drivers/fts2ba61y/unbind' ]"

echo "== refusals"
make_tree "$W/refuse"
env ID_U=1 SYSFS="$W/refuse/sys" PROC="$W/refuse/proc" DEVDIR="$W/refuse/dev" DEBUGFS="$W/refuse/sys/kernel/debug" \
	MODPROBE=true SPI_XFER="$W/refuse/spi-xfer.sh" sh "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
run "$W/refuse" WAIT=x; rc=$?
[ "$rc" = 2 ] && ok "non-numeric WAIT: exit 2" || bad "non-numeric WAIT: exit $rc"
check "a refused run sent nothing to the chip" "[ ! -e '$W/refuse/xfer.log' ]"

echo "== static checks"
sh -n "$SCRIPT" && ok "sh -n" || bad "sh -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
