#!/bin/sh
# Phone-side: make the GPU fix and the Plasma Mobile start permanent (docs/11 section 9.12). POSIX sh, run as root
# (collect-phone-state.sh --boot-setup=MODE does that and pushes the firmware). NO apk anywhere: only plain files, systemd unit files and
# symlinks, so nothing here can fire the mkinitfs trigger of docs/06 rule 3; the script prints the sha256 of /boot/initramfs-extra before and
# after and says so.
#
# Usage: phone-boot-setup.sh check | gpu-fw | undo-gpu-fw | trust-gpu-fw | undo-trust-gpu-fw | touch-poll[=MS] | undo-touch-poll | wifi-sleep-hook | undo-wifi-sleep-hook | plasma | undo-plasma
#   check         read-only status of everything below (writes nothing)
#   gpu-fw        install the phone's own Adreno 740 firmware (SQE, GMU and the Samsung-signed zap shader, staged in $SRC, hashes pinned) into
#                 the default firmware path /lib/firmware/postmarketos, so the GPU comes up by itself at boot (msm bind / first open) instead of
#                 after a hand-run power-up. Plus a boot-loop breaker: dm1q-gpu-fw-guard.service (sysinit, before udev) leaves a marker,
#                 dm1q-gpu-fw-ok.service removes it 90 s after multi-user.target, and the guard's ExecStop removes it at a CLEAN shutdown (a
#                 normal reboot at any time); a marker still there at the next boot means the boot with the GPU firmware ended without either
#                 (reset, hang, power key held), and the guard then moves the firmware to /var/lib/dm1q/gpu-fw-disabled so that boot comes up
#                 without the GPU (run gpu-fw again to put it back). Until 2026-10-22 only the 90 s rule existed, so a plain reboot soon after
#                 a boot silently disabled the GPU for every later boot (docs/11 9.13).
#   undo-gpu-fw   remove all of that (firmware files only when they still match the manifest)
#   trust-gpu-fw  the installed firmware is KNOWN GOOD (it ran, 2026-10-24): the guard then never moves it and never leaves a marker, however a
#                 boot ends (a hard reset, a reboot right after a boot, a flash and boot from TWRP all tripped it before). Needs the pinned files in place.
#                 Survives a later gpu-fw. A real firmware boot loop would then have to be broken by hand (undo-trust-gpu-fw re-arms the guard).
#   undo-trust-gpu-fw  re-arm the guard
#   touch-poll[=MS]  keep the touch chip alive (docs/08 2.21 to 2.27: it sometimes stops asserting its interrupt; one read of its event queue
#                 restarts it): at every boot dm1q-touch-poll.service sets /sys/kernel/debug/spi0.0/poll_ms (default 150) once the knob exists
#                 (kernel package r11), and the value is also applied now when the knob is there. The driver then reads the queue after that many ms
#                 of silence on the interrupt line. Costs one 18-byte SPI read per poll while the screen is idle.
#   undo-touch-poll  remove the unit and script, set poll_ms back to 0
#   wifi-sleep-hook  a systemd-sleep hook (/etc/systemd/system-sleep/dm1q-ath11k): unload ath11k_pci before every suspend and load it again
#                 after. Without it the Wi-Fi card (WCN6855) fails to come back from a suspend (mhi: Device failed to enter MHI Ready, resume error
#                 -110 after 26 to 49 s, wlan0 gone until a reboot; 2026-10-24 captures). With the module unloaded the suspend has no Wi-Fi power
#                 management to wait for. NetworkManager sees the interface go and come back.
#   undo-wifi-sleep-hook  remove the hook
#   plasma        enable plasma-mobile.service at boot (alias display-manager.service, default target graphical.target) with a drop-in that
#                 stops a crash loop after 4 starts in 3 minutes (its OnFailure= then gives tty1 back to getty), waits up to 15 s for the msm
#                 render node and then REFUSES TO START PLASMA unless the kernel log shows the GPU initialised (dm1q-plasma-gate: without a GPU
#                 kwin renders on llvmpipe on every core, hot and laggy, docs/11 9.13; escape hatch: touch /var/lib/dm1q/plasma-allow-cpu).
#                 The command itself REFUSES unless the GPU firmware is installed AND the GPU initialised by itself in the current boot (without a GPU
#                 kwin falls back to llvmpipe, which dies with SIGILL, docs/10 9.3) AND the PAM problem of docs/11 9.10 is solved. It does not
#                 start the UI now.
#   undo-plasma   disable it again, remove the drop-in and the helper, restore the previous default target (a running UI is not stopped)
# Env (the PC-side test uses them): ROOT SYSFS SYSTEMCTL DMESG SRC SHA BOOTDIR ID_U FW_SQE_SHA FW_GMU_SHA FW_ZAP_SHA DEBUGFS
#   FORCE_GPU_UNPROVEN=1 (plasma: skip the "GPU initialised in this boot" requirement)
ROOT="${ROOT:-}"
SYSFS="${SYSFS:-/sys}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
DMESG="${DMESG:-dmesg}"
SRC="${SRC:-/root/dm1q-gpu-fw}"
SHA="${SHA:-sha256sum}"
BOOTDIR="${BOOTDIR:-$ROOT/boot}"
FW_SQE_SHA="${FW_SQE_SHA:-96fee336424b139100fc60b5b45a907360e4b3936d7e1d00406b9bd80ca48473}"
FW_GMU_SHA="${FW_GMU_SHA:-1a2a419c39046d3141fc5fed5aa7f971de2db40cc7a1d89693c3e26fad64dd98}"
FW_ZAP_SHA="${FW_ZAP_SHA:-60cf7ab4f3d96e0992a42560ac288c053328bda5e41b4fe5e678be94ecd7ae35}"
GENERIC_ZAP_SHA=386bbdc25ae94a9398e33e7580eecfdcef6c472682a1e3123e1374bcffe7cde3
FORCE_GPU_UNPROVEN="${FORCE_GPU_UNPROVEN:-0}"

FWREL=/lib/firmware/postmarketos
RELS="qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/sm8550/a740_zap.mbn"
FWDIR="$ROOT$FWREL"
STATE="$ROOT/var/lib/dm1q"
SBIN="$ROOT/usr/local/sbin"
UNITS="$ROOT/etc/systemd/system"
MANIFEST="$STATE/gpu-fw.manifest"
MARKER="$STATE/gpu-fw-boot-pending"
DISABLED="$STATE/gpu-fw-disabled"
PREVDEF="$STATE/plasma-prev-default"
DROPDIR="$UNITS/plasma-mobile.service.d"
DROPIN="$DROPDIR/10-dm1q-boot.conf"
GUARD="$SBIN/dm1q-gpu-fw-guard"
OKSCRIPT="$SBIN/dm1q-gpu-fw-ok"
CLEAN="$SBIN/dm1q-gpu-fw-clean"
WAITNODE="$SBIN/dm1q-plasma-gate"
OLDWAIT="$SBIN/dm1q-wait-render-node"
GUARD_UNIT="$UNITS/dm1q-gpu-fw-guard.service"
OK_UNIT="$UNITS/dm1q-gpu-fw-ok.service"
PARAM="$SYSFS/module/firmware_class/parameters/path"
DEBUGFS="${DEBUGFS:-$SYSFS/kernel/debug}"
TRUSTED="$STATE/gpu-fw-trusted"
TPOLL="$SBIN/dm1q-touch-poll"
TPOLL_UNIT="$UNITS/dm1q-touch-poll.service"
WIFIHOOK="$ROOT/etc/systemd/system-sleep/dm1q-ath11k"

MODE_ARG="${1:-}"
MODE="${MODE_ARG%%=*}"
ARG=""
case "$MODE_ARG" in *=*) ARG="${MODE_ARG#*=}" ;; esac
case "$MODE" in check|gpu-fw|undo-gpu-fw|trust-gpu-fw|undo-trust-gpu-fw|touch-poll|undo-touch-poll|wifi-sleep-hook|undo-wifi-sleep-hook|plasma|undo-plasma) ;; *) sed -n '2,48p' "$0"; exit 2 ;; esac

say() { echo; echo "== $*"; }
refuse() { echo "REFUSING: $*"; exit 3; }
need_root() { [ "${ID_U:-$(id -u)}" = 0 ] || { echo "run as root"; exit 2; }; }
sc() { "$SYSTEMCTL" "$@" 2>&1 | sed 's/^/  /'; }
hash_of() { "$SHA" "$1" 2>/dev/null | cut -d' ' -f1; }
is_ours() { [ -f "$1" ] && grep -q '^# dm1q-boot-setup' "$1"; }
pin_of() {
	case "$1" in
	qcom/a740_sqe.fw) echo "$FW_SQE_SHA" ;;
	qcom/gmu_gen70200.bin) echo "$FW_GMU_SHA" ;;
	qcom/sm8550/a740_zap.mbn) echo "$FW_ZAP_SHA" ;;
	esac
}
put() { # $1 path, $2 mode; content on stdin; written next to the target and renamed, so a reader never sees half a file
	mkdir -p "$(dirname "$1")" || return 1
	cat > "$1.new" && chmod "$2" "$1.new" && mv "$1.new" "$1"
}
extra_sha() { if [ -f "$BOOTDIR/initramfs-extra" ]; then hash_of "$BOOTDIR/initramfs-extra"; else echo none; fi; }
pam_ok() { # the UI user's systemd manager needs either the module or our override (docs/11 9.10)
	[ -e "$ROOT/usr/lib/security/pam_selinux.so" ] || [ -e "$ROOT/lib/security/pam_selinux.so" ] && return 0
	grep -q '^# dm1q-pam-fix' "$ROOT/etc/pam.d/systemd-user" 2>/dev/null && return 0
	return 1
}
gpu_proven() { # the GPU initialised by itself in this boot: the GMU firmware line, and no hw init failure after it
	log=$("$DMESG" 2>/dev/null)
	echo "$log" | grep -q 'Loaded GMU firmware' || return 1
	echo "$log" | grep -qE 'gpu hw init failed|Unable to authorize|error -22 initializing firmware' && return 1
	return 0
}

emit_guard() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.12). Boot-loop breaker for the Adreno firmware.
# Runs at sysinit, before udev loads msm. A marker left by the previous boot (never cleared by dm1q-gpu-fw-ok.service) means that boot did not
# finish with the GPU firmware in place: move the firmware away so this boot comes up without the GPU. Never fails the boot.
R="${DM1Q_ROOT:-}"
S="$R/var/lib/dm1q"
M="$S/gpu-fw-boot-pending"
MAN="$S/gpu-fw.manifest"
OFF="$S/gpu-fw-disabled"
T="$S/gpu-fw-trusted"
KMSG="${DM1Q_KMSG:-/dev/kmsg}"
[ -f "$MAN" ] || exit 0
# the firmware was proven good by hand (phone-boot-setup.sh trust-gpu-fw): never move it, never leave a marker
if [ -e "$T" ]; then
	rm -f "$M"
	exit 0
fi
if [ -e "$M" ]; then
	mkdir -p "$OFF"
	while read -r _ path; do
		[ -n "$path" ] && [ -f "$R$path" ] && mv "$R$path" "$OFF/$(basename "$path")"
	done < "$MAN"
	mv "$MAN" "$OFF/gpu-fw.manifest.disabled"
	rm -f "$M"
	sync
	echo "dm1q-gpu-fw-guard: the previous boot did not finish with the GPU firmware; it was moved to $OFF (run phone-boot-setup.sh gpu-fw to put it back)" > "$KMSG" 2>/dev/null
	exit 0
fi
if ! : > "$M" 2>/dev/null; then
	echo "dm1q-gpu-fw-guard: cannot write $M: no boot-loop protection this boot" > "$KMSG" 2>/dev/null
fi
sync
exit 0
EOF
}

emit_ok() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.12). The boot with the GPU firmware survived: clear the marker.
sleep "${DM1Q_OK_DELAY:-90}"
rm -f "${DM1Q_ROOT:-}/var/lib/dm1q/gpu-fw-boot-pending"
sync
exit 0
EOF
}

emit_clean() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.13). ExecStop of dm1q-gpu-fw-guard.service: a clean shutdown (a normal
# reboot or poweroff, at any time after boot) clears the boot-pending marker, so only a boot that ends without a clean shutdown trips the guard.
rm -f "${DM1Q_ROOT:-}/var/lib/dm1q/gpu-fw-boot-pending"
sync
exit 0
EOF
}

emit_wait() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.13). ExecStartPre of plasma-mobile.service: wait up to 15 s for the
# msm render node, then require that the GPU initialised ("Loaded GMU firmware" in the kernel log, no hw-init failure line). Without a GPU kwin
# renders on llvmpipe on every core (hot, laggy phone, docs/08 2.16), so the start is refused (exit 1: the unit fails and its OnFailure= gives tty1
# to getty). Escape hatch: touch /var/lib/dm1q/plasma-allow-cpu.
R="${DM1Q_ROOT:-}"
DMESG="${DM1Q_DMESG:-dmesg}"
KMSG="${DM1Q_KMSG:-/dev/kmsg}"
i=0
while [ "$i" -lt "${DM1Q_WAIT_TRIES:-15}" ] && [ ! -e "${DM1Q_RENDER_NODE:-/dev/dri/renderD128}" ]; do
	sleep 1
	i=$((i + 1))
done
[ -e "$R/var/lib/dm1q/plasma-allow-cpu" ] && exit 0
j=0
while :; do
	log=$("$DMESG" 2>/dev/null)
	if echo "$log" | grep -q 'Loaded GMU firmware' && ! echo "$log" | grep -qE 'gpu hw init failed|Unable to authorize|error -22 initializing firmware'; then
		exit 0
	fi
	[ "$j" -lt "${DM1Q_GPU_TRIES:-10}" ] || break
	sleep 1
	j=$((j + 1))
done
echo "dm1q-plasma-gate: the GPU did not initialise in this boot; not starting Plasma (software rendering burns the CPU). Fix: phone-boot-setup.sh gpu-fw and a normal reboot, or touch /var/lib/dm1q/plasma-allow-cpu" > "$KMSG" 2>/dev/null
echo "dm1q-plasma-gate: the GPU did not initialise in this boot; not starting Plasma" >&2
exit 1
EOF
}

emit_guard_unit() {
	cat <<'EOF'
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.12)
[Unit]
Description=dm1q: break a boot loop caused by the Adreno firmware
DefaultDependencies=no
After=systemd-remount-fs.service
Before=systemd-udev-trigger.service systemd-modules-load.service sysinit.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/dm1q-gpu-fw-guard
ExecStop=/usr/local/sbin/dm1q-gpu-fw-clean

[Install]
WantedBy=sysinit.target
EOF
}

emit_ok_unit() {
	cat <<'EOF'
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.12)
[Unit]
Description=dm1q: the boot with the Adreno firmware survived
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/dm1q-gpu-fw-ok

[Install]
WantedBy=multi-user.target
EOF
}

emit_dropin() {
	cat <<'EOF'
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/11 section 9.12). Remove with: phone-boot-setup.sh undo-plasma
[Unit]
# a crash loop stops after 4 starts in 3 minutes; the unit's OnFailure= then starts getty@tty1 again
StartLimitIntervalSec=180
StartLimitBurst=4

[Service]
# the + prefix runs the gate as root: the unit runs as the UI user, who may not read the kernel log (dmesg_restrict)
ExecStartPre=+/usr/local/sbin/dm1q-plasma-gate
EOF
}

emit_wifihook() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (wifi-sleep-hook). systemd-sleep hook: $1 = pre or post, $2 = the kind of sleep.
# The WCN6855 Wi-Fi card does not survive a suspend with its driver loaded (mhi: Device failed to enter MHI Ready, -110, wlan0 gone), so the
# driver is unloaded before and loaded after. Never fails the suspend.
MODPROBE="${DM1Q_MODPROBE:-modprobe}"
KMSG="${DM1Q_KMSG:-/dev/kmsg}"
case "$1" in
pre)
	"$MODPROBE" -r ath11k_pci >/dev/null 2>&1
	echo "dm1q-ath11k: unloaded ath11k_pci before $2" > "$KMSG" 2>/dev/null
	;;
post)
	"$MODPROBE" ath11k_pci >/dev/null 2>&1
	echo "dm1q-ath11k: loaded ath11k_pci after $2" > "$KMSG" 2>/dev/null
	;;
esac
exit 0
EOF
}

emit_touchpoll() {
	cat <<'EOF'
#!/bin/sh
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/08 section 2.27). Sets the touch driver's poll_ms once its debugfs knob exists
# (kernel package r11; the driver probes a few seconds after boot). Never fails the boot.
D="${DM1Q_DEBUGFS:-/sys/kernel/debug}/spi0.0"
MS="${DM1Q_POLL_MS:-150}"
KMSG="${DM1Q_KMSG:-/dev/kmsg}"
i=0
while [ ! -w "$D/poll_ms" ] && [ "$i" -lt "${DM1Q_POLL_WAIT:-120}" ]; do
	sleep 1
	i=$((i + 1))
done
if [ -w "$D/poll_ms" ]; then
	echo "$MS" > "$D/poll_ms" && echo "dm1q-touch-poll: poll_ms=$MS" > "$KMSG" 2>/dev/null
else
	echo "dm1q-touch-poll: $D/poll_ms did not appear (kernel without patch 0005?): no poll" > "$KMSG" 2>/dev/null
fi
exit 0
EOF
}

emit_touchpoll_unit() { # $1 = ms
	cat <<EOF
# dm1q-boot-setup: generated by scripts/phone-boot-setup.sh (docs/08 section 2.27)
[Unit]
Description=dm1q: keep the touch chip alive (poll its event queue after $1 ms of silence)
After=local-fs.target sys-kernel-debug.mount

[Service]
Type=simple
RemainAfterExit=yes
Environment=DM1Q_POLL_MS=$1
ExecStart=/usr/local/sbin/dm1q-touch-poll

[Install]
WantedBy=multi-user.target
EOF
}

status() {
	say "firmware path and files"
	echo "firmware_class.path: '$(cat "$PARAM" 2>/dev/null)' (the install target is $FWREL)"
	fwstate=absent
	allok=1
	for rel in $RELS; do
		f="$FWDIR/$rel"
		if [ -f "$f" ]; then
			h=$(hash_of "$f")
			if [ "$h" = "$(pin_of "$rel")" ]; then echo "  present  $rel sha256 $(echo "$h" | cut -c1-12)... matches the pin"; else echo "  present  $rel sha256 $h does NOT match the pin"; allok=0; fi
		else
			echo "  absent   $rel"; allok=0
		fi
	done
	[ "$allok" = 1 ] && fwstate=installed
	if [ -f "$MANIFEST" ]; then echo "manifest: present"; else echo "manifest: absent"; fi
	if [ -d "$DISABLED" ] && [ -n "$(ls "$DISABLED" 2>/dev/null)" ]; then echo "guard moved files away: $(ls "$DISABLED" | tr '\n' ' ')"; fwstate=disabled-by-guard; fi
	if [ -e "$MARKER" ]; then echo "boot-pending marker: present (cleared 90 s after multi-user.target of a good boot, or at a clean shutdown)"; else echo "boot-pending marker: absent"; fi
	if [ -e "$TRUSTED" ]; then guardstate=trusted; echo "guard: the firmware is TRUSTED, the guard never moves it"; elif [ -f "$MANIFEST" ]; then guardstate=armed; echo "guard: armed"; else guardstate=none; echo "guard: no manifest"; fi
	say "boot-loop breaker units"
	for u in dm1q-gpu-fw-guard.service dm1q-gpu-fw-ok.service; do
		if [ -f "$UNITS/$u" ]; then echo "  $u: file present, $("$SYSTEMCTL" is-enabled "$u" 2>&1)"; else echo "  $u: file absent"; fi
	done
	say "GPU in this boot"
	if gpu_proven; then echo "gpu_in_this_boot=initialised (Loaded GMU firmware, no failure line)"; gpustate=initialised; else echo "gpu_in_this_boot=not-initialised"; gpustate=not-initialised; fi
	"$DMESG" 2>/dev/null | grep -E 'Loaded GMU firmware|gpu hw init failed|Unable to authorize|no GPU device was found|a740' | tail -n 8 | cut -c1-200 | sed 's/^/  /'
	say "Plasma Mobile at boot"
	if [ -f "$ROOT/usr/lib/systemd/system/plasma-mobile.service" ] || [ -f "$UNITS/plasma-mobile.service" ]; then echo "plasma-mobile.service: unit exists, $("$SYSTEMCTL" is-enabled plasma-mobile.service 2>&1)"; else echo "plasma-mobile.service: unit does not exist"; fi
	if is_ours "$DROPIN"; then echo "drop-in: present (ours)"; else echo "drop-in: absent"; fi
	echo "default target: $("$SYSTEMCTL" get-default 2>&1)"
	if pam_ok; then echo "PAM: ok (module present or our override in place)"; else echo "PAM: NOT ok (user@10000 would fail, docs/11 9.10)"; fi
	say "Wi-Fi sleep hook"
	if is_ours "$WIFIHOOK"; then echo "wifi_sleep_hook=present"; else echo "wifi_sleep_hook=absent"; fi
	say "touch poll"
	if is_ours "$TPOLL_UNIT"; then echo "dm1q-touch-poll.service: file present (ours), $("$SYSTEMCTL" is-enabled dm1q-touch-poll.service 2>&1)"; else echo "dm1q-touch-poll.service: file absent"; fi
	if [ -r "$DEBUGFS/spi0.0/poll_ms" ]; then echo "touch driver poll_ms now: $(cat "$DEBUGFS/spi0.0/poll_ms" 2>/dev/null)"; else echo "touch driver poll_ms: knob absent (kernel without patch 0005, or debugfs not readable)"; fi
	say "other"
	echo "initramfs-extra sha256: $(extra_sha)"
	echo "apk db names the firmware files: $(for rel in $RELS; do if grep -qx "R:$(basename "$rel")" "$ROOT/lib/apk/db/installed" 2>/dev/null; then echo "$(basename "$rel"):yes"; else echo "$(basename "$rel"):no"; fi; done | tr '\n' ' ')"
	echo
	echo "gpu_fw=$fwstate"
	echo "gpu_fw_guard=$guardstate"
	echo "gpu_state=$gpustate"
	if "$SYSTEMCTL" is-enabled plasma-mobile.service >/dev/null 2>&1; then echo "plasma_boot=enabled"; else echo "plasma_boot=disabled"; fi
}

gpu_fw_apply() {
	need_root
	say "preflight"
	cur=$(cat "$PARAM" 2>/dev/null)
	[ "$cur" = "$FWREL" ] || refuse "firmware_class.path is '$cur', not $FWREL: files installed there would not be found by the kernel"
	echo "firmware_class.path: $cur"
	[ "$FW_ZAP_SHA" != "$GENERIC_ZAP_SHA" ] || refuse "the generic linux-firmware zap shader is refused by the secure world (-22, docs/11 9.7); only the phone's own signed one works"
	bad=0
	for rel in $RELS; do
		f="$SRC/$rel"
		pin=$(pin_of "$rel")
		if [ ! -f "$f" ]; then echo "$f: missing"; bad=1; continue; fi
		got=$(hash_of "$f")
		if [ "$got" != "$pin" ]; then echo "$rel: sha256 $got is not the pinned $pin"; bad=1; continue; fi
		echo "ok  $rel $(wc -c < "$f") bytes sha256 $got"
	done
	[ "$bad" = 0 ] || refuse "the staged set in $SRC is not the pinned one"
	for rel in $RELS; do
		dest="$FWDIR/$rel"
		[ -e "$dest" ] || continue
		dh=$(hash_of "$dest")
		if [ "$dh" != "$(pin_of "$rel")" ] && ! grep -qF " $FWREL/$rel" "$MANIFEST" 2>/dev/null; then
			refuse "$dest exists with another content and is not in our manifest: not overwriting it"
		fi
	done
	before=$(extra_sha)
	echo "initramfs-extra sha256 before: $before"

	say "install the firmware under $FWREL"
	mkdir -p "$STATE" || refuse "cannot create $STATE"
	: > "$MANIFEST.new" || refuse "cannot write $MANIFEST.new"
	for rel in $RELS; do
		dest="$FWDIR/$rel"
		mkdir -p "$(dirname "$dest")" || refuse "cannot create $(dirname "$dest")"
		cp "$SRC/$rel" "$dest.new" && chmod 644 "$dest.new" && mv "$dest.new" "$dest" || refuse "could not write $dest"
		[ "$(hash_of "$dest")" = "$(pin_of "$rel")" ] || refuse "$dest does not read back as the pinned file"
		echo "$(pin_of "$rel") $FWREL/$rel" >> "$MANIFEST.new"
		echo "installed $dest"
	done

	say "boot-loop breaker (guard + ok units)"
	rm -rf "$DISABLED" "$MARKER"
	emit_guard | put "$GUARD" 755 || refuse "cannot write $GUARD"
	emit_ok | put "$OKSCRIPT" 755 || refuse "cannot write $OKSCRIPT"
	emit_clean | put "$CLEAN" 755 || refuse "cannot write $CLEAN"
	emit_guard_unit | put "$GUARD_UNIT" 644 || refuse "cannot write $GUARD_UNIT"
	emit_ok_unit | put "$OK_UNIT" 644 || refuse "cannot write $OK_UNIT"
	mv "$MANIFEST.new" "$MANIFEST" || refuse "cannot write the manifest"
	echo "wrote $GUARD, $OKSCRIPT, $CLEAN and the two units"
	sc daemon-reload
	sc enable dm1q-gpu-fw-guard.service dm1q-gpu-fw-ok.service
	sync

	say "done"
	after=$(extra_sha)
	echo "initramfs-extra sha256 after:  $after"
	if [ "$before" = "$after" ]; then echo "initramfs-extra unchanged (no mkinitfs trigger fired)"; else echo "WARNING: initramfs-extra CHANGED: do not reboot into the system, repair from TWRP (scripts/fix-phone-initramfs-extra.sh)"; fi
	echo "RESULT: GPU firmware installed under $FWREL; the next boot loads the GPU by itself (msm bind or the first open)"
	echo "next: reboot, then collect with --gpu and --boot-setup=check; the boot-loop breaker undoes this by itself if that boot resets or hangs the phone"
}

gpu_fw_undo() {
	need_root
	say "undo gpu-fw"
	sc disable dm1q-gpu-fw-guard.service dm1q-gpu-fw-ok.service
	for f in "$GUARD_UNIT" "$OK_UNIT" "$GUARD" "$OKSCRIPT" "$CLEAN"; do
		if is_ours "$f"; then rm -f "$f" && echo "removed $f"; elif [ -e "$f" ]; then echo "kept $f (not ours)"; fi
	done
	for src in "$MANIFEST" "$DISABLED/gpu-fw.manifest.disabled"; do
		[ -f "$src" ] || continue
		while read -r sum path; do
			[ -n "$path" ] || continue
			f="$ROOT$path"
			[ -f "$f" ] || f="$DISABLED/$(basename "$path")"
			[ -f "$f" ] || continue
			if [ "$(hash_of "$f")" = "$sum" ]; then rm -f "$f" && echo "removed $f"; else echo "kept $f (content differs from the manifest)"; fi
		done < "$src"
	done
	rm -f "$MANIFEST" "$MARKER" "$TRUSTED" "$DISABLED/gpu-fw.manifest.disabled"
	rmdir "$DISABLED" 2>/dev/null
	rmdir "$FWDIR/qcom/sm8550" "$FWDIR/qcom" 2>/dev/null
	rmdir "$STATE" 2>/dev/null
	sc daemon-reload
	sync
	echo
	echo "RESULT: the GPU firmware and the boot-loop breaker are removed; the GPU is down after the next boot again (use --gpu-powerup=full)"
}

plasma_apply() {
	need_root
	say "preflight"
	if [ ! -f "$ROOT/usr/lib/systemd/system/plasma-mobile.service" ] && [ ! -f "$UNITS/plasma-mobile.service" ]; then refuse "plasma-mobile.service does not exist"; fi
	[ -f "$MANIFEST" ] || refuse "the GPU firmware is not installed (run gpu-fw, reboot, check the GPU first): without a GPU kwin dies with SIGILL in a restart loop"
	while read -r sum path; do
		[ -n "$path" ] || continue
		[ -f "$ROOT$path" ] || refuse "$path from the manifest is missing"
	done < "$MANIFEST"
	echo "GPU firmware: installed (manifest and files present)"
	if gpu_proven; then
		echo "GPU in this boot: initialised by itself (Loaded GMU firmware, no failure line)"
	elif [ "$FORCE_GPU_UNPROVEN" = 1 ]; then
		echo "GPU in this boot: NOT initialised, continuing because FORCE_GPU_UNPROVEN=1"
	else
		refuse "the GPU did not initialise by itself in this boot (no 'Loaded GMU firmware' line, or a failure line): reboot after gpu-fw and read the GPU log first"
	fi
	pam_ok || refuse "the PAM breakage of docs/11 9.10 is not solved (no pam_selinux.so and no dm1q-pam-fix override): user@10000 would not start; run --pam-fix"
	echo "PAM: ok"

	say "enable plasma-mobile.service at boot"
	emit_wait | put "$WAITNODE" 755 || refuse "cannot write $WAITNODE"
	emit_dropin | put "$DROPIN" 644 || refuse "cannot write $DROPIN"
	echo "wrote $DROPIN and $WAITNODE (the gate: Plasma does not start without an initialised GPU)"
	if is_ours "$OLDWAIT"; then rm -f "$OLDWAIT"; fi
	def=$("$SYSTEMCTL" get-default 2>/dev/null)
	if [ "$def" != graphical.target ]; then
		mkdir -p "$STATE" && echo "$def" > "$PREVDEF"
		echo "default target was '$def': set to graphical.target (previous kept in $PREVDEF)"
		sc set-default graphical.target
	else
		echo "default target: graphical.target"
	fi
	sc daemon-reload
	sc enable plasma-mobile.service
	state=$("$SYSTEMCTL" is-enabled plasma-mobile.service 2>&1)
	echo "plasma-mobile.service: $state"
	sync
	echo
	if [ "$state" = enabled ] || [ "$state" = alias ]; then
		echo "RESULT: plasma-mobile.service starts at every boot (not started now); undo with --boot-setup=undo-plasma"
	else
		echo "RESULT: plasma-mobile.service is '$state', not enabled: read the lines above"
	fi
}

plasma_undo() {
	need_root
	say "undo plasma"
	sc disable plasma-mobile.service
	for f in "$DROPIN" "$WAITNODE" "$OLDWAIT"; do
		if is_ours "$f"; then rm -f "$f" && echo "removed $f"; elif [ -e "$f" ]; then echo "kept $f (not ours)"; fi
	done
	rmdir "$DROPDIR" 2>/dev/null
	if [ -f "$PREVDEF" ]; then
		prev=$(cat "$PREVDEF")
		if [ -n "$prev" ]; then echo "restoring the default target '$prev'"; sc set-default "$prev"; fi
		rm -f "$PREVDEF"
	fi
	rmdir "$STATE" 2>/dev/null
	sc daemon-reload
	echo
	echo "RESULT: plasma-mobile.service no longer starts at boot (a running UI was not stopped)"
}

gpu_fw_trust() {
	need_root
	say "trust the installed GPU firmware"
	[ -f "$MANIFEST" ] || refuse "the GPU firmware is not installed (no manifest): run gpu-fw first"
	for rel in $RELS; do
		[ "$(hash_of "$FWDIR/$rel")" = "$(pin_of "$rel")" ] || refuse "$FWDIR/$rel is missing or not the pinned file: run gpu-fw first"
		echo "ok  $rel is the pinned file"
	done
	# the guard on the phone may be the old one, without the trusted check: write the current one
	emit_guard | put "$GUARD" 755 || refuse "cannot write $GUARD"
	mkdir -p "$STATE" || refuse "cannot create $STATE"
	date > "$TRUSTED" || refuse "cannot write $TRUSTED"
	rm -f "$MARKER"
	sync
	echo
	echo "RESULT: GPU firmware trusted: dm1q-gpu-fw-guard no longer moves it or leaves a marker (undo-trust-gpu-fw re-arms it)"
}

gpu_fw_untrust() {
	need_root
	say "re-arm the guard"
	rm -f "$TRUSTED"
	echo
	echo "RESULT: the guard is armed again (an unclean boot moves the firmware away)"
}

wifi_hook_apply() {
	need_root
	say "install the Wi-Fi sleep hook"
	if [ -e "$WIFIHOOK" ] && ! is_ours "$WIFIHOOK"; then refuse "$WIFIHOOK exists and is not ours"; fi
	emit_wifihook | put "$WIFIHOOK" 755 || refuse "cannot write $WIFIHOOK"
	sync
	echo "wrote $WIFIHOOK"
	echo
	echo "RESULT: ath11k_pci is unloaded before every suspend and loaded after it (undo-wifi-sleep-hook removes the hook); it takes effect at the next suspend"
}

wifi_hook_undo() {
	need_root
	say "remove the Wi-Fi sleep hook"
	if is_ours "$WIFIHOOK"; then rm -f "$WIFIHOOK" && echo "removed $WIFIHOOK"; elif [ -e "$WIFIHOOK" ]; then echo "kept $WIFIHOOK (not ours)"; fi
	echo
	echo "RESULT: the Wi-Fi sleep hook is gone"
}

touch_poll_apply() {
	need_root
	ms="${ARG:-150}"
	case "$ms" in ''|*[!0-9]*) refuse "touch-poll=MS needs a number of milliseconds (got '$ms')" ;; esac
	{ [ "$ms" -ge 20 ] && [ "$ms" -le 60000 ]; } || refuse "touch-poll=MS must be between 20 and 60000 (got $ms)"
	say "install the touch poll at boot (poll_ms=$ms)"
	emit_touchpoll | put "$TPOLL" 755 || refuse "cannot write $TPOLL"
	emit_touchpoll_unit "$ms" | put "$TPOLL_UNIT" 644 || refuse "cannot write $TPOLL_UNIT"
	echo "wrote $TPOLL and $TPOLL_UNIT"
	sc daemon-reload
	sc enable dm1q-touch-poll.service
	if [ -w "$DEBUGFS/spi0.0/poll_ms" ]; then
		echo "$ms" > "$DEBUGFS/spi0.0/poll_ms" && echo "poll_ms=$ms applied now"
	else
		echo "the knob $DEBUGFS/spi0.0/poll_ms is not there now (kernel without patch 0005, or debugfs unreadable): it is applied at the next boot where it exists"
	fi
	sync
	echo
	echo "RESULT: the touch poll is set to $ms ms at every boot (undo-touch-poll removes it)"
}

touch_poll_undo() {
	need_root
	say "remove the touch poll"
	sc disable dm1q-touch-poll.service
	for f in "$TPOLL_UNIT" "$TPOLL"; do
		if is_ours "$f"; then rm -f "$f" && echo "removed $f"; elif [ -e "$f" ]; then echo "kept $f (not ours)"; fi
	done
	sc daemon-reload
	if [ -w "$DEBUGFS/spi0.0/poll_ms" ]; then echo 0 > "$DEBUGFS/spi0.0/poll_ms" && echo "poll_ms=0 applied now"; fi
	echo
	echo "RESULT: the touch poll no longer starts at boot"
}

case "$MODE" in
check) status ;;
gpu-fw) gpu_fw_apply ;;
undo-gpu-fw) gpu_fw_undo ;;
trust-gpu-fw) gpu_fw_trust ;;
undo-trust-gpu-fw) gpu_fw_untrust ;;
touch-poll) touch_poll_apply ;;
undo-touch-poll) touch_poll_undo ;;
wifi-sleep-hook) wifi_hook_apply ;;
undo-wifi-sleep-hook) wifi_hook_undo ;;
plasma) plasma_apply ;;
undo-plasma) plasma_undo ;;
esac
echo
echo "done"
