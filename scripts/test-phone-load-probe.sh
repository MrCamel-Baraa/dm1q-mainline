#!/usr/bin/env bash
# PC-side test of scripts/phone-load-probe.sh (docs/06 rule 3). Fake /proc and /sys trees, stubs for top / systemctl / journalctl / coredumpctl / dmesg, and a
# background SIMULATOR that advances /proc/stat and /proc/interrupts in whole ticks (cpu0 80 % busy, cpu1 idle, irq 178 firing 10x more than irq 7), so the
# per-CPU percentages and the interrupt rates have exact expected values. Checks: every section, the busy / user / sys percentages, the interrupt ranking, only the
# LAST frame of top, the -H fallback, the processes holding a /dev/dri node (symlinks only), the unit state, the filtered journal / kernel lines, cpufreq and the
# hottest zone first, READ-ONLY (no file under the fake tree changes), refusals, and that the script never opens a /dev/dri node. Run with bash.
# Usage: bash scripts/test-phone-load-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-load-probe.sh"
W="$(mktemp -d)"
SIMPID=""
finish() { [ -n "$SIMPID" ] && kill "$SIMPID" 2>/dev/null; rm -rf "$W"; }
trap finish EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

D="$W/fake"
mkdir -p "$D/bin" "$D/proc/pressure" "$D/proc/321/fd" "$D/proc/322/fd" "$D/sys/class/devfreq/3d00000.gpu" "$D/sys/devices/system/cpu/cpufreq/policy0" \
	"$D/sys/class/thermal/thermal_zone0" "$D/sys/class/thermal/thermal_zone1"
echo "1234.56 9999.00" > "$D/proc/uptime"; echo "7.10 5.20 3.30 4/200 999" > "$D/proc/loadavg"
printf 'processor\t: 0\nprocessor\t: 1\n' > "$D/proc/cpuinfo"
echo "some avg10=41.00 avg60=30.00 avg300=20.00 total=123" > "$D/proc/pressure/cpu"
echo "some avg10=0.00 avg60=0.00 avg300=0.00 total=0" > "$D/proc/pressure/io"
echo kwin_wayland > "$D/proc/321/comm"; ln -s /dev/dri/renderD128 "$D/proc/321/fd/3"; ln -s /dev/null "$D/proc/321/fd/4"
echo plasmashell > "$D/proc/322/comm"; ln -s /dev/dri/card1 "$D/proc/322/fd/4"
echo 680000000 > "$D/sys/class/devfreq/3d00000.gpu/cur_freq"; echo 770000000 > "$D/sys/class/devfreq/3d00000.gpu/max_freq"; echo msm-adreno-tz > "$D/sys/class/devfreq/3d00000.gpu/governor"
echo 2000000 > "$D/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq"; echo 2800000 > "$D/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
echo schedutil > "$D/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"; echo "0 1" > "$D/sys/devices/system/cpu/cpufreq/policy0/related_cpus"
echo cpu-a > "$D/sys/class/thermal/thermal_zone0/type"; echo 85000 > "$D/sys/class/thermal/thermal_zone0/temp"
echo gpu > "$D/sys/class/thermal/thermal_zone1/type"; echo 70500 > "$D/sys/class/thermal/thermal_zone1/temp"
cat > "$D/dmesg" <<'EOF'
[   10.000000] ordinary line
[  500.000000] msm_dpu: adreno gpu hang detected, recovering
[  600.000000] thermal thermal_zone0: throttling the cpu
EOF
printf '#!/bin/sh\ncat "%s/dmesg"\n' "$D" > "$D/bin/dmesg"
cat > "$D/bin/journalctl" <<'EOF'
#!/bin/sh
case "$*" in
*-u\ plasma-mobile.service*) echo "Oct 22 01:00:00 phone systemd[1]: Started plasma-mobile.service." ;;
*) echo "Oct 22 01:00:01 phone kwin_wayland[321]: using renderer llvmpipe"
   echo "Oct 22 01:00:02 phone kernel: unrelated message" ;;
esac
EOF
printf '#!/bin/sh\nprintf "ActiveState=active\\nSubState=running\\nNRestarts=7\\nMainPID=300\\n"\n' > "$D/bin/systemctl"
printf '#!/bin/sh\necho "TIME PID UID GID SIG COREFILE EXE"\necho "Thu 2026-10-22 00:59 400 10000 10000 SIGSEGV present /usr/bin/plasmashell"\n' > "$D/bin/coredumpctl"
cat > "$D/bin/top" <<'EOF'
#!/bin/sh
H=""
for a in "$@"; do [ "$a" = -H ] && H=1; done
if [ -n "$H" ] && [ -e "$(dirname "$0")/noH" ]; then echo "top: unknown option 'H'"; exit 1; fi
for f in 1 2; do
	echo "Mem: 1000K used, 2000K free, 0K shrd"
	echo "CPU:  80% usr  10% sys   0% nic  10% idle"
	echo "  PID  PPID USER     STAT   VSZ %VSZ %CPU COMMAND"
	if [ -n "$H" ]; then echo "  300     1 user     R     1000   1%  95% THREAD_FRAME$f"; else echo "  200     1 user     R     1000   1%  90% PROC_FRAME$f"; fi
done
EOF
chmod +x "$D/bin/dmesg" "$D/bin/journalctl" "$D/bin/systemctl" "$D/bin/coredumpctl" "$D/bin/top"

sim() { # per tick (0.1 s): cpu0 +70 user +10 sys +20 idle; cpu1 +100 idle; irq 178 +30, irq 7 +1. Counters are written whole, so the window deltas are exact multiples.
	(
		u0=1000; s0=1000; i0=1000; i1=1000; a=1000; b=1000
		while :; do
			sleep 0.1
			u0=$((u0 + 70)); s0=$((s0 + 10)); i0=$((i0 + 20)); i1=$((i1 + 100)); a=$((a + 30)); b=$((b + 1))
			printf 'cpu  %d 0 %d %d 0 0 0 0 0 0\ncpu0 %d 0 %d %d 0 0 0 0 0 0\ncpu1 1000 0 1000 %d 0 0 0 0 0 0\nintr 1\n' $((u0 + 1000)) $((s0 + 1000)) $((i0 + i1)) "$u0" "$s0" "$i0" "$i1" > "$D/proc/stat.tmp" && mv "$D/proc/stat.tmp" "$D/proc/stat"
			printf '           CPU0       CPU1\n   7:  %d  0  GICv3  27 Level     arch_timer\n 178:  %d  0  msmgpio  25 Level     fts2ba61y\n' "$b" "$a" > "$D/proc/interrupts.tmp" && mv "$D/proc/interrupts.tmp" "$D/proc/interrupts"
		done
	) &
	SIMPID=$!
}
printf 'cpu  1 0 1 1 0 0 0 0 0 0\ncpu0 1 0 1 1 0 0 0 0 0 0\ncpu1 1 0 1 1 0 0 0 0 0 0\n' > "$D/proc/stat"
printf '           CPU0       CPU1\n   7:  1  0  GICv3  27 Level     arch_timer\n 178:  1  0  msmgpio  25 Level     fts2ba61y\n' > "$D/proc/interrupts"

run() {
	timeout 60 env PROC="$D/proc" SYSFS="$D/sys" DMESG="$D/bin/dmesg" JOURNALCTL="$D/bin/journalctl" SYSTEMCTL="$D/bin/systemctl" COREDUMPCTL="$D/bin/coredumpctl" \
		TOP="$D/bin/top" WINDOW=1 TOPD=1 ID_U="${ID_U_T-0}" "$@" bash "$SCRIPT" > "$W/out" 2>&1
}
snap() { (cd "$D" && find . -type f -not -path ./proc/stat -not -path ./proc/interrupts -not -name '*.tmp' -print0 | sort -z | xargs -0 -r cksum); }

before=$(snap)
echo "== run as root, phone hot"
sim
sleep 0.4
run; rc=$?; O="$W/out"
kill "$SIMPID" 2>/dev/null; wait "$SIMPID" 2>/dev/null; SIMPID=""
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
for s in "0. when" "1. load" "2. cpus" "3. interrupts" "4. top" "5. session" "6. GPU path" "7. cpufreq and temperatures"; do
	expect "$O" "section '$s'" "^== $s"
done
expect "$O" "loadavg" "^loadavg .*: 7.10 5.20 3.30 4/200"
expect "$O" "cpu count" "^cpus: 2"
expect "$O" "pressure" "^pressure cpu: some avg10=41.00"
expect "$O" "cpu0 80 % busy, 70 % user, 10 % sys" "^   cpu0 busy=80% user=70% sys=10% irq=0% softirq=0% iowait=0%"
expect "$O" "cpu1 idle" "^   cpu1 busy=0% "
expect "$O" "total line" "^   cpu busy=40% user=35% sys=5% "
expect "$O" "irq 178 listed with its label" "^   [0-9.]+/s 178: .*fts2ba61y"
[ "$(grep -n -E '^   [0-9.]+/s 178:' "$O" | cut -d: -f1)" -lt "$(grep -n -E '^   [0-9.]+/s 7:' "$O" | cut -d: -f1)" ] && ok "the busier interrupt is listed first" || bad "interrupt order"
expect "$O" "top: the last frame" "PROC_FRAME2"
reject "$O" "top: the first frame is dropped" "PROC_FRAME1"
expect "$O" "top -H: the last frame" "THREAD_FRAME2"
reject "$O" "top -H: the first frame is dropped" "THREAD_FRAME1"
expect "$O" "unit state with the restart count" "^NRestarts=7"
expect "$O" "unit journal" "Started plasma-mobile.service"
expect "$O" "core dump list" "SIGSEGV present /usr/bin/plasmashell"
expect "$O" "dri holder 1" "^ +1 kwin_wayland /dev/dri/renderD128"
expect "$O" "dri holder 2" "^ +1 plasmashell /dev/dri/card1"
reject "$O" "a non-dri descriptor is ignored" "/dev/null"
expect "$O" "devfreq" "^devfreq 3d00000.gpu: cur=680000000 max=770000000 governor=msm-adreno-tz"
expect "$O" "renderer line" "using renderer llvmpipe"
reject "$O" "journal: unrelated line filtered" "unrelated message"
expect "$O" "kernel: gpu hang" "adreno gpu hang detected"
expect "$O" "kernel: throttling" "throttling the cpu"
reject "$O" "kernel: ordinary line filtered" "ordinary line"
expect "$O" "cpufreq" "^policy0: cur=2000000 min= max=2800000 hw_max= governor=schedutil cpus=0 1"
expect "$O" "hottest zone first" "^   85.0 cpu-a"
[ "$(grep -n -E '^   85.0 cpu-a' "$O" | cut -d: -f1)" -lt "$(grep -n -E '^   70.5 gpu' "$O" | cut -d: -f1)" ] && ok "zones sorted hottest first" || bad "thermal order"
expect "$O" "done" "^done"
after=$(snap)
if [ "$before" = "$after" ]; then ok "READ-ONLY: no file of the fake tree changed"; else bad "the probe changed something"; diff <(echo "$before") <(echo "$after") | head -n 10; fi

echo "== top without -H"
: > "$D/bin/noH"
run
expect "$W/out" "fallback message" "^\(top -H is not supported here\)"
reject "$W/out" "no thread frame" "THREAD_FRAME"
expect "$W/out" "the process frame is still there" "PROC_FRAME2"

echo "== refusals"
ID_U_T=1 run; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
run WINDOW=abc; rc=$?
[ "$rc" = 2 ] && ok "bad WINDOW: exit 2" || bad "bad WINDOW: exit $rc"
run WINDOW=0; rc=$?
[ "$rc" = 2 ] && ok "WINDOW=0: exit 2" || bad "WINDOW=0: exit $rc"

echo "== static checks"
bash --posix -n "$SCRIPT" && ok "bash --posix -n" || bad "bash --posix -n"
if grep -n '/dev/dri' "$SCRIPT" | grep -v -E '^[0-9]+:#' | grep -v -E 'case "\$_l" in /dev/dri|processes holding a /dev/dri' >/dev/null; then bad "the script uses /dev/dri other than in the symlink check"; else ok "/dev/dri only appears in the symlink check (never opened)"; fi
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
