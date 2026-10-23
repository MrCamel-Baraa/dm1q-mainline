#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-trace.sh (docs/06 rule 3). Fake /proc, /sys (regulators, the spi driver's unbind / bind files), a fake tracefs whose
# `instances/` directory gets its tree from a MKDIR stub (real tracefs creates the files itself), a background SIMULATOR that plays the chip (alive / dead /
# a rebind brings it back), and a crafted phone-format trace (dash-separated bytes, as the phone prints them) for the decoder. Checks: arm enables exactly the
# spi event with the bus 0 / cs 0 filter and the requested buffer size, the alive check, the revive by rebind (only when dead and REVIVE=1), the device left bound,
# refusals (no instances, no spi event, not root, bad numbers), dump decoding (record count, event ids, the status record with its stype, the gap, the per-second
# buckets, the age of the last record), dump changes nothing, disarm. Run with bash. Usage: bash scripts/test-phone-touch-trace.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-trace.sh"
W="$(mktemp -d)"
SIMPID=""
finish() { [ -n "$SIMPID" ] && kill "$SIMPID" 2>/dev/null; rm -rf "$W"; }
trap finish EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

mk() { # $1 = dir
	local D="$1"
	rm -rf "$D"
	mkdir -p "$D/bin" "$D/tmp" "$D/proc" "$D/sys/kernel/debug" "$D/sys/class/regulator/regulator.1" "$D/sys/class/regulator/regulator.2" \
		"$D/sys/bus/spi/devices/spi0.0" "$D/sys/bus/spi/drivers/fts2ba61y" "$D/sys/kernel/tracing/events/spi/spi_transfer_stop" "$D/sys/kernel/tracing/instances" "$D/outdir"
	printf '  7:          0          0  GICv3  27 Level     arch_timer\n 178:      11464          0          0          0  msmgpio  25 Level     fts2ba61y\n' > "$D/proc/interrupts"
	echo "1100.00 9999.00" > "$D/proc/uptime"
	printf ' gpio25  : in  high func0 2mA no pull\n' > "$D/sys/kernel/debug/gpio"
	echo vreg_l12b_1p8 > "$D/sys/class/regulator/regulator.1/name"; echo enabled > "$D/sys/class/regulator/regulator.1/state"
	echo 1800000 > "$D/sys/class/regulator/regulator.1/microvolts"; echo 1 > "$D/sys/class/regulator/regulator.1/num_users"
	echo vreg_l16b_3p0 > "$D/sys/class/regulator/regulator.2/name"; echo enabled > "$D/sys/class/regulator/regulator.2/state"
	echo 3000000 > "$D/sys/class/regulator/regulator.2/microvolts"; echo 1 > "$D/sys/class/regulator/regulator.2/num_users"
	: > "$D/sys/bus/spi/devices/spi0.0/driver"
	: > "$D/sys/bus/spi/drivers/fts2ba61y/unbind"; : > "$D/sys/bus/spi/drivers/fts2ba61y/bind"
	echo 0 > "$D/sys/kernel/tracing/events/spi/spi_transfer_stop/enable"
	printf '[    7.700000] fts2ba61y spi0.0: id 53 54 40 36 01, resolution 4095x4095, 16 TX x 34 RX channels\n' > "$D/dmesg"
	printf '#!/bin/sh\ncat "%s/dmesg"\n' "$D" > "$D/bin/dmesg"
	cat > "$D/bin/journalctl" <<'EOF'
#!/bin/sh
printf '%s\n' '[  960.000000] samsung-dm1q plasmashell[900]: outside, too early' \
	'[  970.123456] samsung-dm1q kernel: inside, early' \
	'-- a line without a monotonic stamp' \
	'[  995.150000] samsung-dm1q systemd-logind[612]: inside, near the stop' \
	'[ 1030.000000] samsung-dm1q plasmashell[900]: outside, too late'
EOF
	printf '#!/bin/sh\nexit 0\n' > "$D/bin/nojournal"
	printf '#!/bin/sh\necho "$*" >> "%s/mount.log"\n' "$D" > "$D/bin/mount"
	# the real tracefs fills a new instance directory by itself; the stub plays that
	cat > "$D/bin/mkdir" <<EOF
#!/bin/sh
[ -e "$D/nomk" ] && exit 1
mkdir -p "\$1/events/spi/spi_transfer_stop" "\$1/per_cpu/cpu0"
[ -e "$D/nospi" ] && rmdir "\$1/events/spi/spi_transfer_stop"
echo 1408 > "\$1/buffer_size_kb"; echo 1 > "\$1/tracing_on"; echo 0 > "\$1/events/spi/spi_transfer_stop/enable" 2>/dev/null
: > "\$1/trace"
printf 'entries: 203\noverrun: 12\nbytes: 4000\n' > "\$1/per_cpu/cpu0/stats"
EOF
	printf '#!/bin/sh\nrm -rf "$1"\n' > "$D/bin/rmdir"
	chmod +x "$D/bin/journalctl" "$D/bin/nojournal" "$D/bin/dmesg" "$D/bin/mount" "$D/bin/mkdir" "$D/bin/rmdir"
}

sim() { # $1 dir $2 mode: alive | dead | rebindfix
	local D="$1" mode="$2"
	case "$mode" in alive) : > "$D/alive" ;; esac
	(
		cnt=11464
		while :; do
			sleep 0.2
			if [ "$mode" = rebindfix ] && [ -s "$D/sys/bus/spi/drivers/fts2ba61y/bind" ]; then : > "$D/alive"; fi
			if [ -e "$D/alive" ]; then
				cnt=$((cnt + 25))
				printf ' 178: %10d          0          0          0  msmgpio  25 Level     fts2ba61y\n' "$cnt" > "$D/proc/interrupts.tmp" && mv "$D/proc/interrupts.tmp" "$D/proc/interrupts"
			fi
		done
	) &
	SIMPID=$!
}
unsim() { [ -n "$SIMPID" ] && { kill "$SIMPID" 2>/dev/null; wait "$SIMPID" 2>/dev/null; }; SIMPID=""; }

go() { # $1 dir, $2 mode, rest = VAR=value assignments
	local D="$1" m="$2"; shift 2
	timeout 100 env SYSFS="$D/sys" PROC="$D/proc" DEBUGFS="$D/sys/kernel/debug" DMESG="$D/bin/dmesg" JOURNALCTL="$D/bin/journalctl" MOUNT="$D/bin/mount" MKDIR="$D/bin/mkdir" RMDIR="$D/bin/rmdir" \
		TMPDIR="$D/tmp" OUT="$D/outdir/raw.txt" ID_U="${ID_U_T-0}" CHECK=2 COUNTDOWN=0 "$@" bash "$SCRIPT" "$m" > "$D/out" 2>&1
}
INSTD() { echo "$1/sys/kernel/tracing/instances/dm1q-touch"; }

echo "== arm, touch alive"
D="$W/a1"; mk "$D"; sim "$D" alive
go "$D" arm; rc=$?; unsim; O="$D/out"; I=$(INSTD "$D"); TE="$I/events/spi/spi_transfer_stop"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
[ "$(cat "$TE/enable")" = 1 ] && [ "$(cat "$I/tracing_on")" = 1 ] && ok "event enabled and tracing on in the instance" || bad "not enabled"
grep -q 'bus_num == 0 && chip_select == 0' "$TE/filter" && ok "filter bus 0 / cs 0" || bad "filter"
[ "$(cat "$I/buffer_size_kb")" = 4096 ] && ok "buffer_size_kb = BUF_KB (4096)" || bad "buffer_size_kb = $(cat "$I/buffer_size_kb")"
[ "$(cat "$D/sys/kernel/tracing/events/spi/spi_transfer_stop/enable")" = 0 ] && ok "the global spi event untouched" || bad "global event changed"
expect "$O" "armed line" "^armed: .*/instances/dm1q-touch \(spi:spi_transfer_stop, bus 0 / cs 0\), buffer_size_kb=4096 per CPU, at uptime 1100.00 s"
expect "$O" "state line" "^irq count: [0-9]+ +gpio25: high +l12b=enabled:1800000uV:users=1 l16b=enabled:3000000uV:users=1"
expect "$O" "alive" "^touch is alive now \([1-9][0-9]* interrupts in 2 s\)"
expect "$O" "RESULT ARMED" "^RESULT: ARMED"
[ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/unbind" ] && ok "no rebind when alive" || bad "rebind ran"

echo "== arm, dead, a rebind revives it"
D="$W/a2"; mk "$D"; sim "$D" rebindfix
go "$D" arm; rc=$?; unsim; O="$D/out"; I=$(INSTD "$D")
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "dead noticed" "^touch looks DEAD right now"
[ "$(cat "$D/sys/bus/spi/drivers/fts2ba61y/unbind")" = spi0.0 ] && [ "$(cat "$D/sys/bus/spi/drivers/fts2ba61y/bind")" = spi0.0 ] && ok "spi0.0 unbind then bind" || bad "unbind / bind contents"
expect "$O" "RESULT REVIVED" "^RESULT: REVIVED by rebind"
[ "$(cat "$I/events/spi/spi_transfer_stop/enable")" = 1 ] && ok "recorder still armed" || bad "recorder not armed"

echo "== arm, dead, nothing revives it"
D="$W/a3"; mk "$D"; sim "$D" dead
go "$D" arm; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "STILL-SILENT" "^RESULT: STILL-SILENT after the rebind"

echo "== arm, dead, REVIVE=0"
D="$W/a4"; mk "$D"; sim "$D" dead
go "$D" arm REVIVE=0; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$O" "RESULT ARMED" "^RESULT: ARMED"
[ ! -s "$D/sys/bus/spi/drivers/fts2ba61y/unbind" ] && ok "no rebind with REVIVE=0" || bad "rebind ran"

echo "== arm, CHECK=0: no alive check"
D="$W/a5"; mk "$D"; sim "$D" dead
go "$D" arm CHECK=0; rc=$?; unsim; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
reject "$O" "no check" "alive check|DEAD"
expect "$O" "RESULT ARMED" "^RESULT: ARMED"

echo "== arm: no trace instances / cannot create / no spi event"
D="$W/n1"; mk "$D"; rm -rf "$D/sys/kernel/tracing/events" "$D/sys/kernel/tracing/instances"
go "$D" arm; rc=$?
[ "$rc" = 3 ] && ok "no instances: exit 3" || bad "no instances: exit $rc"
expect "$D/out" "message" "^RESULT: NO-TRACE-INSTANCES"
[ "$(wc -l < "$D/mount.log" 2>/dev/null)" = 1 ] && ok "tracefs mount tried once" || bad "mount calls: $(cat "$D/mount.log" 2>/dev/null)"
D="$W/n2"; mk "$D"; : > "$D/nomk"
go "$D" arm; rc=$?
[ "$rc" = 3 ] && ok "cannot create: exit 3" || bad "cannot create: exit $rc"
expect "$D/out" "message" "^RESULT: CANNOT-CREATE-INSTANCE"
D="$W/n3"; mk "$D"; : > "$D/nospi"
go "$D" arm; rc=$?
[ "$rc" = 3 ] && ok "no spi event: exit 3" || bad "no spi event: exit $rc"
expect "$D/out" "message" "^RESULT: NO-SPI-EVENT"
[ ! -d "$(INSTD "$D")" ] && ok "the half-made instance is removed" || bad "instance left behind"

echo "== arm twice: the second arm resets the instance"
D="$W/a6"; mk "$D"; sim "$D" alive
go "$D" arm CHECK=0; echo stale > "$(INSTD "$D")/trace"
go "$D" arm CHECK=0; rc=$?; unsim
[ "$rc" = 0 ] && [ ! -s "$(INSTD "$D")/trace" ] && ok "re-armed with an empty buffer" || bad "re-arm: rc=$rc trace=$(cat "$(INSTD "$D")/trace")"

echo "== dump: not armed"
D="$W/d0"; mk "$D"
go "$D" dump; rc=$?
[ "$rc" = 4 ] && ok "exit 4" || bad "exit $rc"
expect "$D/out" "message" "^RESULT: NOT-ARMED"

echo "== dump: empty buffer"
D="$W/d1"; mk "$D"; go "$D" arm CHECK=0
go "$D" dump; rc=$?; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$O" "zero records explained" "^records=0: the buffer holds no transfer of spi0.0"
expect "$O" "stays armed" "^RESULT: DUMPED \(the recorder stays armed\)"

echo "== dump: crafted phone-format trace"
D="$W/d2"; mk "$D"; go "$D" arm CHECK=0; I=$(INSTD "$D")
mkline() { printf '    irq/178-fts2ba6-14764   [000] .....   %s: spi_transfer_stop: %s 000000005fdf8c3a len=18 tx=[87-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00] rx=[%s]\n' "$1" "${3:-spi0.0}" "$2"; }
{
	echo '# tracer: nop'; echo '# entries-in-buffer/entries-written: 203/203   #P:8'
	for i in $(seq 0 199); do mkline "$(awk -v i="$i" 'BEGIN { printf "%.6f", 990.0005 + i * 0.008 }')" "00-87-80-43-33-e3-11-09-11-00-02-5e-00-01-00-00-00-00"; done
	mkline 993.000000 "00-87-80-43-33-e3-11-09-11-00-02-5e-00-01-00-00-00-00" spi1.0
	mkline 995.100300 "00-87-49-00-10-00-00-00-00-00-00-00-00-00-00-00-00-00"
	mkline 995.150000 "00-87-4b-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00"
	mkline 995.200000 "00-87-80-43-33-e3-11-09-11-00-02-5e-00-01-00-00-00-00"
} > "$I/trace"
sum_before=$(cd "$D/sys" && find . -type f -exec cksum {} + | sort)
go "$D" dump; rc=$?; O="$D/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
expect "$O" "recorder status line" "^recorder: enable=1 tracing_on=1 buffer_size_kb=4096"
expect "$O" "per-CPU stats shown (overrun)" "cpu0: entries: 203 overrun: 12 bytes: 4000"
cmp -s "$I/trace" "$D/outdir/raw.txt" && ok "raw buffer saved unchanged" || bad "raw copy differs"
expect "$O" "record count (the spi1.0 line is ignored)" "^records=203 first=990.000500 last=995.200000 \(span 5.2 s\)"
expect "$O" "age of the last record" "^last record is 104.8 s older than the boot clock now \(1100.00 s\)"
expect "$O" "event id counts" "^event ids: coordinate\(0\)=201 status\(1\)=1 other\(2\)=0 other\(3\)=1 undecodable=0"
expect "$O" "largest gap" "^largest gap between two records: 3.508 s \(ending at 995.100300\)"
expect "$O" "rate buckets (3 records in the last second, then 50 / 125 / 25 in seconds 3 / 4 / 5)" "^records per second before the last record \(newest first, 10 buckets\): 3 0 0 50 125 25 0 0 0 0"
expect "$O" "status record decoded with its stype" "^   995.100300 len=18 id=1 stype=2 ev=49 00 10 00"
expect "$O" "the other id listed too" "^   995.150000 len=18 id=3 stype=2 ev=4b"
reject "$O" "the coordinate records are not in the non-coordinate list" "^   990\.[0-9]+ len=18 id=1"
[ "$(sed -n '/^last 20 records:/,$p' "$O" | grep -c '^   99')" = 20 ] && ok "20 last records" || bad "last-20 count"
expect "$O" "kernel lines about the chip" "fts2ba61y spi0.0: id 53 54 40 36 01"
expect "$O" "state line" "^irq count: 11464"
[ "$sum_before" = "$(cd "$D/sys" && find . -type f -exec cksum {} + | sort)" ] && ok "dump changed nothing under /sys" || bad "dump changed the fake sys tree"
[ "$(cat "$I/events/spi/spi_transfer_stop/enable")" = 1 ] && ok "still armed" || bad "not armed any more"
expect "$O" "journal header names the last record" "^-- journal, all units, within 30 s of the last record \(995.200000 s, monotonic clock\):"
expect "$O" "journal line inside the window (early edge)" "^   \[  970.123456\] samsung-dm1q kernel: inside, early"
expect "$O" "journal line inside the window (near the stop)" "^   \[  995.150000\] samsung-dm1q systemd-logind\[612\]: inside, near the stop"
reject "$O" "journal line before the window is dropped" "outside, too early"
reject "$O" "journal line after the window is dropped" "outside, too late"
reject "$O" "a line without a stamp is dropped" "without a monotonic stamp"
go "$D" dump JOURNALCTL="$D/bin/nojournal"; O="$D/out"
expect "$O" "an empty journal is said so" "no journal lines in that window"

echo "== disarm"
go "$D" disarm; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$D/out" "message" "^RESULT: DISARMED"
[ ! -d "$I" ] && ok "instance removed" || bad "instance still there"
go "$D" dump; rc=$?
[ "$rc" = 4 ] && ok "dump after disarm: NOT-ARMED" || bad "dump after disarm: exit $rc"

echo "== refusals"
D="$W/r1"; mk "$D"
ID_U_T=1 go "$D" arm; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
go "$D" arm BUF_KB=abc; rc=$?
[ "$rc" = 2 ] && ok "bad BUF_KB: exit 2" || bad "bad BUF_KB: exit $rc"
go "$D" arm BUF_KB=8; rc=$?
[ "$rc" = 2 ] && ok "BUF_KB below 64: exit 2" || bad "small BUF_KB: exit $rc"
go "$D" nonsense; rc=$?
[ "$rc" = 2 ] && ok "unknown mode: exit 2" || bad "unknown mode: exit $rc"
[ ! -d "$(INSTD "$D")" ] && ok "nothing created on a refusal" || bad "instance created on a refusal"

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
