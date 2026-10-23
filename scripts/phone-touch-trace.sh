#!/bin/sh
# Phone-side flight recorder for the touch drop-out (docs/08 section 2.14). POSIX sh, run as root
# (collect-phone-state.sh --touch-trace=arm|dump|disarm does that). Usage: sh phone-touch-trace.sh arm|dump|disarm
#
# Why: when the touch chip goes silent the kernel prints nothing and the driver does not read the chip any more (it only reads when gpio25 asserts), so a
# trace started AFTER the failure is empty (the 2026-10-21 touch-watch run). The only record of what the chip said last is the SPI traffic before it stopped.
# `arm` starts a dedicated trace instance (/sys/kernel/tracing/instances/dm1q-touch) that keeps the spi:spi_transfer_stop records of spi0.0 (tx and rx, the first
# 64 bytes of each transfer) in a ring buffer that overwrites the oldest records: after the chip goes quiet nothing new is written, so the buffer still holds the
# final seconds of its traffic. It lives in RAM until the next reboot (arm again after every boot) and costs a few MB.
#   arm      creates / resets the instance, enables the event for bus 0 / cs 0, then (CHECK seconds, default 6) asks you to drag a finger and checks that the
#            interrupt count rises. If it does not (touch is dead right now) and REVIVE=1 (default) it power-cycles the chip with an unbind / bind of spi0.0 (what
#            worked on 2026-10-21) and checks again, so that the NEXT failure is the one that gets recorded. The device is always left bound.
#   dump     changes nothing: saves the raw buffer to $OUT, prints the buffer statistics, the current interrupt count / gpio25 / rails, the decoded records
#            (event id counts, every non-coordinate record, the last 20 records, records per second before the last one, the largest gap), and how long ago
#            the last record was, then the journal lines of ALL units within 30 s of the last record (docs/08 2.21: what userspace did when the chip stopped).
#            Run it BEFORE reviving the touch (reviving does not clear the buffer, but new touch traffic overwrites the oldest records).
#   disarm   stops the event and removes the instance.
# Event layout (kernel patch 0002): rx = 2 header bytes (00 87) then 16-byte events; event byte0: bits 1:0 = id (0 coordinate, 1 status, 2 / 3 other),
# bits 5:2 = touch id (coordinate) or status type (stype).
# Env (the PC-side test uses them): SYSFS PROC DEBUGFS DMESG JOURNALCTL TRACEFS MOUNT MKDIR RMDIR OUT TMPDIR NAME SPIDEV IRQ_GPIO BUF_KB CHECK REVIVE COUNTDOWN ID_U
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
DMESG="${DMESG:-dmesg}"
JOURNALCTL="${JOURNALCTL:-journalctl}"
TRACEFS="${TRACEFS:-$SYSFS/kernel/tracing}"
MOUNT="${MOUNT:-mount}"
MKDIR="${MKDIR:-mkdir}"
RMDIR="${RMDIR:-rmdir}"
NAME="${NAME:-STMicroelectronics FTS2BA61Y Touchscreen}"
SPIDEV="${SPIDEV:-spi0.0}"
IRQ_GPIO="${IRQ_GPIO:-25}"
BUF_KB="${BUF_KB:-4096}"
CHECK="${CHECK:-6}"
REVIVE="${REVIVE:-1}"
COUNTDOWN="${COUNTDOWN:-2}"
TMPD="${TMPDIR:-/tmp}"
OUT="${OUT:-$TMPD/dm1q-touch-trace-raw.txt}"
MODE="${1:-}"
INST="$TRACEFS/instances/dm1q-touch"
TE="$INST/events/spi/spi_transfer_stop"
DRVDIR="$SYSFS/bus/spi/drivers/fts2ba61y"

for kv in BUF_KB:$BUF_KB CHECK:$CHECK COUNTDOWN:$COUNTDOWN; do
	case "${kv#*:}" in ''|*[!0-9]*) echo "${kv%%:*} must be a number (got '${kv#*:}')"; exit 2 ;; esac
done
[ "$BUF_KB" -ge 64 ] || { echo "BUF_KB must be at least 64"; exit 2; }
case "$MODE" in arm|dump|disarm) ;; *) echo "usage: sh phone-touch-trace.sh arm|dump|disarm"; exit 2 ;; esac
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }
irq_count() {
	awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; found = 1; exit } END { if (!found) print -1 }' "$PROC/interrupts" 2>/dev/null
}
gpio_level() {
	awk -v g="gpio$IRQ_GPIO" '$1 == g { print $4; found = 1; exit } END { if (!found) print "?" }' "$DEBUGFS/gpio" 2>/dev/null
}
reg_line() {
	for d in "$SYSFS"/class/regulator/regulator.*; do
		[ -d "$d" ] || continue
		if [ "$(rd "$d/name")" = "$1" ]; then echo "$(rd "$d/state"):$(rd "$d/microvolts")uV:users=$(rd "$d/num_users")"; return 0; fi
	done
	echo none
}
uptime_s() { read -r _u _ < "$PROC/uptime" 2>/dev/null; echo "${_u:-0}"; }
state_line() { echo "irq count: $(irq_count)   gpio$IRQ_GPIO: $(gpio_level)   l12b=$(reg_line vreg_l12b_1p8) l16b=$(reg_line vreg_l16b_3p0)"; }

EXPERIMENTED=0
cleanup() {
	if [ "$EXPERIMENTED" = 1 ] && [ ! -e "$SYSFS/bus/spi/devices/$SPIDEV/driver" ]; then
		echo "cleanup: $SPIDEV is not bound: binding it again"
		echo "$SPIDEV" > "$DRVDIR/bind" 2>/dev/null
	fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

alive_check() { # $1 seconds; sets ALIVE_DELTA
	_i=0
	_a0=$(irq_count)
	_a=$_a0
	while [ "$_i" -lt "$1" ]; do
		sleep 1
		_i=$((_i + 1))
		_a=$(irq_count)
		echo "  t=$_i irq=$_a gpio$IRQ_GPIO=$(gpio_level)"
	done
	ALIVE_DELTA=$((_a - _a0))
	[ "$_a0" = -1 ] && ALIVE_DELTA=-1
}

do_arm() {
	[ -d "$TRACEFS/events/spi" ] || "$MOUNT" -t tracefs nodev "$TRACEFS" 2>/dev/null
	if [ ! -d "$TRACEFS/instances" ]; then
		echo "RESULT: NO-TRACE-INSTANCES ($TRACEFS/instances does not exist: tracefs is not mounted or the kernel has no trace instances)"
		exit 3
	fi
	if [ -d "$INST" ]; then "$RMDIR" "$INST" 2>/dev/null; fi
	if [ -d "$INST" ]; then
		echo "instance $INST already exists and cannot be removed: reusing it and clearing it"
	else
		"$MKDIR" "$INST" || { echo "RESULT: CANNOT-CREATE-INSTANCE ($INST)"; exit 3; }
	fi
	if [ ! -d "$TE" ]; then
		echo "RESULT: NO-SPI-EVENT (no spi:spi_transfer_stop trace event in $INST: the kernel was built without it)"
		"$RMDIR" "$INST" 2>/dev/null
		exit 3
	fi
	echo 0 > "$TE/enable"
	: > "$INST/trace"
	echo "$BUF_KB" > "$INST/buffer_size_kb" 2>/dev/null || echo "could not set buffer_size_kb to $BUF_KB (the kernel default stays)"
	echo 'bus_num == 0 && chip_select == 0' > "$TE/filter" 2>/dev/null || echo "the filter was rejected: every SPI controller's transfers will be recorded (spi0.0 lines are picked out when decoding)"
	echo 1 > "$TE/enable"
	echo 1 > "$INST/tracing_on"
	if [ "$(rd "$TE/enable")" != 1 ] || [ "$(rd "$INST/tracing_on")" != 1 ]; then
		echo "RESULT: ARM-FAILED (enable=$(rd "$TE/enable") tracing_on=$(rd "$INST/tracing_on"))"
		exit 3
	fi
	echo "armed: $INST (spi:spi_transfer_stop, bus 0 / cs 0), buffer_size_kb=$(rd "$INST/buffer_size_kb") per CPU, at uptime $(uptime_s) s"
	echo "it lives in RAM until the next reboot: arm again after every boot"
	state_line
	if [ "$CHECK" -gt 0 ]; then
		echo ">>> alive check starts in $COUNTDOWN s: DRAG A FINGER on the screen for $CHECK s"
		sleep "$COUNTDOWN"
		alive_check "$CHECK"
		if [ "$ALIVE_DELTA" -gt 0 ]; then
			echo "touch is alive now ($ALIVE_DELTA interrupts in $CHECK s)"
		elif [ "$ALIVE_DELTA" = -1 ]; then
			echo "no fts2ba61y interrupt line in $PROC/interrupts: the touch driver is not loaded"
		else
			echo "touch looks DEAD right now (no interrupts in $CHECK s; only meaningful if you dragged a finger)"
			if [ "$REVIVE" = 1 ] && [ -d "$DRVDIR" ]; then
				echo "reviving it with a rebind of $SPIDEV (power cycle of the chip) so that the next failure is the one that gets recorded"
				EXPERIMENTED=1
				echo "$SPIDEV" > "$DRVDIR/unbind" || echo "unbind failed"
				sleep 1
				echo "$SPIDEV" > "$DRVDIR/bind" || echo "bind failed"
				sleep 2
				echo "rails: l12b=$(reg_line vreg_l12b_1p8) l16b=$(reg_line vreg_l16b_3p0)"
				echo ">>> DRAG A FINGER again for $CHECK s"
				alive_check "$CHECK"
				if [ "$ALIVE_DELTA" -gt 0 ]; then echo "RESULT: REVIVED by rebind ($ALIVE_DELTA interrupts); recorder armed"; else echo "RESULT: STILL-SILENT after the rebind; recorder armed"; fi
				exit 0
			fi
		fi
	fi
	echo "RESULT: ARMED"
}

do_disarm() {
	if [ -d "$INST" ]; then
		echo 0 > "$TE/enable" 2>/dev/null
		echo 0 > "$INST/tracing_on" 2>/dev/null
		"$RMDIR" "$INST" 2>/dev/null
	fi
	if [ -d "$INST" ]; then echo "RESULT: instance $INST could not be removed (it is stopped)"; else echo "RESULT: DISARMED"; fi
}

do_dump() {
	if [ ! -d "$INST" ]; then
		echo "RESULT: NOT-ARMED ($INST does not exist: a reboot clears the recorder; run arm first)"
		exit 4
	fi
	echo "recorder: enable=$(rd "$TE/enable") tracing_on=$(rd "$INST/tracing_on") buffer_size_kb=$(rd "$INST/buffer_size_kb") filter=$(rd "$TE/filter")"
	for c in "$INST"/per_cpu/cpu*; do
		[ -d "$c" ] || continue
		echo "  $(basename "$c"): $(grep -E '^(entries|overrun|bytes):' "$c/stats" 2>/dev/null | tr '\n' ' ')"
	done
	cat "$INST/trace" > "$OUT" 2>/dev/null || { echo "RESULT: CANNOT-READ-TRACE"; exit 3; }
	echo "raw buffer saved: $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
	UP=$(uptime_s)
	echo "uptime now: $UP s (boot clock)"
	state_line
	echo "-- kernel log lines about the touch chip (all of the ring buffer):"
	"$DMESG" 2>/dev/null | grep -i -E 'fts2ba61y|nobody cared|spi_geni|a90000' | tail -n 20 | cut -c1-200 | sed 's/^/   /'
	echo "-- decoded records of $SPIDEV:"
	awk -v up="$UP" -v dev="$SPIDEV" '
function hv(s,   i, c, v) { v = 0; s = tolower(s); for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)) - 1; if (c < 0) return -1; v = v * 16 + c } return v }
/^#/ { next }
index($0, "spi_transfer_stop") == 0 { next }
index($0, dev " ") == 0 { next }
{
	ts = ""
	for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { ts = substr($i, 1, length($i) - 1); break }
	if (ts == "") next
	len = 0
	if (match($0, /len=[0-9]+/)) len = substr($0, RSTART + 4, RLENGTH - 4)
	if (!match($0, /rx=\[[0-9a-fA-F-]*\]/)) next
	rx = substr($0, RSTART + 4, RLENGTH - 5)
	nb = split(rx, b, "-")
	n++
	T[n] = ts + 0
	L[n] = len
	e0 = (nb >= 3) ? hv(b[3]) : -1
	ID[n] = (e0 >= 0) ? e0 % 4 : -1
	ST[n] = (e0 >= 0) ? int(e0 / 4) % 16 : -1
	ev = ""
	for (k = 3; k <= nb && k <= 18; k++) ev = ev (k > 3 ? " " : "") b[k]
	E[n] = ev
	C[ID[n]]++
	if (n > 1 && T[n] - T[n - 1] > maxgap) { maxgap = T[n] - T[n - 1]; gapend = T[n] }
}
END {
	if (n == 0) { print "records=0: the buffer holds no transfer of " dev " (nothing was read since arming: the chip never asserted gpio25, or the recorder was armed after the failure)"; exit }
	printf "records=%d first=%.6f last=%.6f (span %.1f s)\n", n, T[1], T[n], T[n] - T[1]
	printf "last record is %.1f s older than the boot clock now (%s s); if the system suspended since, that includes the suspended time\n", up - T[n], up
	printf "event ids: coordinate(0)=%d status(1)=%d other(2)=%d other(3)=%d undecodable=%d\n", C[0], C[1], C[2], C[3], C[-1]
	printf "largest gap between two records: %.3f s (ending at %.6f)\n", maxgap, gapend
	printf "records per second before the last record (newest first, 10 buckets):"
	for (i = n; i >= 1 && T[i] > T[n] - 10; i--) R[int(T[n] - T[i])]++
	for (k = 0; k < 10; k++) printf " %d", R[k]
	printf "\n"
	shown = 0
	print "non-coordinate records (id != 0), first 40:"
	for (i = 1; i <= n && shown < 40; i++) if (ID[i] != 0) { shown++; printf "   %.6f len=%s id=%d stype=%d ev=%s\n", T[i], L[i], ID[i], ST[i], E[i] }
	if (shown == 0) print "   none in the buffer"
	print "last 20 records:"
	for (i = (n > 20 ? n - 19 : 1); i <= n; i++) printf "   %.6f len=%s id=%d ev=%s\n", T[i], L[i], ID[i], E[i]
}' "$OUT"
	LAST=$(awk -v dev="$SPIDEV" 'index($0, "spi_transfer_stop") && index($0, dev " ") { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t = substr($i, 1, length($i) - 1); break } } END { if (t != "") print t }' "$OUT")
	if [ -n "$LAST" ]; then
		echo "-- journal, all units, within 30 s of the last record ($LAST s, monotonic clock):"
		"$JOURNALCTL" -b --no-pager -o short-monotonic 2>/dev/null | awk -v last="$LAST" '
match($0, /^\[ *[0-9]+\.[0-9]+\]/) { t = substr($0, RSTART + 1, RLENGTH - 2) + 0; if (t >= last - 30 && t <= last + 30) { n++; if (n <= 150) print "   " substr($0, 1, 220) } }
END { if (n == 0) print "   no journal lines in that window (journalctl missing, or the journal is not readable)"; else if (n > 150) print "   ... " n - 150 " more lines not shown" }'
	fi
	echo "RESULT: DUMPED (the recorder stays armed)"
}

case "$MODE" in
arm) do_arm ;;
dump) do_dump ;;
disarm) do_disarm ;;
esac
