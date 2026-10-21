#!/usr/bin/env bash
# PC-side test of scripts/phone-sleep-probe.sh (docs/06 rule 3). Fake /sys /proc /etc /home trees and stubs for dmesg / journalctl / systemctl. Checks: every section
# is printed, the values come from the right files, the kernel-log timeline counts the suspend entries, the journal lines are filtered, comments are dropped from
# the config files, a persistent journal is detected, the probe is READ-ONLY (the whole fake tree and the temp dir are byte-identical afterwards), and it
# refuses to run as a non-root user. Run with bash. Usage: bash scripts/test-phone-sleep-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-sleep-probe.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

D="$W/fake"
mkdir -p "$D/bin" "$D/tmp" "$D/proc/bus/input" "$D/sys/power/suspend_stats" "$D/sys/devices/system/cpu/cpuidle" "$D/sys/devices/system/cpu/cpu0/cpuidle/state0" \
	"$D/sys/devices/system/cpu/cpu0/cpuidle/state1" "$D/sys/class/wakeup/wakeup0" "$D/sys/class/wakeup/wakeup1" "$D/sys/class/input/input0/device/power" \
	"$D/sys/bus/platform/devices/3d00000.gpu/power" "$D/sys/bus/platform/devices/ae94000.dsi/power" "$D/sys/bus/platform/devices/a90000.spi/power" \
	"$D/sys/bus/platform/devices/unrelated.thing/power" "$D/sys/class/devfreq/3d00000.gpu" "$D/sys/class/rtc/rtc0" "$D/sys/class/power_supply/battery" \
	"$D/sys/class/drm/card1-DSI-1" "$D/sys/class/backlight/ae94000.dsi.0" "$D/sys/firmware/devicetree/base/gpio-keys/key-vol-up" \
	"$D/etc/systemd/logind.conf.d" "$D/etc/xdg" "$D/home/user/.config" "$D/journal"
echo "freeze mem disk" > "$D/sys/power/state"; echo "s2idle [deep]" > "$D/sys/power/mem_sleep"; echo 1 > "$D/sys/power/pm_async"; echo 7 > "$D/sys/power/wakeup_count"
echo 2 > "$D/sys/power/suspend_stats/success"; echo 0 > "$D/sys/power/suspend_stats/fail"; echo "-" > "$D/sys/power/suspend_stats/last_failed_dev"
echo psci_idle > "$D/sys/devices/system/cpu/cpuidle/current_driver"; echo menu > "$D/sys/devices/system/cpu/cpuidle/current_governor"
echo WFI > "$D/sys/devices/system/cpu/cpu0/cpuidle/state0/name"; echo 123 > "$D/sys/devices/system/cpu/cpu0/cpuidle/state0/usage"
echo cpu-sleep > "$D/sys/devices/system/cpu/cpu0/cpuidle/state1/name"; echo 456 > "$D/sys/devices/system/cpu/cpu0/cpuidle/state1/usage"
echo pwrkey > "$D/sys/class/wakeup/wakeup0/name"; echo 99999 > "$D/sys/class/wakeup/wakeup0/total_time_ms"; echo 5 > "$D/sys/class/wakeup/wakeup0/wakeup_count"
echo alarmtimer > "$D/sys/class/wakeup/wakeup1/name"; echo 10 > "$D/sys/class/wakeup/wakeup1/total_time_ms"
: > "$D/sys/firmware/devicetree/base/gpio-keys/key-vol-up/wakeup-source"
printf 'I: Bus=0019\nN: Name="gpio-keys"\nH: Handlers=kbd event0 \n' > "$D/proc/bus/input/devices"
echo gpio-keys > "$D/sys/class/input/input0/name"; echo enabled > "$D/sys/class/input/input0/device/power/wakeup"
echo suspended > "$D/sys/bus/platform/devices/3d00000.gpu/power/runtime_status"; echo auto > "$D/sys/bus/platform/devices/3d00000.gpu/power/control"
echo active > "$D/sys/bus/platform/devices/ae94000.dsi/power/runtime_status"; echo active > "$D/sys/bus/platform/devices/a90000.spi/power/runtime_status"
echo active > "$D/sys/bus/platform/devices/unrelated.thing/power/runtime_status"
echo 680000000 > "$D/sys/class/devfreq/3d00000.gpu/cur_freq"; echo msm-adreno-tz > "$D/sys/class/devfreq/3d00000.gpu/governor"
echo rtc0 > "$D/sys/class/rtc/rtc0/name"; echo 2026-10-21 > "$D/sys/class/rtc/rtc0/date"
echo Battery > "$D/sys/class/power_supply/battery/type"; echo Discharging > "$D/sys/class/power_supply/battery/status"; echo 61 > "$D/sys/class/power_supply/battery/capacity"
echo enabled > "$D/sys/class/drm/card1-DSI-1/enabled"; echo On > "$D/sys/class/drm/card1-DSI-1/dpms"
echo 0 > "$D/sys/class/backlight/ae94000.dsi.0/bl_power"; echo 2047 > "$D/sys/class/backlight/ae94000.dsi.0/brightness"
echo "1234.56 9999.00" > "$D/proc/uptime"; echo "0.10 0.20 0.30 1/200 999" > "$D/proc/loadavg"; echo 'console=tty0 clk_ignore_unused' > "$D/proc/cmdline"
printf '# a comment\n\n[Login]\nHandlePowerKey=suspend\n; another\n' > "$D/etc/systemd/logind.conf"
printf '[AC][SuspendAndShutdown]\nAutoSuspendAction=1\nAutoSuspendIdleTimeoutSec=900\n' > "$D/home/user/.config/powerdevilrc"
printf '[Daemon]\nAutolock=false\n' > "$D/home/user/.config/kscreenlockerrc"
cat > "$D/dmesg" <<'EOF'
[    1.000000] calling  something_init+0x0/0x10 @ 1
[  100.000000] PM: suspend entry (s2idle)
[  100.400000] msm_dpu ae01000.display-controller: error -110 while resuming
[  130.000000] PM: suspend exit
[  200.000000] PM: suspend entry (s2idle)
[  230.000000] PM: suspend exit
[  231.000000] ordinary line
EOF
printf '#!/bin/sh\ncat "%s/dmesg"\n' "$D" > "$D/bin/dmesg"
cat > "$D/bin/journalctl" <<EOF
#!/bin/sh
case "\$*" in
*--disk-usage*) echo "Archived and active journals take up 8.0M in the file system." ;;
*--list-boots*) echo " 0 abcdef Wed 2026-10-21 08:26:00 EEST—Wed 2026-10-21 13:00:00 EEST" ;;
*-u*) echo "Oct 21 12:00:01 phone systemd[1]: Starting System Suspend..." ;;
*)  echo "Oct 21 12:00:00 phone systemd-logind[300]: Suspending..."
    echo "Oct 21 12:00:30 phone systemd-logind[300]: Power key pressed short."
    echo "Oct 21 12:00:31 phone audit[1]: should be filtered out audit suspend"
    echo "Oct 21 12:00:32 phone kernel: unrelated message about disk" ;;
esac
EOF
printf '#!/bin/sh\ncase "$*" in *is-active*) echo active ;; *list-units*) echo "systemd-logind.service loaded active running Login Service" ;; esac\n' > "$D/bin/systemctl"
chmod +x "$D/bin/dmesg" "$D/bin/journalctl" "$D/bin/systemctl"

run() {
	timeout 60 env SYSFS="$D/sys" PROC="$D/proc" ETC="$D/etc" HOMES="$D/home" DMESG="$D/bin/dmesg" JOURNALCTL="$D/bin/journalctl" SYSTEMCTL="$D/bin/systemctl" \
		JOURNALDIR="$D/journal" TMPDIR="$D/tmp" ID_U="${ID_U_T-0}" bash "$SCRIPT" > "$W/out" 2>&1
}
snap() { (cd "$D" && find . -path ./out -prune -o -print0 | sort -z | xargs -0 -r ls -ld --time-style=+ 2>/dev/null; find . -path ./out -prune -o -type f -print0 | sort -z | xargs -0 -r cksum); }

before=$(snap)
echo "== run as root (persistent journal)"
run; rc=$?; O="$W/out"
[ "$rc" = 0 ] && ok "exit 0" || { bad "exit $rc"; cat "$O"; }
for s in "0. when" "1. power configuration" "2. cpuidle" "3. wakeup sources" "4. input devices" "5. kernel log timeline" "6. runtime PM" "7. journal of this boot" "8. sleep configuration" "9. RTC and battery" "10. current state"; do
	expect "$O" "section '$s'" "^== $s"
done
expect "$O" "uptime" "^uptime \(boot clock, counts suspended time\): 1234.56 s"
expect "$O" "cmdline" "^cmdline: console=tty0 clk_ignore_unused"
expect "$O" "mem_sleep" "^/sys/power/mem_sleep: s2idle \[deep\]"
expect "$O" "state" "^/sys/power/state: freeze mem disk"
expect "$O" "suspend_stats" "^   success = 2"
expect "$O" "cpuidle driver" "^driver: psci_idle"
expect "$O" "cpuidle state" "^cpu0 state1 name=cpu-sleep usage=456"
expect "$O" "wakeup source with the biggest total time first" "^   pwrkey active=.* wakeups=5 total_ms=99999"
[ "$(grep -n 'pwrkey active' "$O" | head -1 | cut -d: -f1)" -lt "$(grep -n 'alarmtimer active' "$O" | head -1 | cut -d: -f1)" ] && ok "sorted by total time" || bad "wakeup sources not sorted"
expect "$O" "device tree wakeup-source" "/gpio-keys/key-vol-up/wakeup-source"
expect "$O" "input device and its wake setting" "^   input0 gpio-keys: power/wakeup=enabled"
expect "$O" "suspend entry count" "^suspend entries: 2 +suspend exits: 2"
expect "$O" "timeline keeps the -110 line with its line number" "^[0-9]+:\[  100.400000\] msm_dpu ae01000.display-controller: error -110"
reject "$O" "initcall noise filtered from the timeline" "^[0-9]+:.*calling +something_init"
expect "$O" "tail of the kernel log" "ordinary line"
expect "$O" "runtime PM of the gpu" "^3d00000.gpu: status=suspended control=auto"
reject "$O" "an unrelated device is not listed" "unrelated.thing"
expect "$O" "devfreq" "^devfreq 3d00000.gpu: cur=680000000 governor=msm-adreno-tz"
expect "$O" "persistent journal detected" "^persistent journal: yes"
expect "$O" "journal: suspend line" "systemd-logind\[300\]: Suspending"
expect "$O" "journal: power key line" "Power key pressed short"
reject "$O" "journal: audit lines filtered" "should be filtered out audit"
reject "$O" "journal: unrelated lines filtered" "unrelated message about disk"
expect "$O" "sleep units section" "Starting System Suspend"
expect "$O" "logind.conf: setting kept" "^HandlePowerKey=suspend"
reject "$O" "logind.conf: comments dropped" "^# a comment|^; another"
expect "$O" "powerdevilrc read" "^AutoSuspendIdleTimeoutSec=900"
expect "$O" "kscreenlockerrc read" "^Autolock=false"
expect "$O" "systemd units listed" "systemd-logind.service loaded active running"
expect "$O" "battery" "^battery: type=Battery status=Discharging capacity=61"
expect "$O" "display state" "^card1-DSI-1: enabled=enabled dpms=On"
expect "$O" "plasma state" "^plasma-mobile.service: active"
expect "$O" "done" "^done"
after=$(snap)
if [ "$before" = "$after" ]; then ok "READ-ONLY: the fake tree and the temp dir are unchanged"; else bad "the probe changed something"; diff <(echo "$before") <(echo "$after") | head -n 10; fi
[ -z "$(ls -A "$D/tmp")" ] && ok "no temp file written" || bad "temp dir not empty"

echo "== volatile journal"
rmdir "$D/journal"
run; O="$W/out"
expect "$O" "volatile detected" "^persistent journal: no"

echo "== refusal"
ID_U_T=1 run; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"

echo "== static checks"
bash --posix -n "$SCRIPT" && ok "bash --posix -n" || bad "bash --posix -n"
if grep -n -E '(^|[^<>2&0-9])> *[^ &/]' "$SCRIPT" | grep -v -E '^[0-9]+:\s*#' | grep -v -E '> */dev/null|2>&1' >/dev/null; then bad "the script has a redirection that writes a file"; else ok "no file-writing redirection in the script"; fi
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
