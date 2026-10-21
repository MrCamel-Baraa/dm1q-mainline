#!/bin/sh
# Phone-side CPU load snapshot (docs/08 section 2.16: "the phone is laggy, top shows a very high CPU usage, and it gets very hot"). POSIX sh, run as root
# (collect-phone-state.sh --load-probe does that). READ-ONLY: it reads procfs / sysfs / the journal and runs `top` in batch mode; it writes nothing, not even a
# temp file, and it never opens /dev/dri/* (it only reads the symlinks of the other processes' file descriptors).
#
# Run it WHILE THE PHONE IS HOT / LAGGY: it samples for WINDOW seconds (default 3) and for about the same again for top, so the numbers are a short average over
# the lag, not the idle phone afterwards. Sections:
#   1 load      loadavg, pressure stall info (cpu / io / memory), number of CPUs, uptime
#   2 cpus      busy / user / system / irq / softirq / iowait percent per CPU over the window (from /proc/stat deltas)
#   3 irqs      the interrupts with the highest rate over the window (an interrupt storm shows here: a stuck level-low line burns a CPU in its irq thread)
#   4 top       the busiest processes (two frames of top -b, the second one counts: the first frame averages since process start), and the busiest threads
#               (top -H, if this top has it); kernel threads (irq/..., kworker/..., ksoftirqd/...) are separate tasks and show up as processes
#   5 session   plasma-mobile.service state and restart count (a crash loop burns CPU), its last journal lines, the stored core dumps
#   6 gpu       which processes hold a /dev/dri node open (a compositor on the GPU holds renderD128; a software renderer does not), the devfreq GPU frequency,
#               the journal lines that name the renderer or a crash, and the kernel lines about stalls / throttling / GPU hangs
#   7 freq/temp the cpufreq policies (current / max frequency, governor) and the hottest thermal zones
# Env (the PC-side test uses them): PROC SYSFS DMESG JOURNALCTL SYSTEMCTL COREDUMPCTL TOP WINDOW TOPD ID_U
PROC="${PROC:-/proc}"
SYSFS="${SYSFS:-/sys}"
DMESG="${DMESG:-dmesg}"
JOURNALCTL="${JOURNALCTL:-journalctl}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
COREDUMPCTL="${COREDUMPCTL:-coredumpctl}"
TOP="${TOP:-top}"
WINDOW="${WINDOW:-3}"
TOPD="${TOPD:-2}"
for kv in WINDOW:$WINDOW TOPD:$TOPD; do
	case "${kv#*:}" in ''|*[!0-9]*) echo "${kv%%:*} must be a number of seconds (got '${kv#*:}')"; exit 2 ;; esac
	[ "${kv#*:}" -ge 1 ] || { echo "${kv%%:*} must be at least 1"; exit 2; }
done
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

say() { echo; echo "== $*"; }
rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }

say "0. when"
echo "date: $(date 2>/dev/null)"
read -r up _ < "$PROC/uptime" 2>/dev/null
echo "uptime: ${up:-?} s   kernel: $(uname -r 2>/dev/null)"

say "1. load"
echo "loadavg (1 / 5 / 15 min, running/total tasks): $(cut -d' ' -f1-4 "$PROC/loadavg" 2>/dev/null)"
echo "cpus: $(grep -c '^processor' "$PROC/cpuinfo" 2>/dev/null)"
for p in cpu io memory; do
	[ -r "$PROC/pressure/$p" ] && sed "s/^/pressure $p: /" "$PROC/pressure/$p"
done

STAT1=$(grep '^cpu' "$PROC/stat" 2>/dev/null)
INT1=$(cat "$PROC/interrupts" 2>/dev/null)
sleep "$WINDOW"
STAT2=$(grep '^cpu' "$PROC/stat" 2>/dev/null)
INT2=$(cat "$PROC/interrupts" 2>/dev/null)

say "2. cpus over the last ${WINDOW} s (percent of the window)"
printf '%s\n----\n%s\n' "$STAT1" "$STAT2" | awk '
/^----$/ { blk = 2; next }
$1 ~ /^cpu/ {
	tot = 0
	for (i = 2; i <= 9 && i <= NF; i++) tot += $i
	if (blk != 2) { T0[$1] = tot; ID0[$1] = $5; W0[$1] = $6; U0[$1] = $2 + $3; S0[$1] = $4; Q0[$1] = $7; O0[$1] = $8 }
	else {
		dt = tot - T0[$1]
		if (dt <= 0) next
		printf "%s busy=%.0f%% user=%.0f%% sys=%.0f%% irq=%.0f%% softirq=%.0f%% iowait=%.0f%%\n", $1, 100 * (dt - ($5 - ID0[$1]) - ($6 - W0[$1])) / dt, 100 * (($2 + $3) - U0[$1]) / dt, 100 * ($4 - S0[$1]) / dt, 100 * ($7 - Q0[$1]) / dt, 100 * ($8 - O0[$1]) / dt, 100 * ($6 - W0[$1]) / dt
	}
}' | sed 's/^/   /'

say "3. interrupts with the highest rate over the last ${WINDOW} s (per second; top 10)"
printf '%s\n----\n%s\n' "$INT1" "$INT2" | awk -v win="$WINDOW" '
function parse(   s, i) { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } LBL = ""; for (; i <= NF; i++) LBL = LBL (LBL == "" ? "" : " ") $i; return s }
/^----$/ { blk = 2; next }
$1 ~ /^CPU/ { next }
{ s = parse(); if (blk != 2) C0[$1] = s; else if (($1 in C0) && s > C0[$1]) printf "%.1f/s %s %s\n", (s - C0[$1]) / win, $1, substr(LBL, 1, 60) }' | sort -rn | head -n 10 | sed 's/^/   /'

top_last() { # $1 = "" or "-H"
	if [ -n "$1" ]; then _t=$("$TOP" -b "$1" -n 2 -d "$TOPD" 2>&1); else _t=$("$TOP" -b -n 2 -d "$TOPD" 2>&1); fi
	printf '%s\n' "$_t" | awk '/^(top - |Mem:)/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }'
}
say "4. top: busiest processes (second frame of two, ${TOPD} s apart)"
top_last "" | head -n 30 | cut -c1-200
echo "-- top -H: busiest threads (if this top supports it)"
_th=$(top_last "-H")
if printf '%s\n' "$_th" | grep -q 'PID'; then printf '%s\n' "$_th" | head -n 30 | cut -c1-200; else echo "(top -H is not supported here)"; fi

say "5. session: plasma-mobile.service"
"$SYSTEMCTL" show plasma-mobile.service -p ActiveState -p SubState -p NRestarts -p MainPID -p ActiveEnterTimestamp -p Result 2>&1 | head -n 8
echo "-- last 15 journal lines of the unit:"
"$JOURNALCTL" -b --no-pager -u plasma-mobile.service 2>/dev/null | tail -n 15 | cut -c1-220 | sed 's/^/   /'
echo "-- stored core dumps (last 8):"
"$COREDUMPCTL" list --no-pager 2>&1 | tail -n 8 | cut -c1-200 | sed 's/^/   /'

say "6. GPU path"
echo "processes holding a /dev/dri node (count / name / node):"
for p in "$PROC"/[0-9]*; do
	[ -d "$p/fd" ] || continue
	for f in "$p"/fd/*; do
		_l=$(readlink "$f" 2>/dev/null)
		case "$_l" in /dev/dri/*) echo "$(rd "$p/comm") $_l" ;; esac
	done
done | sort | uniq -c | sed 's/^/   /'
for g in "$SYSFS"/class/devfreq/*; do
	[ -d "$g" ] && echo "devfreq $(basename "$g"): cur=$(rd "$g/cur_freq") max=$(rd "$g/max_freq") governor=$(rd "$g/governor")"
done
echo "journal (this boot): renderer / crash lines (last 30):"
"$JOURNALCTL" -b --no-pager 2>/dev/null | grep -i -E 'llvmpipe|softpipe|freedreno|zink|renderer|EGL|SIGILL|SIGSEGV|segfault|dumped core|watchdog|not responding' | tail -n 30 | cut -c1-220 | sed 's/^/   /'
echo "kernel log: stalls / throttling / hung tasks / GPU faults (last 25):"
"$DMESG" 2>/dev/null | grep -i -E 'rcu|stall|hung task|soft lockup|thermal|throttl|cpufreq|oom|adreno|a6xx|a7xx|gmu|gpu fault|gpu hang|recover|hfi' | tail -n 25 | cut -c1-200 | sed 's/^/   /'

say "7. cpufreq and temperatures"
for pol in "$SYSFS"/devices/system/cpu/cpufreq/policy*; do
	[ -d "$pol" ] || continue
	echo "$(basename "$pol"): cur=$(rd "$pol/scaling_cur_freq") min=$(rd "$pol/scaling_min_freq") max=$(rd "$pol/scaling_max_freq") hw_max=$(rd "$pol/cpuinfo_max_freq") governor=$(rd "$pol/scaling_governor") cpus=$(rd "$pol/related_cpus")"
done
echo "hottest thermal zones (degrees C, top 8):"
for z in "$SYSFS"/class/thermal/thermal_zone*; do
	[ -d "$z" ] || continue
	echo "$(rd "$z/temp") $(rd "$z/type")"
done | sort -rn | head -n 8 | awk '{ printf "   %.1f %s\n", $1 / 1000, $2 }'

echo
echo "done"
