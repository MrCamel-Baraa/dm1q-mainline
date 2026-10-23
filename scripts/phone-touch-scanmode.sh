#!/bin/sh
# Phone-side experiment for the touch drop-out (docs/08 section 2.12: our driver never sends the vendor's scan mode A0 00 01).
# POSIX sh, run as root (collect-phone-state.sh --touch-scanmode does that). Run it ONLY while touch is dead.
# BLOCKED on the current image (docs/08 section 2.18, 2026-10-23): unbinding the touch driver takes both touch rails to zero users, so the chip
# loses power during the swap and the test measures nothing. The script exits 5 unless ALLOW_UNBIND=1 is set, which is only meant for an image
# that holds the rails on (the B1 image of docs/08 section 2). A driver knob that sends the command without an unbind is the real fix for this test.
# It is NOT read-only: it swaps the touch driver for spidev on spi0.0, sends the scan-mode command once with the spi-xfer helper,
# watches the interrupt line and the chip's reads for WAIT seconds, and then always gives spi0.0 back to fts2ba61y (which
# power-cycles the chip and re-initialises it).
#   before   the interrupt count, gpio25, the bound driver and the rails' user counts
#   swap     driver_override=spidev, unbind fts2ba61y, bind spidev. Aborts (and restores) if a touch rail loses all its users,
#            or if the spidev node is missing
#   send     the scan-mode command once (SENDHEX, default A00001)
#   watch    the interrupt count, gpio25 and one event read per second for WAIT seconds
#   restore  clears driver_override, unbinds spidev and binds fts2ba61y again (runs on every exit, including Ctrl-C)
#   RESULT   one line: irq before/after, gpio25 before/after, the send rc, and how many reads answered with a non-trivial record
# Reading the RESULT (docs/08 2.12): irq after > irq before and reads answered -> the scan mode was the missing step;
# irq flat and reads answered with 00 / ff only -> not the scan mode; no answers at all -> the chip is not talking on SPI.
# Env (the PC-side test uses them): SPI_XFER SYSFS PROC DEVDIR DEBUGFS MODPROBE NODE DRV HZ WAIT SENDHEX ID_U
X="${SPI_XFER:-/tmp/spi-xfer}"
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DEVDIR="${DEVDIR:-/dev}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
MODPROBE="${MODPROBE:-modprobe}"
NODE="${NODE:-spi0.0}"
DRV="${DRV:-fts2ba61y}"
HZ="${HZ:-1000000}"
WAIT="${WAIT:-6}"
SENDHEX="${SENDHEX:-A00001}"
DEVNODE="$DEVDIR/spidev${NODE#spi}"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }
[ "${ALLOW_UNBIND:-0}" = 1 ] || { echo "BLOCKED: unbinding the touch driver takes both touch rails to zero users and the chip loses power (docs/08 2.18). Set ALLOW_UNBIND=1 only on an image that holds the rails on."; exit 5; }
case "$WAIT" in ''|*[!0-9]*) echo "WAIT must be a number (got '$WAIT')"; exit 2 ;; esac
[ "$WAIT" -ge 1 ] || { echo "WAIT must be at least 1"; exit 2; }

rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }
irq_count() {
	awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; f = 1; exit } END { if (!f) print -1 }' "$PROC/interrupts" 2>/dev/null
}
gpio_level() {
	awk '$1 == "gpio25" { print $4; f = 1; exit } END { if (!f) print "?" }' "$DEBUGFS/gpio" 2>/dev/null
}
rails() {
	for d in "$SYSFS"/class/regulator/regulator.*; do
		[ -d "$d" ] || continue
		n=$(rd "$d/name")
		case "$n" in *l12b*|*l16b*) echo "$n:users=$(rd "$d/num_users")" ;; esac
	done
}
rails_ok() { # fails when no touch rail was found at all (we cannot verify power) or when one has no users
	_n=0
	for r in $(rails); do
		_n=$((_n + 1))
		case "$r" in *users=0) return 1 ;; esac
	done
	[ "$_n" -gt 0 ]
}
irq_show() { if [ "$1" = -1 ]; then echo n/a; else echo "$1"; fi; }
answered() { # $1 = one line of spi-xfer output: count it only if it carries a record (not all 00 / ff)
	echo "$1" | grep -q '^RX' || return 1
	echo "$1" | grep -qiE '^RX( (00|ff))*$' && return 1
	return 0
}

RESTORED=0
restore() {
	[ "$RESTORED" = 1 ] && return 0
	RESTORED=1
	echo
	echo "== restore"
	printf '\n' > "$SYSFS/bus/spi/devices/$NODE/driver_override" 2>/dev/null
	if [ -e "$SYSFS/bus/spi/drivers/spidev/$NODE" ]; then
		echo "$NODE" > "$SYSFS/bus/spi/drivers/spidev/unbind" 2>/dev/null
	fi
	if echo "$NODE" > "$SYSFS/bus/spi/drivers/$DRV/bind" 2>/dev/null; then
		echo "bound $NODE to $DRV again"
	else
		echo "RESTORE FAILED: could not bind $NODE to $DRV (echo $NODE > /sys/bus/spi/drivers/$DRV/bind by hand)"
	fi
	echo "driver now: $(readlink "$SYSFS/bus/spi/devices/$NODE/driver" 2>/dev/null)"
}
trap restore EXIT
trap 'exit 130' INT TERM

say() { echo; echo "== $*"; }

say "before"
IRQ0=$(irq_count)
G0=$(gpio_level)
echo "driver: $(readlink "$SYSFS/bus/spi/devices/$NODE/driver" 2>/dev/null)"
echo "irq: $IRQ0   gpio25: $G0"
echo "rails: $(rails | tr '\n' ' ')"

say "swap to spidev"
o=$($MODPROBE spidev 2>&1); echo "modprobe spidev rc=$? $o"
echo spidev > "$SYSFS/bus/spi/devices/$NODE/driver_override" || { echo "ABORT: driver_override"; exit 3; }
echo "$NODE" > "$SYSFS/bus/spi/drivers/$DRV/unbind" || { echo "ABORT: unbind from $DRV"; exit 3; }
echo "$NODE" > "$SYSFS/bus/spi/drivers/spidev/bind" || { echo "ABORT: bind to spidev"; exit 3; }
echo "rails after unbind: $(rails | tr '\n' ' ')"
rails_ok || { echo "ABORT: no touch rail found, or one has no users after the unbind (the chip may be unpowered)"; exit 4; }
[ -e "$DEVNODE" ] || { echo "ABORT: $DEVNODE is missing"; exit 4; }
echo "driver now: $(readlink "$SYSFS/bus/spi/devices/$NODE/driver" 2>/dev/null)   node: $DEVNODE"
echo "gpio25 right after the swap: $(gpio_level)  (the touch IRQ is released while spidev is bound, so the count is n/a)"

say "send $SENDHEX"
OUT=$("$X" "$DEVNODE" "$HZ" "$SENDHEX" 2>&1); SRC=$?
echo "spi-xfer rc=$SRC"
echo "$OUT"

say "watch ${WAIT} s"
ANS=0
LOWS=0
t=1
while [ "$t" -le "$WAIT" ]; do
	sleep 1
	R=$("$X" "$DEVNODE" "$HZ" 87+17 2>&1)
	answered "$R" && ANS=$((ANS + 1))
	GL=$(gpio_level)
	[ "$GL" = low ] && LOWS=$((LOWS + 1))
	echo "t=$t irq=$(irq_show "$(irq_count)") gpio25=$GL read: $R"
	t=$((t + 1))
done
IRQ1=$(irq_count)
G1=$(gpio_level)

say "result"
echo "RESULT scanmode irq_before=$(irq_show "$IRQ0") irq_after=$(irq_show "$IRQ1") gpio_before=$G0 gpio_after=$G1 gpio_low_samples=$LOWS/$WAIT send_rc=$SRC answered_reads=$ANS/$WAIT"
echo "rails at the end of the test: $(rails | tr '\n' ' ')"
exit 0
