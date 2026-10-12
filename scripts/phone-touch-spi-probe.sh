#!/bin/sh
# Phone-side probe of the touch controller bus (docs/08 section 2, step B1). POSIX sh, run as root
# (collect-phone-state.sh --touch does that). Needs the B1 test image (spidev bound to spi4's touchscreen@0,
# L12B/L16B always on) and the helper /tmp/spi-xfer (scripts/spi-xfer.c).
#
# 1. loads the modules (gpi, spi_geni_qcom, spidev) and reports what the SPI core made of the DT node:
#    /sys/bus/spi/devices, the driver bound to it, /dev/spidev*, deferred probes, the touch rails, GPIO25/44-47
# 2. talks the FTS2BA61Y protocol (docs/08 2.2) from userspace, as ONE SPI message per step:
#      87+17                 read event: 18 bytes, the first two are the discarded header, then a 16-byte record
#      FA2000002481          the undocumented soft reset
#      sleep:30, then 5 x (87+17, sleep:20)   poll for the "ready" record
#    once at 1 MHz and once at 10 MHz (Samsung's spi-max-frequency)
# 3. classifies every read and prints one machine-readable line per speed:
#      RESULT hz=<hz> pre=<class> polls=<c,c,c,c,c> verdict=<READY|ALLFF|ALLZERO|OTHER|SHORT|XFERERR|NODEV>
#    READY  = event record type (byte0 bits 5:2) is 2 and byte1 == 0 -> the chip answered like the driver expects
#    ALLFF / ALLZERO = MISO stuck high / low: no chip, no power, wrong CS or mode; OTHER = it answered, not "ready"
# Env overrides (the PC-side test uses them): SPI_XFER SYSFS DEVDIR DEBUGFS MODPROBE DMESG SPEEDS
X="${SPI_XFER:-/tmp/spi-xfer}"
SYSFS="${SYSFS:-/sys}"
DEVDIR="${DEVDIR:-/dev}"
DEBUGFS="${DEBUGFS:-/sys/kernel/debug}"
MODPROBE="${MODPROBE:-modprobe}"
DMESG="${DMESG:-dmesg}"
SPEEDS="${SPEEDS:-1000000 10000000}"

say() { echo; echo "== $*"; }

classify() { # $1 = "RX b0 b1 b2 ..." -> READY | ALLFF | ALLZERO | OTHER | SHORT
	_l="${1#RX }"
	# shellcheck disable=SC2086
	set -- $_l
	[ $# -ge 4 ] || { echo SHORT; return; }
	_u="$(printf '%s\n' "$@" | sort -u | tr '\n' ' ')"
	case "$_u" in
	"ff ") echo ALLFF; return ;;
	"00 ") echo ALLZERO; return ;;
	esac
	_b2=$((0x$3)); _b3=$((0x$4))
	if [ $(((_b2 >> 2) & 15)) -eq 2 ] && [ "$_b3" -eq 0 ]; then echo READY; else echo OTHER; fi
}

say "kernel"
uname -a
date

say "modules"
for m in gpi spi_geni_qcom spidev; do
	o="$($MODPROBE "$m" 2>&1)"; r=$?
	echo "modprobe $m rc=$r $o"
done
sleep 1

say "spi devices"
for d in "$SYSFS"/bus/spi/devices/*; do
	[ -e "$d" ] || continue
	drv="$(readlink "$d/driver" 2>/dev/null)"
	echo "$(basename "$d"): driver=${drv##*/} modalias=$(cat "$d/modalias" 2>/dev/null)"
done
ls -l "$DEVDIR"/spidev* 2>&1
echo "-- spi masters"
for m in "$SYSFS"/class/spi_master/*; do [ -e "$m" ] && echo "$(basename "$m") -> $(readlink -f "$m")"; done
echo "-- deferred probes"
cat "$DEBUGFS/devices_deferred" 2>&1
echo "-- touch rails"
grep -E 'vreg_l12b|vreg_l16b' "$DEBUGFS/regulator/regulator_summary" 2>&1
echo "-- gpios (25 = touch irq, 44-47 = spi4 miso/mosi/clk/cs)"
grep -E ' gpio-(25|44|45|46|47) ' "$DEBUGFS/gpio" 2>&1
echo "-- dmesg (spi / geni / gpi / touch)"
$DMESG 2>&1 | grep -i -E 'spi|geni|gpi|a90000|fts|touch|spidev|l12b|l16b' | tail -n 60

DEV="$(ls "$DEVDIR"/spidev*.* 2>/dev/null | head -n 1)"
if [ -z "$DEV" ]; then
	say "result"
	echo "no spidev node -> nothing to talk to. Look at: spi devices / deferred probes / dmesg above"
	echo "RESULT hz=- pre=- polls=- verdict=NODEV"
	exit 0
fi

for hz in $SPEEDS; do
	say "sequence on $DEV at $hz Hz"
	OUT="$($X "$DEV" "$hz" 87+17 FA2000002481 sleep:30 87+17 sleep:20 87+17 sleep:20 87+17 sleep:20 87+17 sleep:20 87+17 2>&1)"; rc=$?
	echo "$OUT"
	echo "spi-xfer rc=$rc"
	if [ "$rc" -ne 0 ]; then
		echo "RESULT hz=$hz pre=- polls=- verdict=XFERERR"
		continue
	fi
	RX="$(echo "$OUT" | grep '^RX')"
	pre="$(classify "$(echo "$RX" | sed -n 1p)")"
	polls=""; ready=0; last=""
	for i in 3 4 5 6 7; do
		c="$(classify "$(echo "$RX" | sed -n "${i}p")")"
		polls="${polls:+$polls,}$c"
		[ "$c" = READY ] && ready=1
		last="$c"
	done
	if [ "$ready" = 1 ]; then v=READY; else v="$last"; fi
	echo "RESULT hz=$hz pre=$pre polls=$polls verdict=$v"
done

say "gpios after the sequences"
grep -E ' gpio-(25|44|45|46|47) ' "$DEBUGFS/gpio" 2>&1
