#!/bin/sh
# Phone-side experiment (docs/08 section 2.18): does holding the touch bus awake bring the chip back?
# POSIX sh, run as root (collect-phone-state.sh --touch-pm does that). Run it while touch is dead AND drag a finger for the whole watch.
# It is reversible and does not unbind anything: it writes "on" to the power/control of the serial engine (a90000.spi) and of spi0.0,
# watches the touch interrupt count for WAIT seconds, and writes the previous control values back at exit (also on Ctrl-C).
#   before   the interrupt count, gpio25, the control values and the runtime status of both devices
#   hold     power/control=on for both (the runtime status should go to active)
#   watch    the interrupt count, gpio25 and the runtime status once a second for WAIT seconds
#   restore  the previous control values
#   RESULT   pm irq_before irq_after delta verdict
#            PM-HOLD-AWAKE  interrupts arrived while the bus was held awake (delta > 0): the runtime PM state is part of the failure
#            NO-CHANGE      no interrupts while held awake: the runtime PM state alone does not bring the chip back
#            NO-IRQ-LINE    the touch interrupt is not in /proc/interrupts
# Why (docs/08 2.18): both dead captures showed the serial engine runtime-suspended, the working capture showed it active. A correlation only.
# Env (the PC-side test uses them): SYSFS PROC DEBUGFS SE DEV WAIT ID_U
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
SE="${SE:-a90000.spi}"
DEV="${DEV:-spi0.0}"
WAIT="${WAIT:-15}"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }
case "$WAIT" in ''|*[!0-9]*) echo "WAIT must be a number (got '$WAIT')"; exit 2 ;; esac
[ "$WAIT" -ge 1 ] || { echo "WAIT must be at least 1"; exit 2; }

SE_CTL="$SYSFS/bus/platform/devices/$SE/power/control"
SE_RT="$SYSFS/bus/platform/devices/$SE/power/runtime_status"
SPI_CTL="$SYSFS/bus/spi/devices/$DEV/power/control"
SPI_RT="$SYSFS/bus/spi/devices/$DEV/power/runtime_status"

rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }
irq_count() {
	awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; f = 1; exit } END { if (!f) print -1 }' "$PROC/interrupts" 2>/dev/null
}
gpio_level() {
	awk '$1 == "gpio25" { print $4; f = 1; exit } END { if (!f) print "?" }' "$DEBUGFS/gpio" 2>/dev/null
}

RESTORED=1
SE_PREV=""
SPI_PREV=""
restore() {
	[ "$RESTORED" = 1 ] && return 0
	RESTORED=1
	echo
	echo "== restore"
	printf '%s\n' "$SE_PREV" > "$SE_CTL" 2>/dev/null
	printf '%s\n' "$SPI_PREV" > "$SPI_CTL" 2>/dev/null
	echo "control restored: $SE=$(rd "$SE_CTL") $DEV=$(rd "$SPI_CTL")"
}
trap restore EXIT
trap 'exit 130' INT TERM

say() { echo; echo "== $*"; }

say "before"
[ -w "$SE_CTL" ] && [ -w "$SPI_CTL" ] || { echo "ABORT: power/control of $SE or $DEV is not writable"; exit 3; }
SE_PREV=$(rd "$SE_CTL")
SPI_PREV=$(rd "$SPI_CTL")
RESTORED=0
IRQ0=$(irq_count)
G0=$(gpio_level)
echo "control: $SE=$SE_PREV $DEV=$SPI_PREV"
echo "runtime: $SE=$(rd "$SE_RT") $DEV=$(rd "$SPI_RT")"
echo "irq: $IRQ0   gpio25: $G0"

say "hold awake"
printf 'on\n' > "$SE_CTL" || { echo "ABORT: could not set $SE control to on"; exit 4; }
printf 'on\n' > "$SPI_CTL" || { echo "ABORT: could not set $DEV control to on"; exit 4; }
echo "control now: $SE=$(rd "$SE_CTL") $DEV=$(rd "$SPI_CTL")"
echo "runtime now: $SE=$(rd "$SE_RT") $DEV=$(rd "$SPI_RT")"

say "watch ${WAIT} s (drag a finger now)"
t=1
while [ "$t" -le "$WAIT" ]; do
	sleep 1
	echo "t=$t irq=$(irq_count) gpio25=$(gpio_level) runtime: $SE=$(rd "$SE_RT") $DEV=$(rd "$SPI_RT")"
	t=$((t + 1))
done
IRQ1=$(irq_count)

say "result"
if [ "$IRQ0" = -1 ] || [ "$IRQ1" = -1 ]; then
	VERDICT=NO-IRQ-LINE
	DELTA=0
else
	DELTA=$((IRQ1 - IRQ0))
	if [ "$DELTA" -gt 0 ]; then VERDICT=PM-HOLD-AWAKE; else VERDICT=NO-CHANGE; fi
fi
echo "RESULT pm irq_before=$IRQ0 irq_after=$IRQ1 delta=$DELTA verdict=$VERDICT"
exit 0
