#!/bin/sh
# Phone-side sleep / wake probe (docs/08 section 2.15: "the power button takes 20-30 s to wake the phone after a long sleep"). POSIX sh, run as root
# (collect-phone-state.sh --sleep-probe does that). READ-ONLY: it reads sysfs / procfs / the kernel log / the journal and writes nothing (not even a temp file).
#
# Run it AFTER a slow wake, in the same boot (the journal and the kernel ring buffer of this boot are what it reads; a reboot loses them unless the journal
# is persistent, which section 7 reports). The question it answers: did the system really suspend (a "PM: suspend entry" line), who woke it and when, and what
# took the 20-30 s (a device that resumes slowly or times out, the display / GPU path, or userspace)?
# Sections:  1 power configuration   2 cpuidle   3 wakeup sources   4 input devices and their wake setting   5 kernel log timeline   6 runtime PM of the
#            display / GPU / storage / SPI devices   7 journal (this boot): logind, powerdevil, kwin, suspend units, and what is stored   8 sleep configuration
#            (logind, sleep.conf, PowerDevil, screen locker)   9 RTC and battery   10 current state
# Env (the PC-side test uses them): SYSFS PROC DMESG JOURNALCTL SYSTEMCTL ETC HOMES JOURNALDIR ID_U
SYSFS="${SYSFS:-/sys}"
PROC="${PROC:-/proc}"
DMESG="${DMESG:-dmesg}"
JOURNALCTL="${JOURNALCTL:-journalctl}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
ETC="${ETC:-/etc}"
HOMES="${HOMES:-/home}"
JOURNALDIR="${JOURNALDIR:-/var/log/journal}"
[ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }

say() { echo; echo "== $*"; }
rd() { _v=""; if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null; fi; printf '%s' "$_v"; }
kv() { echo "$1: $(rd "$2")"; }
conf() { # print the non-comment, non-empty lines of the given files
	for f in "$@"; do
		[ -f "$f" ] || continue
		echo "--- $f"
		grep -v -E '^[[:space:]]*(#|;|$)' "$f" 2>/dev/null | cut -c1-200 | head -n 60
	done
}

say "0. when"
echo "date: $(date 2>/dev/null)"
read -r up _ < "$PROC/uptime" 2>/dev/null
echo "uptime (boot clock, counts suspended time): ${up:-?} s"
echo "load: $(cut -d' ' -f1-3 "$PROC/loadavg" 2>/dev/null)"
echo "kernel: $(uname -r 2>/dev/null)"
echo "cmdline: $(cut -c1-300 "$PROC/cmdline" 2>/dev/null)"

say "1. power configuration"
kv "/sys/power/state" "$SYSFS/power/state"
kv "/sys/power/mem_sleep" "$SYSFS/power/mem_sleep"
kv "/sys/power/pm_async" "$SYSFS/power/pm_async"
kv "/sys/power/wakeup_count" "$SYSFS/power/wakeup_count"
kv "/sys/power/pm_freeze_timeout" "$SYSFS/power/pm_freeze_timeout"
kv "/sys/power/pm_debug_messages" "$SYSFS/power/pm_debug_messages"
if [ -d "$SYSFS/power/suspend_stats" ]; then
	echo "suspend_stats:"
	for f in "$SYSFS"/power/suspend_stats/*; do
		[ -f "$f" ] && echo "   $(basename "$f") = $(rd "$f")"
	done
elif [ -r "$SYSFS/kernel/debug/suspend_stats" ]; then
	echo "suspend_stats (debugfs):"
	head -n 30 "$SYSFS/kernel/debug/suspend_stats" | sed 's/^/   /'
else
	echo "suspend_stats: not available"
fi

say "2. cpuidle"
kv "driver" "$SYSFS/devices/system/cpu/cpuidle/current_driver"
kv "governor" "$SYSFS/devices/system/cpu/cpuidle/current_governor"
for c in cpu0 cpu4 cpu7; do
	for s in "$SYSFS/devices/system/cpu/$c/cpuidle"/state*; do
		[ -d "$s" ] || continue
		echo "$c $(basename "$s") name=$(rd "$s/name") usage=$(rd "$s/usage") time_us=$(rd "$s/time") disabled=$(rd "$s/disable")"
	done
done

say "3. wakeup sources (top 25 by total time; active_count / event_count / wakeup_count / total_time_ms / last_change_ms)"
for w in "$SYSFS"/class/wakeup/wakeup*; do
	[ -d "$w" ] || continue
	echo "$(rd "$w/total_time_ms") $(rd "$w/name") active=$(rd "$w/active_count") events=$(rd "$w/event_count") wakeups=$(rd "$w/wakeup_count") total_ms=$(rd "$w/total_time_ms") max_ms=$(rd "$w/max_time_ms") last_change_ms=$(rd "$w/last_change_ms") prevent_suspend_ms=$(rd "$w/prevent_suspend_time_ms")"
done | sort -rn | head -n 25 | cut -d' ' -f2- | sed 's/^/   /'
if [ -d "$SYSFS/firmware/devicetree/base" ]; then
	echo "wakeup-source properties in the device tree (first 20):"
	find "$SYSFS/firmware/devicetree/base" -name wakeup-source 2>/dev/null | head -n 20 | sed "s|^$SYSFS/firmware/devicetree/base||; s/^/   /"
fi

say "4. input devices and their wake setting"
awk '/^N: Name=/ { name = $0 } /^H: Handlers=/ { print name " | " $0 }' "$PROC/bus/input/devices" 2>/dev/null | cut -c1-200 | sed 's/^/   /'
for d in "$SYSFS"/class/input/input*; do
	[ -d "$d" ] || continue
	w=$(rd "$d/device/power/wakeup")
	[ -n "$w" ] || w=$(rd "$d/power/wakeup")
	echo "   $(basename "$d") $(rd "$d/name"): power/wakeup=${w:-n/a}"
done

say "5. kernel log timeline (suspend / resume / wake / timeouts; line numbers are of the ring buffer; the ring buffer may have wrapped)"
"$DMESG" > /dev/null 2>&1 || echo "dmesg failed"
echo "suspend entries: $("$DMESG" 2>/dev/null | grep -c 'PM: suspend entry')   suspend exits: $("$DMESG" 2>/dev/null | grep -c 'PM: suspend exit')   first line: $("$DMESG" 2>/dev/null | head -n 1 | cut -c1-40)"
"$DMESG" 2>/dev/null | grep -n -i -E 'PM: |suspend|resum|Freezing|Restarting tasks|wakeup|wake-up|wake up|failed to|timed out|timeout|-110|psci|hfi|gmu|a6xx|adreno|nobody cared' | grep -v -E 'initcall|calling ' | tail -n 150 | cut -c1-220
echo "-- last 60 kernel log lines:"
"$DMESG" 2>/dev/null | tail -n 60 | cut -c1-220

say "6. runtime PM of the display / GPU / storage / SPI / PCIe devices"
for d in "$SYSFS"/bus/platform/devices/*; do
	[ -d "$d" ] || continue
	case "$(basename "$d")" in
	*gpu*|*gmu*|*dsi*|*display*|*mdss*|*dpu*|*ufs*|*pcie*|*spi*|*pmic*|*pon*|*pwrkey*) ;;
	*) continue ;;
	esac
	echo "$(basename "$d"): status=$(rd "$d/power/runtime_status") control=$(rd "$d/power/control") autosuspend_ms=$(rd "$d/power/autosuspend_delay_ms") active_ms=$(rd "$d/power/runtime_active_time") suspended_ms=$(rd "$d/power/runtime_suspended_time") wakeup=$(rd "$d/power/wakeup")"
done | head -n 60
for g in "$SYSFS"/class/devfreq/*; do
	[ -d "$g" ] || continue
	echo "devfreq $(basename "$g"): cur=$(rd "$g/cur_freq") governor=$(rd "$g/governor")"
done

say "7. journal of this boot (suspend / sleep / power key / idle / display / powerdevil lines, oldest first, last 250)"
"$JOURNALCTL" --disk-usage 2>&1 | head -n 2
if [ -d "$JOURNALDIR" ]; then echo "persistent journal: yes ($JOURNALDIR)"; else echo "persistent journal: no (volatile: a reboot loses this boot's journal)"; fi
"$JOURNALCTL" --list-boots --no-pager 2>/dev/null | tail -n 3
"$JOURNALCTL" -b --no-pager 2>/dev/null | grep -i -E 'PM: suspend|suspend|resume|sleep|power key|powerkey|power button|idle|dpms|screen ?(off|on)|powerdevil|login1|logind|inhibit|wake|lock' | grep -v -E 'audit|initcall' | tail -n 250 | cut -c1-240
echo "-- systemd sleep units this boot:"
"$JOURNALCTL" -b --no-pager -u systemd-suspend.service -u systemd-sleep.service -u sleep.target -u suspend.target 2>/dev/null | tail -n 30 | cut -c1-220

say "8. sleep configuration"
conf "$ETC/systemd/logind.conf" "$ETC"/systemd/logind.conf.d/*.conf "$ETC/systemd/sleep.conf" "$ETC"/systemd/sleep.conf.d/*.conf
"$SYSTEMCTL" list-units --no-pager --all 2>/dev/null | grep -i -E 'sleep|suspend|powerdevil|upower|elogind|logind' | cut -c1-160
for h in "$HOMES"/*; do
	[ -d "$h/.config" ] || continue
	conf "$h/.config/powerdevilrc" "$h/.config/kscreenlockerrc" "$h/.config/kwinrc"
done
conf "$ETC/xdg/powerdevilrc" "$ETC/xdg/kscreenlockerrc"

say "9. RTC and battery"
for r in "$SYSFS"/class/rtc/rtc*; do
	[ -d "$r" ] || continue
	echo "$(basename "$r"): name=$(rd "$r/name") date=$(rd "$r/date") time=$(rd "$r/time") wakealarm=$(rd "$r/wakealarm")"
done
for p in "$SYSFS"/class/power_supply/*; do
	[ -d "$p" ] || continue
	echo "$(basename "$p"): type=$(rd "$p/type") status=$(rd "$p/status") capacity=$(rd "$p/capacity")"
done

say "10. current state"
echo "plasma-mobile.service: $("$SYSTEMCTL" is-active plasma-mobile.service 2>&1)"
for d in "$SYSFS"/class/drm/card*-DSI-1; do
	[ -d "$d" ] && echo "$(basename "$d"): enabled=$(rd "$d/enabled") dpms=$(rd "$d/dpms")"
done
for b in "$SYSFS"/class/backlight/*; do
	[ -d "$b" ] && echo "backlight $(basename "$b"): bl_power=$(rd "$b/bl_power") brightness=$(rd "$b/brightness")"
done
echo
echo "done"
