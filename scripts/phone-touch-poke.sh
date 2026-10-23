#!/bin/sh
# Phone-side experiment (docs/08 section 2.21): which single SPI command revives a dead FTS2BA61Y, without an unbind?
# POSIX sh, run as root (collect-phone-state.sh --touch-poke=STEP does that). Run it only while touch is dead; it checks that itself.
# It uses the debugfs raw knob of kernel patch 0004 (/sys/kernel/debug/spi0.0/raw): one write = one SPI transfer, the read-back
# is "tx <hex> rx <hex>". It never unbinds, never changes power/control and sends exactly ONE transfer per run.
#   STEP    read      87+17          read one 18-byte event record (does the chip answer on SPI at all? is an event queued?)
#           senseon   C010           vendor "sense on" (what our input_open sends)
#           scanmode  A00001         vendor scan mode, never sent by our driver (docs/08 2.12)
#           reset     FA2000002481   soft reset (the chip restarts and should answer with a ready event)
#           hex:<h>   <h>            any hex bytes, "+N" appends N zero bytes (for example hex:C022 or hex:87+17)
# Phases:
#   pre      PRE seconds, DRAG A FINGER: the interrupt count must NOT move, otherwise the touch is not dead and nothing is sent (NOT-DEAD)
#   poke     the one transfer, the read-back, and a classification of the rx bytes (ALL-00, ALL-FF or DATA)
#   settle   SETTLE seconds, no finger: interrupts here are the chip answering the poke (for example a ready event after a reset)
#   watch    WAIT seconds, DRAG A FINGER: interrupts here mean the chip reports touch again
#   RESULT   poke step irq_pre irq_settle irq_end settle_delta watch_delta verdict
#            REVIVED         watch_delta > 0: this step brought touch back (the missing command, or the chip only needed a transfer)
#            CHIP-RESPONDED  interrupts while settling but none while dragging: the chip answered the poke but does not report touch
#            NO-CHANGE       no interrupts at all after the poke
#            NOT-DEAD        the touch interrupt moved during the pre phase: nothing was sent
#            NO-IRQ-LINE     the touch interrupt is not in /proc/interrupts
# write=ERR in the RESULT line: the knob's write() returned an error (the message is printed). The 2026-10-24 runs showed that the transfer can still
# have gone out (the recorder has it), so the script goes on with the settle and watch phases instead of stopping.
# Caution (docs/08 2.20): a soft reset makes the chip raise its own interrupts, so a reset's settle_delta is not touch activity;
# only watch_delta counts as touch. Send the steps one at a time, in the order read, senseon, scanmode, reset.
# Env (the PC-side test uses them): SYSFS PROC DEBUGFS DEV STEP PRE SETTLE WAIT ID_U RAW RAW_READ DD
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
DEV="${DEV:-spi0.0}"
STEP="${STEP:-read}"
PRE="${PRE:-3}"
SETTLE="${SETTLE:-2}"
WAIT="${WAIT:-8}"
RAW="${RAW:-$DEBUGFS/$DEV/raw}"
RAW_READ="${RAW_READ:-$RAW}"
DD="${DD:-dd}"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }
for _n in PRE SETTLE WAIT; do
	eval "_v=\$$_n"
	case "$_v" in ''|*[!0-9]*) echo "$_n must be a number (got '$_v')"; exit 2 ;; esac
done
[ "$PRE" -ge 1 ] && [ "$WAIT" -ge 1 ] || { echo "PRE and WAIT must be at least 1"; exit 2; }

case "$STEP" in
	read) HEX="87+17" ;;
	senseon) HEX="C010" ;;
	scanmode) HEX="A00001" ;;
	reset) HEX="FA2000002481" ;;
	hex:*)
		HEX="${STEP#hex:}"
		case "$HEX" in ''|*[!0-9A-Fa-f+]*) echo "STEP hex: takes hex digits and one +N suffix (got '$HEX')"; exit 2 ;; esac
		;;
	*) echo "STEP must be read, senseon, scanmode, reset or hex:<bytes> (got '$STEP')"; exit 2 ;;
esac

rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }
irq_count() {
	awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; f = 1; exit } END { if (!f) print -1 }' "$PROC/interrupts" 2>/dev/null
}
gpio_level() {
	awk '$1 == "gpio25" { print $4; f = 1; exit } END { if (!f) print "?" }' "$DEBUGFS/gpio" 2>/dev/null
}
say() { echo; echo "== $*"; }
tick() {
	# tick LABEL SECONDS: print the count once a second
	_t=1
	while [ "$_t" -le "$2" ]; do
		sleep 1
		echo "$1 t=$_t irq=$(irq_count) gpio25=$(gpio_level)"
		_t=$((_t + 1))
	done
}

say "before"
[ -f "$RAW" ] && [ -w "$RAW" ] || { echo "ABORT: $RAW is not writable (kernel patch 0004 / package r9 not running, or debugfs not mounted)"; exit 3; }
IRQ0=$(irq_count)
echo "step: $STEP  bytes: $HEX"
echo "irq: $IRQ0   gpio25: $(gpio_level)"
if [ "$IRQ0" = -1 ]; then
	echo "RESULT poke step=$STEP irq_pre=-1 irq_settle=-1 irq_end=-1 settle_delta=0 watch_delta=0 verdict=NO-IRQ-LINE"
	exit 0
fi

say "pre ${PRE} s (DRAG A FINGER: this run only goes on if the touch is dead)"
tick pre "$PRE"
IRQ1=$(irq_count)
if [ "$IRQ1" -gt "$IRQ0" ]; then
	echo "RESULT poke step=$STEP irq_pre=$IRQ0 irq_settle=$IRQ1 irq_end=$IRQ1 settle_delta=0 watch_delta=0 verdict=NOT-DEAD"
	echo "the touch interrupt moved ($IRQ0 -> $IRQ1): touch is alive, nothing was sent"
	exit 5
fi

say "poke"
IRQP=$(irq_count)
WRITE=ok
# dd, not a shell redirection: busybox printf exits non-zero WITHOUT a message when write() fails, dd names the errno
if ! WERR=$(printf '%s\n' "$HEX" | "$DD" of="$RAW" bs=64 2>&1 >/dev/null); then
	WRITE=ERR
	echo "the write to $RAW returned an error (the transfer may still have gone out, the recorder shows it): $(printf '%s' "$WERR" | tail -n 1)"
fi
LINE=$(rd "$RAW_READ")
echo "readback: $LINE"
RX="${LINE##* rx }"
case "$LINE" in
	*" rx "*)
		if [ -z "$(printf '%s' "$RX" | tr -d '0')" ]; then CLASS=ALL-00
		elif [ -z "$(printf '%s' "$RX" | tr -d 'fF')" ]; then CLASS=ALL-FF
		else CLASS=DATA; fi
		;;
	*) CLASS=NO-READBACK ;;
esac
echo "rx: $CLASS   (ALL-00 / ALL-FF: the chip drove nothing, so it is unpowered, in reset or not listening; DATA: it answered)"

say "settle ${SETTLE} s (no finger)"
if [ "$SETTLE" -ge 1 ]; then tick settle "$SETTLE"; fi
IRQ2=$(irq_count)

say "watch ${WAIT} s (>>> DRAG A FINGER NOW)"
tick watch "$WAIT"
IRQ3=$(irq_count)

say "result"
SD=$((IRQ2 - IRQP))
WD=$((IRQ3 - IRQ2))
if [ "$WD" -gt 0 ]; then VERDICT=REVIVED
elif [ "$SD" -gt 0 ]; then VERDICT=CHIP-RESPONDED
else VERDICT=NO-CHANGE; fi
echo "RESULT poke step=$STEP irq_pre=$IRQP irq_settle=$IRQ2 irq_end=$IRQ3 settle_delta=$SD watch_delta=$WD verdict=$VERDICT rx=$CLASS write=$WRITE"
exit 0
