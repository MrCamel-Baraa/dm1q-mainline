#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-spi-probe.sh (docs/06 rule 3). The phone's /sys, /dev, debugfs, modprobe,
# dmesg and the spi-xfer helper are replaced by a scratch tree and a fake helper through the script's env
# overrides, and the script is run with dash (closest to the phone's busybox ash, no bashisms allowed) and bash.
# Covers: READY detection (immediately, and only on a later poll), ALLFF, ALLZERO, OTHER, the helper failing,
# no spidev node, the two-speed default, and that the exact protocol frames are what docs/08 2.2 says.
# Usage: bash scripts/test-phone-touch-spi-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }

mkdir -p "$W/sys/bus/spi/devices/spi0.0" "$W/sys/class/spi_master" "$W/dev" "$W/dbg/regulator"
echo "spi:dh2228fv" > "$W/sys/bus/spi/devices/spi0.0/modalias"
touch "$W/dev/spidev0.0"
echo "vreg_l12b_1p8  1  0 1800mV" > "$W/dbg/regulator/regulator_summary"
echo " gpio-25  (tsp_int) in  hi IRQ" > "$W/dbg/gpio"
echo "[1.0] spi_geni_qcom a90000.spi: probed" > "$W/dmesg.txt"
printf '#!/bin/sh\ncat "%s"\n' "$W/dmesg.txt" > "$W/dmesg"; chmod +x "$W/dmesg"
printf '#!/bin/sh\nexit 0\n' > "$W/modprobe"; chmod +x "$W/modprobe"

# Fake spi-xfer. FAKE_MODE: ready | late | allff | allzero | other | err.  Items: DEV HZ then items; every
# "87+17" is a read (18 bytes), the first is the pre-reset read, the next five are the polls.
cat > "$W/spi-xfer" <<'EOF'
#!/bin/sh
echo "$@" >> "$FAKE_LOG"
[ "$FAKE_MODE" = err ] && { echo "ERR ioctl mode errno=25"; exit 3; }
shift 2
n=0
zeros="00 00 00 00 00 00 00 00 00 00 00 00 00 00"
for it in "$@"; do
	case "$it" in
	sleep:*) echo "SLEEP ${it#sleep:}" ;;
	87+17)
		echo "TX 87 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
		case "$FAKE_MODE" in
		ready) [ $n -eq 0 ] && echo "RX 00 00 04 11 $zeros" || echo "RX 00 00 08 00 $zeros" ;;
		late)  if [ $n -ge 4 ]; then echo "RX 00 00 08 00 $zeros"; else echo "RX 00 00 04 11 $zeros"; fi ;;
		allff) echo "RX ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff" ;;
		allzero) echo "RX 00 00 00 00 $zeros" ;;
		other) echo "RX 00 00 04 11 $zeros" ;;
		esac
		n=$((n + 1)) ;;
	*) echo "TX $it"; echo "RX 00 00 00 00 00 00" ;;
	esac
done
exit 0
EOF
chmod +x "$W/spi-xfer"

run() { # shell mode extra-env... -> output in $W/out
	local sh="$1" mode="$2"; shift 2
	: > "$W/log"
	# the caller's overrides come LAST so they win over the defaults below
	env FAKE_MODE="$mode" FAKE_LOG="$W/log" SPI_XFER="$W/spi-xfer" SYSFS="$W/sys" DEVDIR="$W/dev" DEBUGFS="$W/dbg" \
	    MODPROBE="$W/modprobe" DMESG="$W/dmesg" "$@" $sh "$HERE/phone-touch-spi-probe.sh" > "$W/out" 2>&1
}
expect() { # name regex
	if grep -q -E "$2" "$W/out"; then ok "$1"; else bad "$1" "$(grep -E '^RESULT|^no spidev|ERR' "$W/out" | tr '\n' '|')"; fi
}

# POSIX shells to try (the phone runs busybox ash); "bash --posix" is always available on the PC
for SH in dash ash mksh yash busybox\ ash "bash --posix" bash; do
	command -v "${SH%% *}" >/dev/null || { echo "  skip  $SH not installed"; continue; }
	echo "-- run with $SH"
	run "$SH" ready SPEEDS="1000000"
	expect "$SH: ready -> READY, pre=OTHER"        '^RESULT hz=1000000 pre=OTHER polls=READY,READY,READY,READY,READY verdict=READY$'
	run "$SH" late SPEEDS="1000000"
	expect "$SH: ready only on the 5th poll"       '^RESULT hz=1000000 pre=OTHER polls=OTHER,OTHER,OTHER,READY,READY verdict=READY$'
	run "$SH" allff SPEEDS="1000000"
	expect "$SH: all 0xff -> ALLFF"                '^RESULT hz=1000000 pre=ALLFF polls=ALLFF,ALLFF,ALLFF,ALLFF,ALLFF verdict=ALLFF$'
	run "$SH" allzero SPEEDS="1000000"
	expect "$SH: all 0x00 -> ALLZERO"              '^RESULT hz=1000000 pre=ALLZERO polls=ALLZERO,ALLZERO,ALLZERO,ALLZERO,ALLZERO verdict=ALLZERO$'
	run "$SH" other SPEEDS="1000000"
	expect "$SH: answers but never ready -> OTHER" '^RESULT hz=1000000 pre=OTHER polls=OTHER,OTHER,OTHER,OTHER,OTHER verdict=OTHER$'
	run "$SH" err SPEEDS="1000000"
	expect "$SH: helper failure -> XFERERR"        '^RESULT hz=1000000 pre=- polls=- verdict=XFERERR$'
	run "$SH" ready
	expect "$SH: default = two speeds (1 MHz)"     '^RESULT hz=1000000 .*verdict=READY$'
	expect "$SH: default = two speeds (10 MHz)"    '^RESULT hz=10000000 .*verdict=READY$'
	run "$SH" ready SPEEDS="1000000" DEVDIR="$W/nodev"
	expect "$SH: no spidev node -> NODEV"          '^RESULT hz=- pre=- polls=- verdict=NODEV$'
	expect "$SH: dmesg section is included"        'spi_geni_qcom a90000.spi: probed'
	expect "$SH: spi device listing is included"   '^spi0.0: driver= modalias=spi:dh2228fv$'
done

# the exact protocol frames: pre-read, reset, 30 ms, five polls 20 ms apart, once per speed
run bash ready SPEEDS="1000000"
got="$(head -1 "$W/log")"
exp="$W/dev/spidev0.0 1000000 87+17 FA2000002481 sleep:30 87+17 sleep:20 87+17 sleep:20 87+17 sleep:20 87+17 sleep:20 87+17"
[ "$got" = "$exp" ] && ok "helper is called with the docs/08 2.2 frame sequence" || bad "frame sequence" "$got"

# the dash/ash portability: no bash-only syntax in the phone script
bash --posix -n "$HERE/phone-touch-spi-probe.sh" && ok "bash --posix -n (syntax)" || bad "bash --posix -n" "syntax error"
if command -v shellcheck >/dev/null; then shellcheck -s sh -S warning "$HERE/phone-touch-spi-probe.sh" >"$W/sc" 2>&1 && ok "shellcheck -s sh" || bad "shellcheck" "$(head -5 "$W/sc")"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
