#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-watch.sh (docs/06 rule 3). A fake /proc, /sys (regulators, spi/platform devices, drm, backlight, the fts2ba61y driver's
# unbind/bind files), a fake evdev node, a fake tracefs with spi_transfer_stop, stubs for dmesg / modprobe / mount / systemctl, and a background SIMULATOR that
# plays the chip: live (events flow), silent, irq-counts-but-no-evdev, gpio25-low, "a rebind brings it back", "a module reload brings it back", "nothing helps".
# Checks: every verdict, the experiments only run with RECOVER=1 and only when the touch phase was not EVENTS-FLOW, they stop at the first success, the
# device is left bound, the tracefs controls are enabled during the run and restored after it, TRACE=0 touches nothing, no /dev/dri, the reader and the temp
# dir are gone after normal exit AND after SIGTERM, refusals (no device, not root, bad numbers). Run with bash (dash / busybox are not installed here;
# `bash --posix -n` and shellcheck -s sh cover the portability). Usage: bash scripts/test-phone-touch-watch.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-watch.sh"
W="$(mktemp -d)"
SIMPID=""
finish() { [ -n "$SIMPID" ] && kill "$SIMPID" 2>/dev/null; rm -rf "$W"; }
trap finish EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

TRACELINE='   kworker/u16:3-123 [001] ..... 100.100000: spi_transfer_stop: spi0.0 000000001234 len=18 tx=[87 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00] rx=[00 87 49 00 10 00 00 00 00 00 00 00 00 00 00 00 00 00]'

mk() { # $1 = dir
	local D="$1" T
	rm -rf "$D"
	T="$D/sys/kernel/tracing"
	mkdir -p "$D/bin" "$D/tmp" "$D/proc/bus/input" "$D/sys/kernel/debug" "$D/sys/class/regulator/regulator.1" "$D/sys/class/regulator/regulator.2" \
		"$D/sys/bus/spi/devices/spi0.0/power" "$D/sys/bus/platform/devices/a90000.spi/power" "$D/sys/bus/spi/drivers/fts2ba61y" \
		"$D/sys/class/drm/card1-DSI-1" "$D/sys/class/backlight/ae94000.dsi.0" "$D/dev/input" "$T/events/spi/spi_transfer_stop"
	cat > "$D/proc/bus/input/devices" <<'EOF'
I: Bus=0019 Vendor=0001 Product=0001 Version=0100
N: Name="gpio-keys"
P: Phys=gpio-keys/input0
S: Sysfs=/devices/platform/gpio-keys/input/input0
U: Uniq=
H: Handlers=kbd event0 
B: PROP=0

I: Bus=001c Vendor=0000 Product=0000 Version=0000
N: Name="STMicroelectronics FTS2BA61Y Touchscreen"
P: Phys=
S: Sysfs=/devices/platform/soc@0/ac0000.geniqup/a90000.spi/spi_master/spi0/spi0.0/input/input3
U: Uniq=
H: Handlers=event3 
B: PROP=2
EOF
	printf '  7:          0          0          0          0          0          0          0          0  GICv3  27 Level     arch_timer\n 178:          0          0          0          0          0          0          0          0  msmgpio  25 Level     fts2ba61y\n' > "$D/proc/interrupts"
	echo "1234.56 9999.00" > "$D/proc/uptime"
	printf ' gpio24  : in  high func0 2mA no pull\n gpio25  : in  high func0 2mA no pull\n' > "$D/sys/kernel/debug/gpio"
	echo vreg_l12b_1p8 > "$D/sys/class/regulator/regulator.1/name"; echo enabled > "$D/sys/class/regulator/regulator.1/state"
	echo 1800000 > "$D/sys/class/regulator/regulator.1/microvolts"; echo 1 > "$D/sys/class/regulator/regulator.1/num_users"
	echo vreg_l16b_3p0 > "$D/sys/class/regulator/regulator.2/name"; echo enabled > "$D/sys/class/regulator/regulator.2/state"
	echo 3000000 > "$D/sys/class/regulator/regulator.2/microvolts"; echo 1 > "$D/sys/class/regulator/regulator.2/num_users"
	echo active > "$D/sys/bus/spi/devices/spi0.0/power/runtime_status"
	echo suspended > "$D/sys/bus/platform/devices/a90000.spi/power/runtime_status"
	: > "$D/sys/bus/spi/devices/spi0.0/driver"
	: > "$D/sys/bus/spi/drivers/fts2ba61y/unbind"; : > "$D/sys/bus/spi/drivers/fts2ba61y/bind"
	echo 1 > "$D/sys/class/drm/card1-DSI-1/enabled"; echo On > "$D/sys/class/drm/card1-DSI-1/dpms"
	echo 0 > "$D/sys/class/backlight/ae94000.dsi.0/bl_power"; echo 1234 > "$D/sys/class/backlight/ae94000.dsi.0/brightness"
	: > "$D/dev/input/event3"
	echo 0 > "$T/events/spi/spi_transfer_stop/enable"; echo none > "$T/events/spi/spi_transfer_stop/filter"; echo 1 > "$T/tracing_on"
	{ echo '# tracer: nop'; echo "$TRACELINE"; echo "$TRACELINE"; echo "$TRACELINE"; } > "$T/trace"
	printf '[    1.000000] spi_geni_qcom a90000.spi: ok\n[    7.700000] fts2ba61y spi0.0: id 53 54 40 36 01, resolution 4095x4095, 16 TX x 34 RX channels\n' > "$D/dmesg"
	cat > "$D/bin/dmesg" <<EOF
#!/bin/sh
cat "$D/dmesg"
EOF
	cat > "$D/bin/modprobe" <<EOF
#!/bin/sh
echo "\$*" >> "$D/modprobe.log"
case "\$1" in -r) ;; *) [ "\$(cat "$D/mode" 2>/dev/null)" = modfix ] && : > "$D/alive" ;; esac
exit 0
EOF
	cat > "$D/bin/mount" <<EOF
#!/bin/sh
echo "\$*" >> "$D/mount.log"
EOF
	printf '#!/bin/sh\necho active\n' > "$D/bin/systemctl"
	chmod +x "$D/bin/dmesg" "$D/bin/modprobe" "$D/bin/mount" "$D/bin/systemctl"
}

sim() { # $1 dir $2 mode: live | silent | irqonly | gpulow | rebindfix | modfix | nofix
	local D="$1" mode="$2"
	echo "$mode" > "$D/mode"
	case "$mode" in live|irqonly) : > "$D/alive" ;; esac
	[ "$mode" = gpulow ] && printf ' gpio25  : in  low  func0 2mA no pull\n' > "$D/sys/kernel/debug/gpio"
	(
		cnt=0; logged=0
		T="$D/sys/kernel/tracing/events/spi/spi_transfer_stop"
		while :; do
			sleep 0.2
			if [ "$mode" = rebindfix ] && [ -s "$D/sys/bus/spi/drivers/fts2ba61y/bind" ]; then
				: > "$D/alive"
				if [ "$logged" = 0 ]; then echo '[   99.000000] fts2ba61y spi0.0: id 53 54 40 36 01, resolution 4095x4095, 16 TX x 34 RX channels' >> "$D/dmesg"; logged=1; fi
			fi
			if [ -e "$D/alive" ]; then
				cnt=$((cnt + 3))
				printf ' 178: %10d          0          0          0          0          0          0          0  msmgpio  25 Level     fts2ba61y\n' "$cnt" > "$D/proc/interrupts.tmp" && mv "$D/proc/interrupts.tmp" "$D/proc/interrupts"
				[ "$mode" != irqonly ] && head -c 48 /dev/zero >> "$D/dev/input/event3"
			fi
			if [ "$(cat "$T/enable" 2>/dev/null)" = 1 ]; then echo 1 > "$D/seen-enable"; cat "$T/filter" > "$D/seen-filter"; echo "$TRACELINE" >> "$D/sys/kernel/tracing/trace"; fi
		done
	) &
	SIMPID=$!
}
unsim() { [ -n "$SIMPID" ] && { kill "$SIMPID" 2>/dev/null; wait "$SIMPID" 2>/dev/null; }; SIMPID=""; }

go() { # $1 dir, rest = VAR=value assignments
	local D="$1"; shift
	timeout 150 env SYSFS="$D/sys" PROC="$D/proc" DEBUGFS="$D/sys/kernel/debug" DMESG="$D/bin/dmesg" EVDIR="$D/dev/input" READER="tail -n +1 -f" \
		MODPROBE="$D/bin/modprobe" MOUNT="$D/bin/mount" SYSTEMCTL="$D/bin/systemctl" TMPDIR="$D/tmp" ID_U="${ID_U_T-0}" DUR=3 RWIN=3 COUNTDOWN=0 \
		"$@" bash "$SCRIPT" > "$D/out" 2>&1
}
scenario() { # $1 name $2 mode, rest = env assignments; sets D and rc
	local name="$1" mode="$2"; shift 2
	D="$W/$name"; mk "$D"; sim "$D" "$mode"
	go "$D" "$@"; rc=$?
	unsim
}
trace_restored() { [ "$(cat "$1/sys/kernel/tracing/events/spi/spi_transfer_stop/enable")" = 0 ] && [ "$(cat "$1/sys/kernel/tracing/tracing_on")" = 1 ]; }
no_leftovers() { # $1 dir
	if pgrep -f "tail -n +1 -f $1/dev/input/event3" >/dev/null 2>&1; then return 1; fi
	[ -z "$(ls -A "$1/tmp" 2>/dev/null)" ]
}

echo "== live: events flow (RECOVER=1 must not run anything)"
scenario live live RECOVER=1; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "header: device found" "^input device 'STMicroelectronics FTS2BA61Y Touchscreen': event3"
expect "$O" "header: plasma service state" "^plasma-mobile.service: active"
expect "$O" "per-second line has all the columns" "^t=[0-9]+ irq=[0-9]+ dirq=[0-9]+ gpio25=high ev=[0-9]+\(\+[0-9]+\) idle=[0-9]+s spi=active se=suspended l12b=enabled:1800000uV:users=1 l16b=enabled:3000000uV:users=1 dsi=1/On bl=0/1234"
expect "$O" "verdict EVENTS-FLOW" "^-- phase touch: verdict=EVENTS-FLOW irq_delta=[1-9][0-9]* events=[1-9][0-9]*"
expect "$O" "no experiment needed" "recovery experiments: not needed"
[ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/unbind" ] && [ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/bind" ] && ok "unbind / bind never written" || bad "unbind / bind written"
[ ! -e "$D/modprobe.log" ] && ok "modprobe never called" || bad "modprobe called"
expect "$O" "SPI trace lines printed with the raw rx bytes" "rx=\[00 87 49 00 10"
expect "$O" "trace buffer count" "[1-9][0-9]* in the buffer"
[ -e "$D/seen-enable" ] && ok "the tracepoint was enabled during the run" || bad "tracepoint never enabled"
grep -q 'bus_num == 0 && chip_select == 0' "$D/seen-filter" && ok "filter bus 0 / cs 0 set during the run" || bad "filter not set"
trace_restored "$D" && ok "trace enable and tracing_on restored" || bad "trace controls not restored"
[ ! -e "$D/mount.log" ] && ok "tracefs already there: no mount" || bad "mount called"
no_leftovers "$D" && ok "reader killed, temp dir removed" || bad "leftover reader or temp files"
expect "$O" "summary line" "^phase=touch verdict=EVENTS-FLOW"
expect "$O" "recovered_by=none" "^recovered_by=none"

echo "== silent chip, RECOVER=0: verdict only"
scenario silent silent RECOVER=0; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "verdict CHIP-SILENT" "^-- phase touch: verdict=CHIP-SILENT irq_delta=0 events=0 gpio25_low_samples=0"
expect "$O" "the 'were you dragging' caveat" "only meaningful if you dragged a finger"
expect "$O" "idle counter grows" "idle=3s"
[ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/unbind" ] && [ ! -e "$D/modprobe.log" ] && ok "no experiment without RECOVER=1" || bad "experiment ran without RECOVER=1"
trace_restored "$D" && ok "trace restored" || bad "trace not restored"
no_leftovers "$D" && ok "no leftovers" || bad "leftovers"

echo "== interrupt counts, no evdev bytes"
scenario irqonly irqonly RECOVER=0; O="$D/out"
expect "$O" "verdict IRQ-COUNTS-NO-EVDEV" "^-- phase touch: verdict=IRQ-COUNTS-NO-EVDEV irq_delta=[1-9][0-9]* events=0"

echo "== gpio25 low, nothing serviced"
scenario gpulow gpulow RECOVER=0; O="$D/out"
expect "$O" "verdict IRQ-LINE-LOW-NOT-SERVICED" "^-- phase touch: verdict=IRQ-LINE-LOW-NOT-SERVICED irq_delta=0 events=0 gpio25_low_samples=3"
expect "$O" "gpio25=low in the lines" "gpio25=low"

echo "== a rebind brings it back"
scenario rebindfix rebindfix RECOVER=1; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "touch phase was silent" "^-- phase touch: verdict=CHIP-SILENT"
expect "$O" "rails shown around the unbind" "^rails after unbind: l12b="
[ "$(cat "$D/sys/bus/spi/drivers/fts2ba61y/unbind")" = spi0.0 ] && [ "$(cat "$D/sys/bus/spi/drivers/fts2ba61y/bind")" = spi0.0 ] && ok "spi0.0 written to unbind, then bind" || bad "unbind / bind contents"
expect "$O" "rebind phase EVENTS-FLOW" "^-- phase rebind: verdict=EVENTS-FLOW"
expect "$O" "new kernel line shown" "fts2ba61y spi0.0: id 53 54 40 36 01"
[ ! -e "$D/modprobe.log" ] && ok "stops at the first success: no module reload" || bad "module reload ran after a success"
expect "$O" "recovered_by=rebind" "^recovered_by=rebind"
expect "$O" "first_verdict kept" "^first_verdict=CHIP-SILENT"
no_leftovers "$D" && ok "no leftovers" || bad "leftovers"

echo "== a module reload brings it back"
scenario modfix modfix RECOVER=1; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "rebind phase did not help" "^-- phase rebind: verdict=CHIP-SILENT"
[ "$(sed -n 1p "$D/modprobe.log")" = "-r fts2ba61y" ] && [ "$(sed -n 2p "$D/modprobe.log")" = "fts2ba61y" ] && [ "$(wc -l < "$D/modprobe.log")" = 2 ] && ok "modprobe -r fts2ba61y then modprobe fts2ba61y, nothing else" || bad "modprobe calls: $(cat "$D/modprobe.log")"
expect "$O" "modreload phase EVENTS-FLOW" "^-- phase modreload: verdict=EVENTS-FLOW"
expect "$O" "recovered_by=modreload" "^recovered_by=modreload"

echo "== nothing helps"
scenario nofix nofix RECOVER=1; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "recovered_by=none" "^recovered_by=none"
expect "$O" "both experiments ran" "^-- phase modreload: verdict=CHIP-SILENT"
no_leftovers "$D" && ok "no leftovers" || bad "leftovers"

echo "== left unbound after the experiments: cleanup binds it again"
D="$W/unb"; mk "$D"; sim "$D" nofix; rm -f "$D/sys/bus/spi/devices/spi0.0/driver"
go "$D" RECOVER=1; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "cleanup message" "^cleanup: spi0.0 is not bound: binding it again"

echo "== power key window"
scenario sw live PHASE_B=3 RECOVER=0; O="$D/out"
expect "$O" "prompt printed" "press the POWER KEY once \(screen off\), wait 5 s"
expect "$O" "sleepwake phase ran" "^-- phase sleepwake: verdict=EVENTS-FLOW"
expect "$O" "both phases in the summary" "^phase=sleepwake verdict=EVENTS-FLOW"

echo "== TRACE=0 touches no tracefs control"
D="$W/t0"; mk "$D"; sim "$D" live
b=$(cd "$D/sys/kernel/tracing" && find . -type f -exec cksum {} + | sort)
go "$D" TRACE=0; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
[ "$b" = "$(cd "$D/sys/kernel/tracing" && find . -type f -exec cksum {} + | sort)" ] && ok "tracefs files unchanged" || bad "tracefs changed"
expect "$O" "says so" "^trace: off"
reject "$O" "no trace dump" "last SPI transfers"

echo "== tracefs missing: skipped, mounted once"
D="$W/nt"; mk "$D"; sim "$D" live; rm -rf "$D/sys/kernel/tracing/events"
go "$D"; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$O" "skipped" "^trace: no spi_transfer_stop event under"
[ "$(wc -l < "$D/mount.log")" = 1 ] && grep -q -- '-t tracefs' "$D/mount.log" && ok "tried to mount tracefs once" || bad "mount calls: $(cat "$D/mount.log" 2>/dev/null)"
expect "$O" "verdict still printed" "^-- phase touch: verdict=EVENTS-FLOW"

echo "== refusals"
D="$W/nodev"; mk "$D"; sed -i '/FTS2BA61Y/d' "$D/proc/bus/input/devices"
go "$D" RECOVER=1; rc=$?
[ "$rc" = 4 ] && ok "no device: exit 4" || bad "no device: exit $rc"
expect "$D/out" "message" "^RESULT: NO-DEVICE"
[ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/unbind" ] && [ ! -e "$D/modprobe.log" ] && ok "nothing written without a device" || bad "wrote something"
D="$W/root"; mk "$D"
ID_U_T=1 go "$D"; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
D="$W/num"; mk "$D"
go "$D" DUR=abc; rc=$?
[ "$rc" = 2 ] && ok "bad number: exit 2" || bad "bad number: exit $rc"
expect "$D/out" "message" "^DUR must be a number of seconds"

echo "== SIGTERM in the middle of a phase cleans up"
D="$W/sig"; mk "$D"; sim "$D" live
( env SYSFS="$D/sys" PROC="$D/proc" DEBUGFS="$D/sys/kernel/debug" DMESG="$D/bin/dmesg" EVDIR="$D/dev/input" READER="tail -n +1 -f" MODPROBE="$D/bin/modprobe" \
	MOUNT="$D/bin/mount" SYSTEMCTL="$D/bin/systemctl" TMPDIR="$D/tmp" ID_U=0 DUR=60 COUNTDOWN=0 bash "$SCRIPT" > "$D/out" 2>&1 ) &
bp=$!
sleep 4; pkill -TERM -f "bash $SCRIPT" ; wait "$bp" 2>/dev/null; unsim
no_leftovers "$D" && ok "reader killed and temp dir removed after SIGTERM" || bad "leftovers after SIGTERM"
trace_restored "$D" && ok "trace controls restored after SIGTERM" || bad "trace not restored after SIGTERM"

echo "== static checks"
bash --posix -n "$SCRIPT" && ok "bash --posix -n" || bad "bash --posix -n"
grep -n '/dev/dri' "$SCRIPT" | grep -v '^[0-9]*:#' >/dev/null && bad "the script mentions /dev/dri outside comments" || ok "never opens /dev/dri"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
