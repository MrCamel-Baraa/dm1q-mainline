#!/bin/sh
# Phone-side input-stack check (docs/08 section 2.17: the evdev module failed its BTF check at boot, and the touch / key input devices have not been
# checked since). POSIX sh, run as root (collect-phone-state.sh --input-check does that). READ-ONLY: it reads procfs / sysfs / dmesg; it writes nothing,
# not even a temp file, and it never opens an input or DRI device node.
#   0 when      date, uptime, kernel
#   1 modules   evdev and fts2ba61y in /proc/modules; the BTF / verification / taint lines of dmesg
#   2 devices   every entry of /proc/bus/input/devices (name and handlers)
#   3 touch     the FTS2BA61Y: the SPI driver bound to spi0.0, its input device, its interrupt lines
#   4 keys      the power and volume-key input devices
#   3b irq      the touch IRQ count, whether that IRQ is enabled (debugfs; best effort), and what gpio25 reads (IRQ=enabled|disabled|unknown, GPIO25=high|low|unknown)
#   3c irq thread  the touch IRQ handler thread (irq/<n>-fts2ba6...): its state, wait channel and stack (IRQ_THREAD=state|none).
#                  A thread stuck in D with an SPI wait channel means the threaded IRQ never returned, so its ONESHOT line stays masked.
#   5 verdict   EVDEV, BTF, TOUCH, KEYS, IRQ, GPIO25, IRQ_THREAD, one per line. A healthy input stack is EVDEV=loaded BTF=none TOUCH=ok KEYS=ok IRQ=enabled.
#               TOUCH=ok means only that the driver is bound and its input device exists; it does not mean the chip is reporting. IRQ=disabled or GPIO25 low with a frozen count is the lead.
# The driver and input names come from kernel/patches/0002 (driver "fts2ba61y", input "STMicroelectronics FTS2BA61Y Touchscreen").
# Env (the PC-side test uses them): PROC SYSFS DEBUGFS DMESG ID_U
PROC="${PROC:-/proc}"
SYSFS="${SYSFS:-/sys}"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
DMESG="${DMESG:-dmesg}"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

say() { echo; echo "== $*"; }

say "0. when"
echo "date: $(date 2>/dev/null)"
read -r up _ < "$PROC/uptime" 2>/dev/null
echo "uptime: ${up:-?} s   kernel: $(uname -r 2>/dev/null)"

say "1. modules"
EVDEV=absent
if grep -q '^evdev ' "$PROC/modules" 2>/dev/null; then
	EVDEV=loaded
elif [ -d "$SYSFS/module/evdev" ]; then
	EVDEV=loaded
fi
echo "evdev: $EVDEV"
if grep -q '^fts2ba61y ' "$PROC/modules" 2>/dev/null; then
	echo "fts2ba61y: loaded as a module"
else
	echo "fts2ba61y: not a loaded module (built in, or not present)"
fi
BTF_LINES=$("$DMESG" 2>/dev/null | grep -E 'failed to validate module .*BTF|module verification failed|tainting kernel')
if [ -n "$BTF_LINES" ]; then
	BTF=seen
	printf '%s\n' "$BTF_LINES" | sed 's/^/dmesg: /'
else
	BTF=none
	echo "dmesg: no BTF, verification or taint lines"
fi

say "2. input devices (/proc/bus/input/devices)"
if [ -r "$PROC/bus/input/devices" ]; then
	awk 'BEGIN { RS = ""; FS = "\n" }
	{
		for (i = 1; i <= NF; i++) {
			if ($i ~ /^[NH]: /) print $i
		}
		print ""
		n++
	}
	END { print "input devices: " (n + 0) }' "$PROC/bus/input/devices"
else
	echo "no /proc/bus/input/devices"
fi

say "3. touch (FTS2BA61Y)"
DRV=$(readlink "$SYSFS/bus/spi/devices/spi0.0/driver" 2>/dev/null)
DRV=${DRV##*/}
echo "spi0.0 driver: ${DRV:-none}"
TOUCH_LINES=$(awk 'BEGIN { RS = ""; FS = "\n" }
{
	hit = 0
	for (i = 1; i <= NF; i++) {
		if ($i ~ /^N: / && tolower($i) ~ /fts|stm|touch/) hit = 1
	}
	if (hit) for (i = 1; i <= NF; i++) if ($i ~ /^[NH]: /) print $i
}' "$PROC/bus/input/devices" 2>/dev/null)
if [ -n "$TOUCH_LINES" ]; then
	TOUCH_IN=present
	printf '%s\n' "$TOUCH_LINES"
else
	TOUCH_IN=absent
	echo "no input device named fts / stm / touch"
fi
echo "interrupt lines (fts / stm / touch / spi):"
grep -iE 'fts|stm|touch|spi' "$PROC/interrupts" 2>/dev/null | head -5 | sed 's/^/  /'
if [ "$DRV" = fts2ba61y ] && [ "$TOUCH_IN" = present ]; then
	TOUCH=ok
elif [ "$DRV" = fts2ba61y ]; then
	TOUCH=no-input-device
elif [ -z "$DRV" ]; then
	TOUCH=unbound
else
	TOUCH=wrong-driver
fi

say "3b. interrupt state (is the touch IRQ enabled, and what does gpio25 read)"
IRQ_N=$(awk '/fts2ba61y/ { sub(/:.*/, "", $1); print $1; exit }' "$PROC/interrupts" 2>/dev/null)
IRQ_N=${IRQ_N:-?}
IRQ_COUNT=$(awk '/fts2ba61y/ { s = 0; for (i = 2; i <= NF; i++) { if ($i ~ /^[0-9]+$/) s += $i; else break } print s; exit }' "$PROC/interrupts" 2>/dev/null)
echo "touch irq: $IRQ_N   count: ${IRQ_COUNT:-?}"
IRQ_STATE=unknown
IRQ_DBG="$DEBUGFS/irq/irqs/$IRQ_N"
if [ "$IRQ_N" != "?" ] && [ -r "$IRQ_DBG" ]; then
    grep -E 'depth|istate|status|IRQS_DISABLED|IRQD_IRQ_DISABLED' "$IRQ_DBG" 2>/dev/null | sed 's/^/  /'
    if grep -qE 'IRQS_DISABLED|IRQD_IRQ_DISABLED|depth:[[:space:]]*[1-9]' "$IRQ_DBG" 2>/dev/null; then
        IRQ_STATE=disabled
    else
        IRQ_STATE=enabled
    fi
else
    echo "no debugfs irq state for irq $IRQ_N (debugfs not mounted, or not readable)"
fi
GPIO_RAW=$(awk -v g="gpio25" '$1 == g { print $4; found = 1; exit } END { if (!found) print "?" }' "$DEBUGFS/gpio" 2>/dev/null)
case "$GPIO_RAW" in hi|high) GPIO_STATE=high ;; lo|low) GPIO_STATE=low ;; *) GPIO_STATE=unknown ;; esac
echo "gpio25: ${GPIO_RAW:-?} ($GPIO_STATE)"

say "3c. touch IRQ handler thread (is the ONESHOT thread stuck?)"
THREAD_STATE=none
for p in "$PROC"/[0-9]*; do
    [ -r "$p/comm" ] || continue
    read -r comm < "$p/comm" 2>/dev/null || continue
    case "$comm" in irq/*fts2ba6*) ;; *) continue ;; esac
    pid=${p##*/}
    pstat=$(cat "$p/stat" 2>/dev/null)
    rest=${pstat##*) }
    state=${rest%% *}
    wchan=$(cat "$p/wchan" 2>/dev/null)
    THREAD_STATE=${state:-?}
    echo "thread: pid $pid comm $comm state ${state:-?} wchan ${wchan:-?}"
    if [ -r "$p/stack" ]; then sed 's/^/  stack: /' "$p/stack" 2>/dev/null; else echo "  stack: not readable"; fi
done
[ "$THREAD_STATE" = none ] && echo "no irq handler thread for fts2ba61y"

say "4. keys"
KEY_LINES=$(awk 'BEGIN { RS = ""; FS = "\n" }
{
	hit = 0
	for (i = 1; i <= NF; i++) {
		if ($i ~ /^N: / && tolower($i) ~ /pwrkey|resin|gpio-keys|volume|key/) hit = 1
	}
	if (hit) for (i = 1; i <= NF; i++) if ($i ~ /^[NH]: /) print $i
}' "$PROC/bus/input/devices" 2>/dev/null)
if [ -n "$KEY_LINES" ]; then
	printf '%s\n' "$KEY_LINES"
	KEY_N=$(printf '%s\n' "$KEY_LINES" | grep -c '^N: ')
else
	KEY_N=0
	echo "no key input device found"
fi
echo "key input devices: $KEY_N (healthy: 3, power / volume-down / volume-up)"
if [ "$KEY_N" -ge 3 ]; then KEYS=ok; else KEYS=partial; fi

say "5. verdict"
echo "EVDEV=$EVDEV"
echo "BTF=$BTF"
echo "TOUCH=$TOUCH"
echo "KEYS=$KEYS"
echo "IRQ=$IRQ_STATE"
echo "GPIO25=$GPIO_STATE"
echo "IRQ_THREAD=$THREAD_STATE"
