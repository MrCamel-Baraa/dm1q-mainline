#!/bin/sh
# Phone-side: read and set the debugfs instruments of kernel patch 0005 (package r11, docs/08 2.26), POSIX sh, run as root
# (collect-phone-state.sh --touch-stats / --touch-set= do that). Files in /sys/kernel/debug/spi0.0/:
#   stats          counters: irqs polls events press move release overflow errors stalls stall_after_none/press/move/release
#   stats_reset    write anything: all counters back to 0
#   poll_ms        0 = off. Else: after that many ms without an interrupt, read the event queue once. An interrupt right after an
#                  empty read, or events in the read, count as one stall (stalls, stall_after_*); the read also recovers the touch.
#   read_delay_us  wait this long before the first read of every interrupt (tests the race of docs/08 2.24, H11)
#   speed_hz       the SPI clock (tests H14); the DT value is the default
# Env: SET="poll_ms=150,read_delay_us=300" (applied first, in that order), RESET=1 (counters to 0 after printing them),
#      DEBUGFS DEV ID_U (the PC-side test uses them).
# Output: the knobs, the counters, and per 1000 touch-downs: stalls and overflow. "overflow" is the number of reads that found the queue
# full (left = 31), i.e. stalls the interrupt path ran into by itself; "stalls" is what the poll found (poll_ms > 0 only).
DEBUGFS="${DEBUGFS:-/sys/kernel/debug}"
DEV="${DEV:-spi0.0}"
D="$DEBUGFS/$DEV"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }
[ -r "$D/stats" ] || { echo "ABORT: $D/stats is missing (kernel patch 0005 / package r11 is not running, or debugfs is not mounted)"; exit 3; }

put() {
	# put FILE VALUE: busybox printf can exit non-zero without a message, dd names the errno
	if ! _e=$(printf '%s\n' "$2" | dd of="$D/$1" bs=64 2>&1 >/dev/null); then
		echo "ERROR: writing $2 to $1 failed: $(printf '%s' "$_e" | tail -n 1)"
		return 1
	fi
	return 0
}
rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }

rc=0
if [ -n "${SET:-}" ]; then
	_old_ifs="$IFS"
	IFS=,
	# shellcheck disable=SC2086
	set -- $SET
	IFS="$_old_ifs"
	for kv in "$@"; do
		k="${kv%%=*}"
		v="${kv#*=}"
		case "$k" in
			poll_ms|read_delay_us|speed_hz) ;;
			*) echo "ERROR: unknown knob '$k' (poll_ms, read_delay_us, speed_hz)"; rc=2; continue ;;
		esac
		case "$v" in ''|*[!0-9]*) echo "ERROR: $k needs a number (got '$v')"; rc=2; continue ;; esac
		put "$k" "$v" && echo "set $k=$v" || rc=4
	done
fi

echo "knobs: poll_ms=$(rd "$D/poll_ms") read_delay_us=$(rd "$D/read_delay_us") speed_hz=$(rd "$D/speed_hz")"
echo "counters:"
sed 's/^/  /' "$D/stats"
awk '
	$1 == "press" { press = $2 } $1 == "stalls" { stalls = $2 } $1 == "overflow" { overflow = $2 }
	END {
		if (press + 0 > 0)
			printf "per 1000 touch-downs (%d touch-downs): stalls %.2f, overflow %.2f\n", press, stalls * 1000 / press, overflow * 1000 / press
		else
			print "no touch-downs counted yet"
	}' "$D/stats"

if [ "${RESET:-0}" = 1 ]; then
	put stats_reset 1 && echo "counters reset" || rc=4
fi
exit "$rc"
