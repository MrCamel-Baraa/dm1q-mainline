#!/bin/sh
# Phone-side touch watcher for the "touch stops working" bug (docs/08 2.11, 2.12, 2.13). POSIX sh, run as root
# (collect-phone-state.sh --touch-watch[=SECONDS] [--touch-sleepwake[=SECONDS]] [--touch-recover] does that).
#
# What it does, in phases (the user DRAGS A FINGER CONTINUOUSLY during every phase; a silent chip and an untouched screen look the same):
#   touch      DUR seconds (default 45): holds the touchscreen's evdev node open with a background reader, and once a second prints the fts2ba61y interrupt
#              count, the gpio25 level, the evdev byte/event count, how long nothing has changed (idle=), the runtime-PM state of the SPI device and its
#              serial engine, the L12B / L16B rail state, the DSI-1 connector (enabled/dpms) and the backlight (bl_power/brightness). At the end of the phase:
#              a verdict (see below), the new kernel log lines that mention touch/spi/panel/regulator/irq, and the last SPI transfers of spi0.0 with their raw
#              tx/rx bytes (the `spi:spi_transfer_stop` tracepoint; the 0x87 event reads show the chip's last status records, which our driver drops silently).
#   sleepwake  only when PHASE_B > 0: the script says when to press the power key (screen off), wait 5 s, press it again (screen on), and keep dragging.
#   rebind, modreload  only when RECOVER=1 AND the touch phase did not show flowing events: ONE reversible experiment at a time, each followed by a RWIN-second
#              window, stopping at the first one that brings events back:
#                rebind     echo spi0.0 > .../fts2ba61y/unbind, then bind: the driver's remove disables L12B/L16B (a real power cycle of the chip), probe re-enables them,
#                           soft-resets and reads the id again
#                modreload  modprobe -r fts2ba61y, then modprobe fts2ba61y (the same plus a module reload)
#              The script always leaves the device bound again (also on Ctrl-C / ssh drop).
# Verdicts (kernel-level, from this reader; they say where the chain breaks, hypotheses of notes/2026-10-20-handoff-touch.md):
#   EVENTS-FLOW                 evdev bytes arrive: the chip, the interrupt and the driver work; if the UI is dead it is userspace (H4)
#   IRQ-COUNTS-NO-EVDEV         the interrupt count rises but evdev stays silent: driver/slot logic (H3)
#   IRQ-LINE-LOW-NOT-SERVICED   gpio25 was seen LOW with no new interrupts: asserted but not serviced (H2)
#   CHIP-SILENT                 no interrupts, no events, gpio25 high: the chip is not reporting (H1, H5, H6; the experiments and the SPI trace separate them)
#   NO-IRQ-LINE / NO-DEVICE     the fts2ba61y interrupt line / the input device does not exist
# Never opens /dev/dri/*. Writes only: the temp dir, the tracefs controls of the spi_transfer_stop event (restored at exit), and, only with RECOVER=1,
# the unbind / bind files of the fts2ba61y driver and modprobe.
# Env (the PC-side test uses them): SYSFS PROC DEBUGFS DMESG DUR STEP PHASE_B RECOVER RWIN COUNTDOWN READER MODPROBE MOUNT SYSTEMCTL TRACE TRACEFS EVDIR
#   NAME SPIDEV IRQ_GPIO TMPDIR ID_U
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
DMESG="${DMESG:-dmesg}"
NAME="${NAME:-STMicroelectronics FTS2BA61Y Touchscreen}"
SPIDEV="${SPIDEV:-spi0.0}"
IRQ_GPIO="${IRQ_GPIO:-25}"
EVDIR="${EVDIR:-/dev/input}"
DUR="${DUR:-45}"
STEP="${STEP:-1}"
PHASE_B="${PHASE_B:-0}"
RECOVER="${RECOVER:-0}"
RWIN="${RWIN:-15}"
COUNTDOWN="${COUNTDOWN:-3}"
READER="${READER:-cat}"
MODPROBE="${MODPROBE:-modprobe}"
MOUNT="${MOUNT:-mount}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
TRACE="${TRACE:-1}"
TRACEFS="${TRACEFS:-$SYSFS/kernel/tracing}"
TMPD="${TMPDIR:-/tmp}"

num() { case "$2" in ''|*[!0-9]*) echo "$1 must be a number of seconds (got '$2')"; exit 2 ;; esac; }
num DUR "$DUR"; num STEP "$STEP"; num PHASE_B "$PHASE_B"; num RWIN "$RWIN"; num COUNTDOWN "$COUNTDOWN"
[ "$STEP" -ge 1 ] || { echo "STEP must be at least 1"; exit 2; }
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

W="$TMPD/dm1q-touch-watch.$$"
mkdir -p "$W" || { echo "cannot create $W"; exit 1; }
EVF="$W/ev.bin"
RES="$W/results"
: > "$RES"
RPID=""
EVNODE=""
TRACE_OK=0
EXPERIMENTED=0
RECOVERED_BY=""
LAST_VERDICT=""
DRVDIR="$SYSFS/bus/spi/drivers/fts2ba61y"

say() { echo; echo "== $*"; }
rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }

find_ev() {
	awk -v n="Name=\"$NAME\"" '/^N: / { hit = (index($0, n) > 0) } hit && /^H: Handlers=/ { if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }' "$PROC/bus/input/devices" 2>/dev/null
}
irq_count() {
	awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; found = 1; exit } END { if (!found) print -1 }' "$PROC/interrupts" 2>/dev/null
}
gpio_level() {
	awk -v g="gpio$IRQ_GPIO" '$1 == g { print $4; found = 1; exit } END { if (!found) print "?" }' "$DEBUGFS/gpio" 2>/dev/null
}
evbytes() { _n=$(wc -c < "$EVF" 2>/dev/null | tr -d ' '); echo "${_n:-0}"; }

reg_dir() {
	for d in "$SYSFS"/class/regulator/regulator.*; do
		[ -d "$d" ] || continue
		if [ "$(rd "$d/name")" = "$1" ]; then echo "$d"; return 0; fi
	done
	return 1
}
reg_line() { if [ -n "$1" ]; then echo "$(rd "$1/state"):$(rd "$1/microvolts")uV:users=$(rd "$1/num_users")"; else echo "none"; fi; }
R12=$(reg_dir vreg_l12b_1p8)
R16=$(reg_dir vreg_l16b_3p0)
DSI=""
for d in "$SYSFS"/class/drm/card*-DSI-1; do if [ -d "$d" ]; then DSI="$d"; break; fi; done
BL=""
for d in "$SYSFS"/class/backlight/*; do if [ -d "$d" ]; then BL="$d"; break; fi; done
dsi_line() { if [ -n "$DSI" ]; then echo "$(rd "$DSI/enabled")/$(rd "$DSI/dpms")"; else echo "?"; fi; }
bl_line() { if [ -n "$BL" ]; then echo "$(rd "$BL/bl_power")/$(rd "$BL/brightness")"; else echo "?"; fi; }

holders() { # comm names of the other processes that have the evdev node open (slow: used once per phase)
	for p in "$PROC"/[0-9]*; do
		[ -d "$p/fd" ] || continue
		[ "$p" = "$PROC/${RPID:-none}" ] && continue
		for f in "$p"/fd/*; do
			if [ "$(readlink "$f" 2>/dev/null)" = "$EVDIR/$EVNODE" ]; then rd "$p/comm"; echo; break; fi
		done
	done | sort -u | tr '\n' ' '
}

stop_reader() {
	if [ -n "$RPID" ]; then kill "$RPID" 2>/dev/null; wait "$RPID" 2>/dev/null; fi
	RPID=""
}
reader_alive() { [ -n "$RPID" ] && kill -0 "$RPID" 2>/dev/null; }
start_reader() {
	stop_reader
	EVNODE=""
	t=0
	while [ "$t" -lt 6 ]; do
		EVNODE=$(find_ev)
		[ -n "$EVNODE" ] && break
		sleep 1
		t=$((t + 1))
	done
	if [ -z "$EVNODE" ]; then echo "no input device named '$NAME' in $PROC/bus/input/devices"; return 1; fi
	: > "$EVF"
	$READER "$EVDIR/$EVNODE" > "$EVF" 2>/dev/null &
	RPID=$!
	sleep 1
	if reader_alive; then
		echo "reader holds $EVDIR/$EVNODE open (pid $RPID)"
	else
		echo "the reader could not hold $EVDIR/$EVNODE open"
		RPID=""
		return 1
	fi
}
ensure_reader() {
	cur=$(find_ev)
	if reader_alive && [ -n "$cur" ] && [ "$cur" = "$EVNODE" ]; then return 0; fi
	start_reader
}

trace_on() {
	[ "$TRACE" = 1 ] || { echo "trace: off (TRACE=0)"; return 0; }
	[ -d "$TRACEFS/events/spi" ] || "$MOUNT" -t tracefs nodev "$TRACEFS" 2>/dev/null
	TE="$TRACEFS/events/spi/spi_transfer_stop"
	if [ ! -d "$TE" ]; then echo "trace: no spi_transfer_stop event under $TRACEFS: skipped"; return 0; fi
	T_EN=$(rd "$TE/enable")
	T_ON=$(rd "$TRACEFS/tracing_on")
	echo 'bus_num == 0 && chip_select == 0' > "$TE/filter" 2>/dev/null || echo "trace: the filter was rejected, spi0.0 lines are picked out when printing"
	: > "$TRACEFS/trace" 2>/dev/null
	echo 1 > "$TE/enable" && echo 1 > "$TRACEFS/tracing_on" && TRACE_OK=1
	echo "trace: spi:spi_transfer_stop enabled for bus 0 / cs 0 (was enable=${T_EN:-?} tracing_on=${T_ON:-?}), restored at exit"
}
trace_off() {
	[ "$TRACE_OK" = 1 ] || return 0
	echo "${T_EN:-0}" > "$TE/enable" 2>/dev/null
	echo 0 > "$TE/filter" 2>/dev/null
	echo "${T_ON:-1}" > "$TRACEFS/tracing_on" 2>/dev/null
	: > "$TRACEFS/trace" 2>/dev/null
	TRACE_OK=0
}
trace_dump() {
	[ "$TRACE_OK" = 1 ] || return 0
	echo "-- last SPI transfers of $SPIDEV (spi_transfer_stop; tx / rx raw, first 64 bytes; $(grep -c "$SPIDEV " "$TRACEFS/trace" 2>/dev/null) in the buffer):"
	grep "$SPIDEV " "$TRACEFS/trace" 2>/dev/null | tail -n 20 | cut -c1-250 | sed 's/^/   /'
}

cleanup() {
	stop_reader
	if [ "$EXPERIMENTED" = 1 ] && [ ! -e "$SYSFS/bus/spi/devices/$SPIDEV/driver" ]; then
		echo "cleanup: $SPIDEV is not bound: binding it again"
		echo "$SPIDEV" > "$DRVDIR/bind" 2>/dev/null || "$MODPROBE" fts2ba61y 2>/dev/null
	fi
	trace_off
	rm -rf "$W"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

new_dmesg() { # $1 = line count before
	"$DMESG" 2>/dev/null | tail -n +"$(($1 + 1))" > "$W/newlog"
	echo "-- new kernel log lines: $(wc -l < "$W/newlog" | tr -d ' ') ($(grep -c -i -E 'fts|spi|geni|touch|input|panel|regulator|nobody|irq|msm|drm' "$W/newlog") match touch/spi/panel/regulator/irq/drm):"
	grep -i -E 'fts|spi|geni|touch|input|panel|regulator|nobody|irq|msm|drm' "$W/newlog" | cut -c1-200 | head -n 40 | sed 's/^/   /'
}

verdict() { # $1 irq0 $2 irq delta $3 events $4 gpio25-low samples
	if [ "$1" = -1 ]; then echo NO-IRQ-LINE
	elif [ "$3" -gt 0 ]; then echo EVENTS-FLOW
	elif [ "$2" -gt 0 ]; then echo IRQ-COUNTS-NO-EVDEV
	elif [ "$4" -gt 0 ]; then echo IRQ-LINE-LOW-NOT-SERVICED
	else echo CHIP-SILENT; fi
}

phase() { # $1 label $2 seconds
	PH="$1"
	secs="$2"
	say "phase $PH: $secs s -- DRAG A FINGER CONTINUOUSLY until it ends"
	if ! ensure_reader; then
		echo "$PH: no reader: phase skipped"
		echo "$PH NO-DEVICE 0 0 0" >> "$RES"
		LAST_VERDICT=NO-DEVICE
		return 1
	fi
	echo "other holders of $EVDIR/$EVNODE: $(holders)"
	n0=$("$DMESG" 2>/dev/null | wc -l | tr -d ' ')
	irq0=$(irq_count)
	b0=$(evbytes)
	previrq=$irq0
	prevb=$b0
	idle=0
	glow=0
	i=0
	irq=$irq0
	b=$b0
	while [ "$i" -lt "$secs" ]; do
		sleep "$STEP"
		i=$((i + STEP))
		irq=$(irq_count)
		g=$(gpio_level)
		b=$(evbytes)
		if [ "$irq" != "$previrq" ] || [ "$b" != "$prevb" ]; then idle=0; else idle=$((idle + STEP)); fi
		[ "$g" = low ] && glow=$((glow + 1))
		echo "t=$i irq=$irq dirq=$((irq - previrq)) gpio25=$g ev=$(( (b - b0) / 24 ))(+$(( (b - prevb) / 24 ))) idle=${idle}s spi=$(rd "$SYSFS/bus/spi/devices/$SPIDEV/power/runtime_status") se=$(rd "$SYSFS/bus/platform/devices/a90000.spi/power/runtime_status") l12b=$(reg_line "$R12") l16b=$(reg_line "$R16") dsi=$(dsi_line) bl=$(bl_line)"
		previrq=$irq
		prevb=$b
	done
	irqd=$((irq - irq0))
	evd=$(( (b - b0) / 24 ))
	v=$(verdict "$irq0" "$irqd" "$evd" "$glow")
	echo "-- phase $PH: verdict=$v irq_delta=$irqd events=$evd gpio25_low_samples=$glow"
	if [ "$v" = CHIP-SILENT ]; then echo "   (only meaningful if you dragged a finger for the whole window)"; fi
	new_dmesg "$n0"
	trace_dump
	echo "$PH $v $irqd $evd $glow" >> "$RES"
	LAST_VERDICT="$v"
}

experiments() {
	EXPERIMENTED=1
	if [ ! -d "$DRVDIR" ]; then echo "no driver directory $DRVDIR: the experiments are skipped"; return 1; fi
	say "experiment 1/2: rebind $SPIDEV (power cycle of the chip: the driver's remove disables L12B/L16B, probe enables them again and soft-resets)"
	echo "rails before: l12b=$(reg_line "$R12") l16b=$(reg_line "$R16")"
	nx=$("$DMESG" 2>/dev/null | wc -l | tr -d ' ')
	echo "$SPIDEV" > "$DRVDIR/unbind" || echo "unbind failed"
	sleep 1
	echo "rails after unbind: l12b=$(reg_line "$R12") l16b=$(reg_line "$R16")"
	echo "$SPIDEV" > "$DRVDIR/bind" || echo "bind failed"
	sleep 1
	echo "rails after bind: l12b=$(reg_line "$R12") l16b=$(reg_line "$R16")"
	echo "(the probe's own kernel lines, printed here because the next window starts after them)"
	new_dmesg "$nx"
	stop_reader
	phase rebind "$RWIN"
	if [ "$LAST_VERDICT" = EVENTS-FLOW ]; then RECOVERED_BY=rebind; return 0; fi
	say "experiment 2/2: reload the module (modprobe -r fts2ba61y; modprobe fts2ba61y)"
	stop_reader
	nx=$("$DMESG" 2>/dev/null | wc -l | tr -d ' ')
	"$MODPROBE" -r fts2ba61y || echo "modprobe -r failed"
	sleep 1
	"$MODPROBE" fts2ba61y || echo "modprobe failed"
	sleep 1
	echo "(the probe's own kernel lines)"
	new_dmesg "$nx"
	phase modreload "$RWIN"
	if [ "$LAST_VERDICT" = EVENTS-FLOW ]; then RECOVERED_BY=modreload; fi
}

say "touch watch: header"
read -r up _ < "$PROC/uptime" 2>/dev/null
echo "uptime: ${up:-?} s"
echo "kernel: $(uname -r 2>/dev/null)"
if command -v "$SYSTEMCTL" >/dev/null 2>&1; then echo "plasma-mobile.service: $("$SYSTEMCTL" is-active plasma-mobile.service 2>&1)"; fi
echo "input device '$NAME': $(find_ev)"
if [ -z "$(find_ev)" ]; then
	echo "RESULT: NO-DEVICE (the touchscreen's input device does not exist: probe failed or the driver is not loaded)"
	"$DMESG" 2>/dev/null | grep -i -E 'fts2ba61y|spi0|a90000' | tail -n 12 | cut -c1-200 | sed 's/^/   /'
	exit 4
fi
grep -E 'fts2ba61y' "$PROC/interrupts" 2>/dev/null | cut -c1-150
echo "gpio$IRQ_GPIO: $(gpio_level)"
echo "rails: l12b=$(reg_line "$R12") l16b=$(reg_line "$R16")"
trace_on

phase touch "$DUR"
FIRST_VERDICT="$LAST_VERDICT"
if [ "$PHASE_B" -gt 0 ]; then
	say "power key test"
	echo ">>> the next window starts in $COUNTDOWN s: press the POWER KEY once (screen off), wait 5 s, press it again (screen on), then DRAG A FINGER again until the window ends ($PHASE_B s)"
	sleep "$COUNTDOWN"
	phase sleepwake "$PHASE_B"
fi
if [ "$RECOVER" = 1 ]; then
	if [ "$FIRST_VERDICT" = EVENTS-FLOW ]; then
		say "recovery experiments: not needed, events flowed in the touch phase"
	else
		experiments
	fi
fi

say "summary"
while read -r p v d e l; do echo "phase=$p verdict=$v irq_delta=$d events=$e gpio25_low_samples=$l"; done < "$RES"
echo "recovered_by=${RECOVERED_BY:-none}"
echo "first_verdict=$FIRST_VERDICT"
echo
echo "done"
