#!/bin/sh
# Controlled FIRST START of Plasma Mobile on the phone (docs/10 section 9). Runs on the phone as root
# (sudo sh phone-plasma-start.sh), POSIX sh / busybox ash. Starts plasma-mobile.service BY HAND (it is not enabled at boot),
# watches it for DUR seconds while YOU use the phone, collects the evidence, then stops it again and gives the console back.
#
#   DUR=240   seconds to keep the session up before collecting (default 240)
#   KEEP=0    1 = leave the session running at the end (default: stop it and restore getty on tty1)
#   PROFILE=default|software|softpipe   applied through a TEMPORARY env script /etc/xdg/plasma-workspace/env/90-dm1q-test.sh that
#             startplasma sources and whose variables reach every user service (removed again at the end, unless KEEP=1):
#               default   nothing (Mesa picks llvmpipe through the msm render node's fallback)
#               software  QT_QUICK_BACKEND=software: Qt Quick apps render on the CPU into shm buffers (no GL in the clients);
#                         KWin still uses GL (llvmpipe)
#               softpipe  software + LIBGL_ALWAYS_SOFTWARE=1 + GALLIUM_DRIVER=softpipe: Mesa's non-JIT software rasteriser for KWin
#                         and everything else that needs GL (very slow, but it needs no LLVM JIT)
#             KWIN_COMPOSE=Q is NOT offered: KWin 6.8's DRM platform answers "Configured compositor not supported by Platform"
#             and exits (docs/10 section 9.2).
#   MAXTEMP=95  abort the window early when the hottest thermal zone reaches this many degrees C
#
# Why PROFILE exists: the first run (notes/2026-10-17-plasma-start, docs/10 section 9.1) showed every GL client (ksplashqml, plasma-keyboard,
# plasmashell, kwin_wayland itself) dying with SIGILL inside llvmpipe's JIT code, which makes the session exit and restart.
#
# It also makes sure /tmp/.X11-unix and /tmp/.ICE-unix exist (mode 1777), which systemd's tmpfiles normally creates; they were missing
# ("kwin_xwl: /tmp/.X11-unix does not exist"). They live in /tmp and are not removed again.
#
# Safety: the unit has OnFailure=getty@tty1 and Restart=always (restart every 5 s); this script aborts the window early after
# 3 restarts (crash loop) and ALWAYS stops the unit again on exit, on Ctrl-C and on a dropped ssh (trap), unless KEEP=1.
# If the screen hangs completely, the phone can still be reset with power + volume-down. It only starts and stops units; the
# files it ever writes are the temporary env script of PROFILE=software|softpipe (removed again) and the two socket directories
# in /tmp. It does not touch /boot, so
# docs/06 rule 3 does not apply.
#
# While it runs, on the phone: touch the screen, press the power key (short), the volume keys, open the quick settings
# (swipe down), move the brightness slider, open the on-screen keyboard (a text field), then wait for the script to finish.
#
# Test overrides (scripts/test-phone-plasma-start.sh): ROOT, SYSTEMCTL, JOURNALCTL, LOGINCTL, PS, PGREP, SUDO, DMESG, POLL, DUR, KEEP.
ROOT="${ROOT:-}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"; JOURNALCTL="${JOURNALCTL:-journalctl}"; LOGINCTL="${LOGINCTL:-loginctl}"
PS="${PS:-ps}"; PGREP="${PGREP:-pgrep}"; SUDO="${SUDO:-sudo}"; DMESG="${DMESG:-dmesg}"
POLL="${POLL:-10}"; DUR="${DUR:-240}"; KEEP="${KEEP:-0}"; PROFILE="${PROFILE:-default}"; MAXTEMP="${MAXTEMP:-95}"
ENVFILE="$ROOT/etc/xdg/plasma-workspace/env/90-dm1q-test.sh"
ENVWRITTEN=0
UNIT=plasma-mobile.service
UID_UI=10000
BL="$ROOT/sys/class/backlight/ae94000.dsi.0"

sec() { echo; echo "=== $1"; }
have() { command -v "$1" >/dev/null 2>&1; }
sc() { if have "$SYSTEMCTL"; then "$SYSTEMCTL" "$@" 2>&1; else echo "  (no systemctl)"; fi; }
prop() { sc show -p "$1" --value "$UNIT" | head -n 1; }
hottest_n() {
	m=0
	for t in "$ROOT"/sys/class/thermal/thermal_zone*/temp; do
		[ -r "$t" ] || continue
		v="$(cat "$t" 2>/dev/null)"; [ -n "$v" ] && [ "$v" -gt "$m" ] && m="$v"
	done
	echo "$((m / 1000))"
}
hottest() { echo "$(hottest_n) C"; }
rmenv() { if [ "$ENVWRITTEN" = 1 ] && [ "$KEEP" != 1 ]; then rm -f "$ENVFILE" && echo "removed the temporary env script ${ENVFILE#"$ROOT"}"; ENVWRITTEN=0; fi; }
psall() { "$PS" -eo pid,ppid,user,args 2>/dev/null || "$PS" aux 2>/dev/null || "$PS" 2>&1; }  # busybox / procps differ
nproc_of() { "$PGREP" "$1" 2>/dev/null | wc -l | tr -d ' '; }
memused() { awk '/^MemTotal/ {t=$2} /^MemAvailable/ {a=$2} END { printf "%d MB", (t - a) / 1024 }' "$ROOT/proc/meminfo" 2>/dev/null; }

STARTED=0
stopit() {
	[ "$STARTED" = 1 ] || { rmenv; return 0; }
	STARTED=0
	if [ "$KEEP" = 1 ]; then echo "KEEP=1: the session is left running (stop it with: systemctl stop $UNIT; systemctl start getty@tty1.service; a temporary env script, if any, stays: rm ${ENVFILE#"$ROOT"})"; return 0; fi
	echo "--- stopping $UNIT and restoring getty on tty1"
	sc stop "$UNIT"
	sc start getty@tty1.service
	rmenv
}
trap 'stopit; exit 130' INT TERM HUP
trap 'stopit' EXIT

sec "1 preflight"
echo "uptime: $(cut -d' ' -f1 "$ROOT/proc/uptime" 2>/dev/null) s since boot; kernel: $(uname -r 2>/dev/null)"
if [ ! -e "$ROOT/usr/lib/systemd/system/$UNIT" ]; then echo "$UNIT is not installed: abort"; echo "done"; exit 1; fi
echo "$UNIT: enabled=$(sc is-enabled "$UNIT" | tr '\n' ' ') active=$(sc is-active "$UNIT" | tr '\n' ' ')"
echo "getty@tty1: active=$(sc is-active getty@tty1.service | tr '\n' ' ')"
echo "/etc/default_user: $(cat "$ROOT/etc/default_user" 2>/dev/null || echo '(absent: the generator falls back to uid/gid 10000)')"
echo "ui user: $(grep "^[^:]*:[^:]*:$UID_UI:" "$ROOT/etc/passwd" 2>/dev/null)"
echo "usb-moded: $(sc is-enabled usb-moded.service | tr '\n' ' ')  usb-signaller: enabled=$(sc is-enabled usb-signaller.service | tr '\n' ' ') active=$(sc is-active usb-signaller.service | tr '\n' ' ')"
echo "baseline: load $(cut -d' ' -f1-3 "$ROOT/proc/loadavg" 2>/dev/null), mem used $(memused), hottest $(hottest)"
[ -d "$BL" ] && echo "backlight before: $(cat "$BL/brightness" 2>/dev/null)/$(cat "$BL/max_brightness" 2>/dev/null)"
ls -l "$ROOT/dev/dri" 2>&1
if [ "$(sc is-active "$UNIT" | tr -d '\n')" = active ]; then echo "$UNIT is already running: not starting a second time; will only observe and collect"; else :; fi
echo "profile: $PROFILE"
case "$PROFILE" in
default) ;;
software)
	mkdir -p "$(dirname "$ENVFILE")"
	printf '%s\n' '# dm1q experiment profile (scripts/phone-plasma-start.sh): Qt Quick on the CPU. Temporary: removed when the test ends.' \
		'export QT_QUICK_BACKEND=software' > "$ENVFILE" && ENVWRITTEN=1 ;;
softpipe)
	mkdir -p "$(dirname "$ENVFILE")"
	printf '%s\n' '# dm1q experiment profile (scripts/phone-plasma-start.sh): no llvmpipe JIT. Temporary: removed when the test ends.' \
		'export QT_QUICK_BACKEND=software' 'export LIBGL_ALWAYS_SOFTWARE=1' 'export GALLIUM_DRIVER=softpipe' > "$ENVFILE" && ENVWRITTEN=1 ;;
*) echo "unknown PROFILE '$PROFILE' (default, software, softpipe): abort"; echo "done"; exit 1 ;;
esac
if [ "$ENVWRITTEN" = 1 ]; then echo "wrote the temporary env script ${ENVFILE#"$ROOT"}:"; cat "$ENVFILE"; fi
echo "--- X11 / ICE socket directories (systemd tmpfiles x11.conf normally creates them)"
for f in "$ROOT"/usr/lib/tmpfiles.d/*x11* "$ROOT"/usr/lib/tmpfiles.d/tmp.conf; do [ -e "$f" ] && echo "tmpfiles.d: ${f##*/}"; done
for d in /tmp/.X11-unix /tmp/.ICE-unix; do
	if [ ! -d "$ROOT$d" ]; then mkdir -p "$ROOT$d" && chmod 1777 "$ROOT$d" && echo "created $d (was missing)"; else echo "$d exists"; fi
done
T0="$(date '+%Y-%m-%d %H:%M:%S')"
echo "T0: $T0"

sec "2 start (watch the screen now)"
if [ "$(sc is-active "$UNIT" | tr -d '\n')" != active ]; then
	sc start "$UNIT"
	STARTED=1
fi

sec "3 monitoring for ${DUR}s (poll ${POLL}s). USE THE PHONE: touch, power key, volume keys, quick settings, brightness slider, keyboard."
W=0; ABORT=""
while [ "$W" -lt "$DUR" ]; do
	sleep "$POLL"; W=$((W + POLL))
	NR="$(prop NRestarts)"
	echo "t=${W}s state=$(prop ActiveState)/$(prop SubState) pid=$(prop MainPID) restarts=${NR:-?} kwin=$(nproc_of kwin_wayland) load=$(cut -d' ' -f1 "$ROOT/proc/loadavg" 2>/dev/null) mem=$(memused) hot=$(hottest)"
	if [ -n "$NR" ] && [ "$NR" -ge 3 ] 2>/dev/null; then ABORT="crash loop: $NR restarts"; echo "ABORT: $ABORT"; break; fi
	HT="$(hottest_n)"
	if [ "$HT" -ge "$MAXTEMP" ] 2>/dev/null; then ABORT="too hot: ${HT} C >= ${MAXTEMP} C"; echo "ABORT: $ABORT"; break; fi
done

sec "4 evidence"
echo "--- unit state"
sc status "$UNIT" --no-pager -n 0 | head -20
echo "--- journal of $UNIT since T0 (first 250 lines)"
"$JOURNALCTL" -u "$UNIT" --since "$T0" --no-pager 2>&1 | head -250
echo "--- journal of the UI user (uid $UID_UI: kwin, plasmashell, ksplash ... as user units), filtered for the interesting lines (first 200)"
"$JOURNALCTL" "_UID=$UID_UI" --since "$T0" --no-pager 2>&1 | grep -iE 'kwin|egl|gbm|drm|libinput|renderer|compositor|opengl|llvmpipe|swrast|gallium|mesa|failed|error|fatal|cannot|can.t|illegal|SIGILL|abort|crash|exited|splash|wayland' | grep -vE 'Stack trace|Module lib|^ +#' | head -200
echo "--- journal warnings and errors since T0, all units, WITHOUT the coredump stack blocks (first 120)"
"$JOURNALCTL" --since "$T0" -p warning --no-pager 2>&1 | grep -vE '^ +(Module|Stack trace|#[0-9]|ELF object)|^ *$' | head -120
echo "--- coredumps since T0"
if have coredumpctl; then
	coredumpctl list --no-pager --since "$T0" 2>&1 | tail -n 25
	for n in ksplashqml plasma-keyboard plasmashell kwin_wayland; do
		echo "- coredumpctl info $n (signal, command, last 12 lines)"; coredumpctl info --no-pager "$n" 2>&1 | grep -E 'Signal:|Timestamp:|Command Line:|Stack trace|#[0-9] ' | head -12
	done
else
	echo "  (no coredumpctl)"
fi
echo "--- CPU identity and features (llvmpipe JIT picks its target from this)"
grep -E '^(CPU part|CPU implementer)' "$ROOT/proc/cpuinfo" 2>/dev/null | sort | uniq -c
grep -m1 -i '^Features' "$ROOT/proc/cpuinfo" 2>/dev/null
if [ -r "$ROOT/proc/config.gz" ]; then zcat "$ROOT/proc/config.gz" 2>/dev/null | grep -E 'CONFIG_ARM64_(SVE|SME|PTR_AUTH|MTE|BTI)=' ; else echo "  (no /proc/config.gz; /boot/config: $(grep -E 'CONFIG_ARM64_(SVE|SME)=' "$ROOT/boot/config" 2>/dev/null | tr '\n' ' '))"; fi
"$DMESG" 2>/dev/null | grep -iE 'sve|sme|hwcap|CPU features|detected:' | head -20
echo "--- UI user's systemd environment (did the env script propagate?)"
if have "$SUDO"; then "$SUDO" -u "$(awk -F: -v u="$UID_UI" '$3 == u { print $1; exit }' "$ROOT/etc/passwd" 2>/dev/null)" env XDG_RUNTIME_DIR="/run/user/$UID_UI" systemctl --user show-environment 2>&1 | grep -E 'QT_QUICK|KWIN|LANG|WAYLAND|XDG_VTNR|XDG_SESSION' ; fi
echo "--- processes"
psall | grep -E 'kwin|plasma|startplasma|maliit|keyboard|kded|krunner|pipewire|powerdevil|upower|ModemManager|NetworkManager|usb-' | grep -v grep | cut -c1-200
KP="$("$PGREP" -n -x kwin_wayland 2>/dev/null)"   # exact name: kwin_wayland_wrapper holds no devices
if [ -n "$KP" ]; then
	echo "--- kwin_wayland pid $KP"
	echo "environment (selected):"
	tr '\0' '\n' < "$ROOT/proc/$KP/environ" 2>/dev/null | grep -E '^(QT_|KWIN|MESA|XDG_|WAYLAND|LIBGL|LIBSEAT|LANG|DBUS_SESSION)' | sort
	echo "open DRM / input fds:"
	for f in "$ROOT/proc/$KP"/fd/*; do readlink "$f" 2>/dev/null; done | grep -E '^/dev/(dri|input)' | sort | uniq -c
	grep -E 'VmRSS|Threads' "$ROOT/proc/$KP/status" 2>/dev/null
else
	echo "no kwin_wayland process found"
fi
echo "--- sessions"
if have "$LOGINCTL"; then "$LOGINCTL" list-sessions 2>&1; "$LOGINCTL" list-seats 2>&1; fi
echo "--- kscreen-doctor -o as the UI user (outputs, scale, rotation)"
UI_NAME="$(awk -F: -v u="$UID_UI" '$3 == u { print $1; exit }' "$ROOT/etc/passwd" 2>/dev/null)"
if have "$SUDO" && have kscreen-doctor; then
	found=0
	for s in "$ROOT/run/user/$UID_UI"/wayland-[0-9]*; do
		[ -e "$s" ] || continue
		case "$s" in *.lock) continue ;; esac
		found=1; echo "socket ${s##*/}:"
		"$SUDO" -u "${UI_NAME:-user}" env XDG_RUNTIME_DIR="/run/user/$UID_UI" WAYLAND_DISPLAY="${s##*/}" kscreen-doctor -o 2>&1 | head -30
	done
	[ "$found" = 1 ] || echo "  (no wayland socket in /run/user/$UID_UI)"
else
	echo "  (no sudo or kscreen-doctor)"
fi
echo "--- backlight after: $(cat "$BL/brightness" 2>/dev/null)/$(cat "$BL/max_brightness" 2>/dev/null)"
echo "--- kernel messages since boot about msm / dpu / smmu faults / touch (last 60 matching lines)"
"$DMESG" 2>/dev/null | grep -iE 'msm|dpu|drm|smmu.*(fault|unhandled)|fts|sec_|input' | tail -n 60
echo "--- number of arm-smmu faults since boot: $("$DMESG" 2>/dev/null | grep -ciE 'arm-smmu.*(fault|unhandled)')"
echo "--- top"
if have top; then top -bn1 2>/dev/null | head -18; fi
echo "--- final: load $(cut -d' ' -f1-3 "$ROOT/proc/loadavg" 2>/dev/null), mem used $(memused), hottest $(hottest)"
[ -n "$ABORT" ] && echo "RESULT: aborted early ($ABORT)" || echo "RESULT: window of ${DUR}s completed"

sec "5 stop"
stopit
echo "unit after: active=$(sc is-active "$UNIT" | tr '\n' ' ')  getty@tty1: $(sc is-active getty@tty1.service | tr '\n' ' ')"
echo
echo "done"
