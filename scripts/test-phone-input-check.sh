#!/usr/bin/env bash
# PC-side test of scripts/phone-input-check.sh (docs/06 rule 3). Fake /proc and /sys trees and a stub dmesg, one healthy tree and several broken ones, so the
# verdicts EVDEV / BTF / TOUCH / KEYS have exact expected values. Checks: the healthy tree (touch ok, three keys, evdev loaded, BTF line seen), a missing
# driver binding, a bound driver with no input device, a wrong driver, no evdev and no BTF lines, the device list, READ-ONLY (no file under the fake tree
# changes), refusals, and the POSIX / shellcheck static checks. Run with bash.
# Usage: bash scripts/test-phone-input-check.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-input-check.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

# A tree builder: $1 = directory, $2 = "good" | "nodrv" | "noinput" | "wrongdrv" | "noevdev"
make_tree() {
	local D="$1" mode="$2"
	mkdir -p "$D/proc/bus/input" "$D/sys/bus/spi/devices/spi0.0" "$D/sys/module"
	echo "1500.00 9000.00" > "$D/proc/uptime"
	cat > "$D/proc/modules" <<'EOF'
spi_geni_qcom 45056 0 - Live 0x0000000000000000
gpi 90112 0 - Live 0x0000000000000000
EOF
	[ "$mode" = noevdev ] || echo "evdev 28672 1 - Live 0x0000000000000000" >> "$D/proc/modules"
	[ "$mode" = good ] || [ "$mode" = noinput ] || [ "$mode" = wrongdrv ] && echo "fts2ba61y 40960 0 - Live 0x0000000000000000" >> "$D/proc/modules"
	case "$mode" in
	good|noinput) ln -s /sys/bus/spi/drivers/fts2ba61y "$D/sys/bus/spi/devices/spi0.0/driver" ;;
	wrongdrv) ln -s /sys/bus/spi/drivers/other_driver "$D/sys/bus/spi/devices/spi0.0/driver" ;;
	esac
	{
		echo "I: Bus=0018 Vendor=0000 Product=0000 Version=0000"
		echo "N: Name=\"pmic_pwrkey\""
		echo "H: Handlers=kbd event0"
		echo ""
		echo "I: Bus=0019 Vendor=0000 Product=0000 Version=0000"
		echo "N: Name=\"pm8550_resin\""
		echo "H: Handlers=kbd event1"
		echo ""
		echo "I: Bus=0019 Vendor=0000 Product=0000 Version=0000"
		echo "N: Name=\"gpio-keys\""
		echo "H: Handlers=kbd event2"
		echo ""
	} > "$D/proc/bus/input/devices"
	if [ "$mode" = good ] || [ "$mode" = wrongdrv ]; then
		{
			echo "I: Bus=0018 Vendor=0000 Product=0000 Version=0000"
			echo "N: Name=\"STMicroelectronics FTS2BA61Y Touchscreen\""
			echo "H: Handlers=event3"
			echo ""
		} >> "$D/proc/bus/input/devices"
	fi
	[ "$mode" = nodrv ] && {
		# no touch device and no driver: remove the key-only list's touch entry (not present anyway)
		:
	}
	cat > "$D/proc/interrupts" <<'EOF'
          CPU0       CPU1
 25:       1024          0  GICv3  25 Level  fts2ba61y
 26:          7          3  GICv3  26 Level  spi0
EOF
    mkdir -p "$D/sys/kernel/debug/irq/irqs"
    printf 'handler:  handle_fasteoi_irq\nstatus:   0x00000400\nistate:   0x00000000\nddepth:   0\n' > "$D/sys/kernel/debug/irq/irqs/25"
    echo "gpio25 (fts2ba61y) in hi" > "$D/sys/kernel/debug/gpio"
    mkdir -p "$D/proc/2817"
    echo "irq/178-fts2ba6" > "$D/proc/2817/comm"
    echo "2817 (irq/178-fts2ba6) S 2 0 0 0 -1 69238880 0 0 0 0 0 0 0 0 20 0 1 0 1 0 0" > "$D/proc/2817/stat"
    echo "futex_wait_queue" > "$D/proc/2817/wchan"
    echo "stack line one" > "$D/proc/2817/stack"
	if [ "$mode" = noevdev ]; then
		echo "[    2.000000] ordinary line" > "$D/dmesg"
	else
		cat > "$D/dmesg" <<'EOF'
[    2.000000] ordinary line
[    3.023965] failed to validate module [evdev] BTF: -22
[    3.011364] evdev: module verification failed: signature and/or required key missing - tainting kernel
EOF
	fi
	printf '#!/bin/sh\ncat "%s/dmesg"\n' "$D" > "$D/dmesg.sh"
	chmod +x "$D/dmesg.sh"
}

run() { # $1 = tree dir, rest = extra env assignments
	local D="$1"; shift
	env ID_U=0 PROC="$D/proc" SYSFS="$D/sys" DMESG="$D/dmesg.sh" "$@" sh "$SCRIPT" > "$D.out" 2>&1
}

echo "== healthy tree"
make_tree "$W/good" good
run "$W/good"; rc=$?
[ "$rc" = 0 ] && ok "healthy: exit 0" || bad "healthy: exit $rc"
expect "$W/good.out" "evdev loaded" "^EVDEV=loaded$"
expect "$W/good.out" "the BTF line is seen" "^BTF=seen$"
expect "$W/good.out" "the BTF line is echoed" "failed to validate module \[evdev\] BTF"
expect "$W/good.out" "the touch driver is bound" "spi0.0 driver: fts2ba61y"
expect "$W/good.out" "touch input device found" "N: Name=\"STMicroelectronics FTS2BA61Y Touchscreen\""
expect "$W/good.out" "touch ok" "^TOUCH=ok$"
expect "$W/good.out" "three key devices" "key input devices: 3"
expect "$W/good.out" "keys ok" "^KEYS=ok$"
expect "$W/good.out" "touch interrupt line listed" "fts2ba61y"
expect "$W/good.out" "device count" "input devices: 4"

echo "== no driver binding"
make_tree "$W/nodrv" noinput
rm -f "$W/nodrv/sys/bus/spi/devices/spi0.0/driver"
run "$W/nodrv"
expect "$W/nodrv.out" "driver is none" "spi0.0 driver: none"
expect "$W/nodrv.out" "TOUCH=unbound" "^TOUCH=unbound$"

echo "== bound driver, no input device"
make_tree "$W/noinput" noinput
run "$W/noinput"
expect "$W/noinput.out" "TOUCH=no-input-device" "^TOUCH=no-input-device$"
expect "$W/noinput.out" "says no input device" "no input device named fts / stm / touch"

echo "== wrong driver bound"
make_tree "$W/wrongdrv" wrongdrv
run "$W/wrongdrv"
expect "$W/wrongdrv.out" "TOUCH=wrong-driver" "^TOUCH=wrong-driver$"

echo "== no evdev, no BTF lines"
make_tree "$W/noevdev" noevdev
run "$W/noevdev"
expect "$W/noevdev.out" "EVDEV=absent" "^EVDEV=absent$"
expect "$W/noevdev.out" "BTF=none" "^BTF=none$"
expect "$W/noevdev.out" "no BTF lines reported" "no BTF, verification or taint lines"

echo "== fewer keys"
make_tree "$W/fewkeys" good
{
	echo "I: Bus=0018 Vendor=0000 Product=0000 Version=0000"
	echo "N: Name=\"pmic_pwrkey\""
	echo "H: Handlers=kbd event0"
	echo ""
	echo "I: Bus=0018 Vendor=0000 Product=0000 Version=0000"
	echo "N: Name=\"STMicroelectronics FTS2BA61Y Touchscreen\""
	echo "H: Handlers=event3"
	echo ""
} > "$W/fewkeys/proc/bus/input/devices"
run "$W/fewkeys"
expect "$W/fewkeys.out" "KEYS=partial with one key" "^KEYS=partial$"

echo "== interrupt state"
make_tree "$W/irqgood" good
run "$W/irqgood"
expect "$W/irqgood.out" "touch irq and count listed" "touch irq: 25   count: 1024"
expect "$W/irqgood.out" "IRQ enabled when depth is 0" "^IRQ=enabled$"
expect "$W/irqgood.out" "gpio25 high" "^GPIO25=high$"
make_tree "$W/irqdis" good
sed -i 's/ddepth:   0/ddepth:   1/' "$W/irqdis/sys/kernel/debug/irq/irqs/25"
run "$W/irqdis"
expect "$W/irqdis.out" "IRQ disabled when depth > 0" "^IRQ=disabled$"
make_tree "$W/irqlo" good
echo "gpio25 (fts2ba61y) in lo" > "$W/irqlo/sys/kernel/debug/gpio"
run "$W/irqlo"
expect "$W/irqlo.out" "gpio25 low" "^GPIO25=low$"
make_tree "$W/irqnodbg" good
rm -rf "$W/irqnodbg/sys/kernel/debug"
run "$W/irqnodbg"
expect "$W/irqnodbg.out" "IRQ unknown without debugfs" "^IRQ=unknown$"
expect "$W/irqnodbg.out" "says no debugfs state" "no debugfs irq state"

echo "== touch IRQ thread"
make_tree "$W/thrS" good
run "$W/thrS"
expect "$W/thrS.out" "thread found with its state" "thread: pid 2817 comm irq/178-fts2ba6 state S wchan futex_wait_queue"
expect "$W/thrS.out" "IRQ_THREAD=S" "^IRQ_THREAD=S$"
expect "$W/thrS.out" "stack shown" "stack: stack line one"
make_tree "$W/thrD" good
sed -i 's/) S 2/) D 2/' "$W/thrD/proc/2817/stat"
echo "spi_transfer_one_message" > "$W/thrD/proc/2817/wchan"
run "$W/thrD"
expect "$W/thrD.out" "uninterruptible state shown" "^IRQ_THREAD=D$"
expect "$W/thrD.out" "wait channel shown" "wchan spi_transfer_one_message"
make_tree "$W/thrNone" good
rm -rf "$W/thrNone/proc/2817"
run "$W/thrNone"
expect "$W/thrNone.out" "no thread reported" "^IRQ_THREAD=none$"
expect "$W/thrNone.out" "says no thread" "no irq handler thread for fts2ba61y"

echo "== refusals"
env ID_U=1 PROC="$W/good/proc" SYSFS="$W/good/sys" DMESG="$W/good/dmesg.sh" sh "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"

echo "== read-only"
before=$(find "$W/good" -type f -o -type l | sort | xargs -I{} sh -c 'printf "%s " "{}"; cat "{}" 2>/dev/null | cksum' | cksum)
run "$W/good"
after=$(find "$W/good" -type f -o -type l | sort | xargs -I{} sh -c 'printf "%s " "{}"; cat "{}" 2>/dev/null | cksum' | cksum)
[ "$before" = "$after" ] && ok "the fake tree is unchanged by the script" || bad "the fake tree changed"

echo "== static checks"
sh -n "$SCRIPT" && ok "sh -n" || bad "sh -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
