#!/usr/bin/env bash
# PC-side test of scripts/phone-plasma-start.sh (docs/06 rule 3). The phone's root is a scratch tree (ROOT=); systemctl,
# journalctl, loginctl, ps, pgrep, sudo, dmesg are stubs (the systemctl stub keeps the unit state in files). Runs with dash
# (closest to busybox ash) and bash. Scenarios:
#   normal    start, monitoring lines, evidence, stop + getty restored, never enable/reboot
#   keep      KEEP=1: started, evidence, NOT stopped
#   crash     the unit restarts 3 times: the window is aborted early, evidence collected, unit stopped
#   missing   the unit file does not exist: abort, nothing started
#   running   the unit is already active: not started again, and NOT stopped at the end (we did not start it)
#   term      SIGTERM during the window: the trap stops the unit and restores getty
# Usage: bash scripts/test-phone-plasma-start.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

mktree() { # $1 dir, $2 unit-present(1/0), $3 initially-active(1/0), $4 crashloop(1/0)
	local D="$1" R="$1/root"
	mkdir -p "$D/bin" "$R/usr/lib/systemd/system" "$R/etc" "$R/proc/4242" "$R/sys/class/backlight/ae94000.dsi.0" \
		"$R/sys/class/thermal/thermal_zone0" "$R/dev/dri" "$R/proc/4242/fd"
	[ "$2" = 1 ] && echo "[Service]" > "$R/usr/lib/systemd/system/plasma-mobile.service"
	printf 'root:x:0:0:root:/root:/bin/ash\nuser:x:10000:10000::/home/user:/bin/ash\n' > "$R/etc/passwd"
	echo "123.45 100.0" > "$R/proc/uptime"; echo "0.30 0.20 0.10 1/100 1" > "$R/proc/loadavg"
	printf 'MemTotal: 6700000 kB\nMemAvailable: 6000000 kB\n' > "$R/proc/meminfo"
	echo 2047 > "$R/sys/class/backlight/ae94000.dsi.0/brightness"; echo 2047 > "$R/sys/class/backlight/ae94000.dsi.0/max_brightness"
	echo 41000 > "$R/sys/class/thermal/thermal_zone0/temp"; touch "$R/dev/dri/card1"
	printf 'LANG=C.UTF-8\0XDG_SEAT=seat0\0QT_QPA_PLATFORM=wayland\0HOME=/home/user\0' > "$R/proc/4242/environ"
	ln -s /dev/dri/card1 "$R/proc/4242/fd/5"; ln -s /dev/input/event3 "$R/proc/4242/fd/6"
	[ "$3" = 1 ] && echo active > "$D/state"
	cat > "$D/bin/systemctl" <<EOF
#!/bin/sh
echo "\$*" >> "$D/systemctl-calls.log"
case "\$1" in
start) [ "\$2" = plasma-mobile.service ] && echo active > "$D/state" ;;
stop) [ "\$2" = plasma-mobile.service ] && rm -f "$D/state" ;;
is-enabled) case "\$2" in plasma-mobile.service) echo disabled ;; usb-moded.service) echo masked ;; *) echo enabled ;; esac ;;
is-active)
	case "\$2" in plasma-mobile.service) if [ -e "$D/state" ]; then echo active; else echo inactive; fi ;; getty@tty1.service) echo inactive ;; *) echo active ;; esac ;;
show)
	case "\$3" in
	ActiveState) if [ -e "$D/state" ]; then echo active; else echo inactive; fi ;;
	SubState) echo running ;;
	MainPID) echo 4242 ;;
	NRestarts)
		if [ "$4" = 1 ]; then n=\$(cat "$D/nr" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$D/nr"; echo \$n; else echo 0; fi ;;
	esac ;;
status) echo "● plasma-mobile.service - Open-source user interface for phones"; echo "     Active: active (running)" ;;
esac
EOF
	printf '#!/bin/sh\necho "-- Boot journal"; echo "kwin_wayland: Using renderer llvmpipe"; echo "kwin_wayland: libinput: found touch device"\n' > "$D/bin/journalctl"
	printf '#!/bin/sh\necho "SESSION UID USER SEAT TTY"; echo "c2 10000 user seat0 tty1"\n' > "$D/bin/loginctl"
	printf '#!/bin/sh\necho "4242 root 0:05 /usr/bin/kwin_wayland --lockscreen"\necho "4300 user 0:02 plasmashell --no-respawn"\n' > "$D/bin/ps"
	printf '#!/bin/sh\nif [ "$1" = -o ]; then echo 4242; else echo 4242; fi\n' > "$D/bin/pgrep"
	printf '#!/bin/sh\nshift 2 2>/dev/null; echo "SUDO $*" >> "%s/sudo-calls.log"; echo "Output: DSI-1 enabled scale 2.5 rotation none"\n' "$D" > "$D/bin/sudo"
	printf '#!/bin/sh\necho "[    1.0] msm_dpu ae01000.display-controller: bound"\necho "[    2.0] fts: touch ready"\n' > "$D/bin/dmesg"
	printf '#!/bin/sh\necho "kscreen-doctor stub"\n' > "$D/bin/kscreen-doctor"
	chmod +x "$D"/bin/*
}
runit() { # $1 shell, $2 dir, $3 out, env...
	local sh="$1" D="$2" out="$3"; shift 3
	env ROOT="$D/root" SYSTEMCTL="$D/bin/systemctl" JOURNALCTL="$D/bin/journalctl" LOGINCTL="$D/bin/loginctl" PS="$D/bin/ps" \
		PGREP="$D/bin/pgrep" SUDO="$D/bin/sudo" DMESG="$D/bin/dmesg" PATH="$D/bin:$PATH" POLL=1 DUR=3 "$@" \
		"$sh" "$HERE/phone-plasma-start.sh" > "$out" 2>&1
}

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }

	echo "== $sh, scenario normal"
	N="$W/normal-$sh"; mktree "$N" 1 0 0
	runit "$sh" "$N" "$N/out" || bad "$sh exits non-zero"
	expect "$N/out" "preflight uptime" "uptime: 123\\.45 s"
	expect "$N/out" "default_user absent noted" "generator falls back to uid/gid 10000"
	expect "$N/out" "ui user shown" "user:x:10000:10000"
	expect "$N/out" "backlight before" "backlight before: 2047/2047"
	expect "$N/out" "monitoring line" "t=1s state=active/running pid=4242 restarts=0 kwin=1"
	expect "$N/out" "journal shown" "Using renderer llvmpipe"
	expect "$N/out" "process list" "plasmashell --no-respawn"
	expect "$N/out" "kwin env selected" "QT_QPA_PLATFORM=wayland"
	reject "$N/out" "env not leaking HOME" "^HOME="
	expect "$N/out" "drm fd counted" "1 /dev/dri/card1"
	expect "$N/out" "sessions" "c2 10000 user seat0 tty1"
	expect "$N/out" "kscreen-doctor ran as the ui user" "DSI-1 enabled scale 2.5"
	grep -q "SUDO.*user.*kscreen-doctor\|user env" "$N/sudo-calls.log" 2>/dev/null && ok "sudo called with the ui user name" || bad "sudo call not as ui user: $(cat "$N/sudo-calls.log" 2>/dev/null)"
	expect "$N/out" "dmesg filtered" "msm_dpu ae01000"
	expect "$N/out" "smmu fault counter" "number of arm-smmu faults since boot: 0"
	expect "$N/out" "result line" "RESULT: window of 3s completed"
	grep -q "^start plasma-mobile.service" "$N/systemctl-calls.log" && ok "unit started" || bad "unit not started"
	grep -q "^stop plasma-mobile.service" "$N/systemctl-calls.log" && ok "unit stopped at the end" || bad "unit not stopped"
	grep -q "^start getty@tty1.service" "$N/systemctl-calls.log" && ok "getty restored" || bad "getty not restored"
	[ "$(grep -c '^stop plasma-mobile.service' "$N/systemctl-calls.log")" = 1 ] && ok "stopped exactly once (EXIT trap does not repeat it)" || bad "stop called more than once"
	reject "$N/systemctl-calls.log" "never enabled, rebooted or masked anything" "^(enable|disable|reboot|poweroff|mask|unmask) "
	expect "$N/out" "ends with done" "^done$"

	echo "== $sh, scenario keep"
	K="$W/keep-$sh"; mktree "$K" 1 0 0
	runit "$sh" "$K" "$K/out" KEEP=1 || bad "$sh exits non-zero (keep)"
	expect "$K/out" "keep message" "KEEP=1: the session is left running"
	reject "$K/systemctl-calls.log" "not stopped" "^stop plasma-mobile.service"

	echo "== $sh, scenario crash loop"
	C="$W/crash-$sh"; mktree "$C" 1 0 1
	runit "$sh" "$C" "$C/out" DUR=30 || bad "$sh exits non-zero (crash)"
	expect "$C/out" "abort line" "ABORT: crash loop: 3 restarts"
	expect "$C/out" "aborted result" "RESULT: aborted early"
	expect "$C/out" "evidence still collected" "Using renderer llvmpipe"
	grep -q "^stop plasma-mobile.service" "$C/systemctl-calls.log" && ok "unit stopped after the crash loop" || bad "unit not stopped after the crash loop"

	echo "== $sh, scenario missing unit"
	M="$W/missing-$sh"; mktree "$M" 0 0 0
	runit "$sh" "$M" "$M/out"; rc=$?
	[ "$rc" = 1 ] && ok "exit 1" || bad "exit code $rc, wanted 1"
	expect "$M/out" "abort message" "is not installed: abort"
	reject "$M/systemctl-calls.log" "nothing started" "^start plasma-mobile.service"

	echo "== $sh, scenario already running"
	A="$W/running-$sh"; mktree "$A" 1 1 0
	runit "$sh" "$A" "$A/out" || bad "$sh exits non-zero (running)"
	expect "$A/out" "already running noted" "already running: not starting a second time"
	reject "$A/systemctl-calls.log" "not started again" "^start plasma-mobile.service"
	reject "$A/systemctl-calls.log" "not stopped (we did not start it)" "^stop plasma-mobile.service"

	echo "== $sh, scenario SIGTERM during the window"
	T="$W/term-$sh"; mktree "$T" 1 0 0
	env ROOT="$T/root" SYSTEMCTL="$T/bin/systemctl" JOURNALCTL="$T/bin/journalctl" LOGINCTL="$T/bin/loginctl" PS="$T/bin/ps" \
		PGREP="$T/bin/pgrep" SUDO="$T/bin/sudo" DMESG="$T/bin/dmesg" PATH="$T/bin:$PATH" POLL=1 DUR=60 \
		"$sh" "$HERE/phone-plasma-start.sh" > "$T/out" 2>&1 &
	BG=$!   # env exec()s the shell, so $BG is the script's own pid
	sleep 3
	kill -TERM "$BG" 2>/dev/null
	wait "$BG" 2>/dev/null
	sleep 1
	grep -q "^stop plasma-mobile.service" "$T/systemctl-calls.log" && ok "trap stopped the unit on SIGTERM" || bad "unit left running after SIGTERM"
	grep -q "^start getty@tty1.service" "$T/systemctl-calls.log" && ok "trap restored getty on SIGTERM" || bad "getty not restored after SIGTERM"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
