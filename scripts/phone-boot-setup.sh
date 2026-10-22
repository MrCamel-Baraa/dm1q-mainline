#!/bin/sh
# Phone-side: make the GPU fix and the Plasma Mobile start permanent (docs/11 section 9.12). POSIX sh, run as root
# (collect-phone-state.sh --boot-setup=MODE does that and pushes the firmware). NO apk anywhere: only plain files, systemd unit files and
# symlinks, so nothing here can fire the mkinitfs trigger of docs/06 rule 3; the script prints the sha256 of /boot/initramfs-extra before and
# after and says so.
#
# Usage: phone-boot-setup.sh check | gpu-fw | undo-gpu-fw | plasma | undo-plasma
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
#   plasma        enable plasma-mobile.service at boot (alias display-manager.service, default target graphical.target) with a drop-in that
#                 stops a crash loop after 4 starts in 3 minutes (its OnFailure= then gives tty1 back to getty), waits up to 15 s for the msm
#                 render node and then REFUSES TO START PLASMA unless the kernel log shows the GPU initialised (dm1q-plasma-gate: without a GPU
#                 kwin renders on llvmpipe on every core, hot and laggy, docs/11 9.13; escape hatch: touch /var/lib/dm1q/plasma-allow-cpu).
#                 The command itself REFUSES unless the GPU firmware is installed AND the GPU initialised by itself in the current boot (without a GPU
#                 kwin falls back to llvmpipe, which dies with SIGILL, docs/10 9.3) AND the PAM problem of docs/11 9.10 is solved. It does not
#                 start the UI now.
#   undo-plasma   disable it again, remove the drop-in and the helper, restore the previous default target (a running UI is not stopped)
# Env (the PC-side test uses them): ROOT SYSFS SYSTEMCTL DMESG SRC SHA BOOTDIR ID_U FW_SQE_SHA FW_GMU_SHA FW_ZAP_SHA
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

MODE="${1:-}"
case "$MODE" in check|gpu-fw|undo-gpu-fw|plasma|undo-plasma) ;; *) sed -n '2,25p' "$0"; exit 2 ;; esac

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
KMSG="${DM1Q_KMSG:-/dev/kmsg}"
[ -f "$MAN" ] || exit 0
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
	say "other"
	echo "initramfs-extra sha256: $(extra_sha)"
	echo "apk db names the firmware files: $(for rel in $RELS; do if grep -qx "R:$(basename "$rel")" "$ROOT/lib/apk/db/installed" 2>/dev/null; then echo "$(basename "$rel"):yes"; else echo "$(basename "$rel"):no"; fi; done | tr '\n' ' ')"
	echo
	echo "gpu_fw=$fwstate"
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
	rm -f "$MANIFEST" "$MARKER" "$DISABLED/gpu-fw.manifest.disabled"
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

case "$MODE" in
check) status ;;
gpu-fw) gpu_fw_apply ;;
undo-gpu-fw) gpu_fw_undo ;;
plasma) plasma_apply ;;
undo-plasma) plasma_undo ;;
esac
echo
echo "done"
