#!/bin/sh
# INSTALLS Plasma Mobile on the phone (docs/10 section 8). Runs on the phone as root (sudo sh phone-plasma-install.sh),
# POSIX sh / busybox ash. This one CHANGES the system:
#   - apk add postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile  (~821 operations, ~2.7 GB)
#   - systemctl mask usb-moded.service  (precaution, undo: systemctl unmask usb-moded.service): the UI package pulls in
#     postmarketos-usb-moded, which may take over the USB gadget that carries our ssh (docs/10 risk 1)
#   - systemctl disable plasma-mobile.service display-manager.service  ONLY IF the install left them enabled
#     (the UI must not autostart before it has been started by hand and found stable)
# It does NOT start the UI and does NOT reboot.
#
# !!! The install WILL regenerate /boot/initramfs-extra (docs/06 rule 3). DO NOT reboot the phone into the system
# afterwards: reboot into TWRP and run `bash scripts/fix-phone-initramfs-extra.sh --yes` from the PC first. !!!
#
# Safety design: apk runs DETACHED (nohup + setsid) and logs to /root/dm1q-plasma/install.log, so a dropped ssh
# session (USB hiccup, PC network switch) does not kill it half way. Run the script again to follow / finish:
# it detects a running or finished install and does not start a second one. Before the install it saves the working
# /boot/initramfs-extra to /root/dm1q-plasma/initramfs-extra.pre-plasma (on the rootfs, NOT in the small nested /boot).
#
# Test overrides (scripts/test-phone-plasma-install.sh): ROOT, APK, SYSTEMCTL, DF, SHA, SETSID, NOHUP, POLL, MAXWAIT,
# MINFREE_KB.
ROOT="${ROOT:-}"
APK="${APK:-apk}"; SYSTEMCTL="${SYSTEMCTL:-systemctl}"; DF="${DF:-df}"; SHA="${SHA:-sha256sum}"
SETSID="${SETSID:-setsid}"; NOHUP="${NOHUP:-nohup}"
POLL="${POLL:-5}"; MAXWAIT="${MAXWAIT:-5400}"; MINFREE_KB="${MINFREE_KB:-6000000}"
PKGS="postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile"
STATE="$ROOT/root/dm1q-plasma"
LOG="$STATE/install.log"
REPOS="$ROOT/etc/apk/repositories"
BOOT="$ROOT/boot"

sec() { echo; echo "=== $1"; }
have() { command -v "$1" >/dev/null 2>&1; }
finished() { grep -q '^INSTALL-FINISHED rc=' "$LOG" 2>/dev/null; }
sc() { if have "$SYSTEMCTL"; then "$SYSTEMCTL" "$@" 2>&1; else echo "  (no systemctl)"; fi; }
lsf() { ls -l --full-time "$1" 2>/dev/null || ls -l "$1" 2>&1; }  # busybox ls may lack --full-time
avail_kb() { "$DF" -k "$1" 2>/dev/null | awk 'NR>1 { print $4; exit }'; }

sec "1 guards"
if ! have "$APK"; then echo "no apk: abort"; echo "done"; exit 1; fi
if [ ! -r "$REPOS" ] || grep -q '^http://' "$REPOS"; then
	echo "$REPOS missing or still has http:// lines (the ISP middlebox breaks them): run the apk-https step first. abort"
	echo "done"; exit 1
fi
echo "repositories: https only"
mkdir -p "$STATE"
FREE="$(avail_kb "$ROOT/")"
echo "free on /: ${FREE:-unknown} kB (need >= $MINFREE_KB)"
if [ -z "$FREE" ] || [ "$FREE" -lt "$MINFREE_KB" ]; then echo "not enough free space (or unreadable): abort"; echo "done"; exit 1; fi
if [ -e "$BOOT/initramfs-extra" ]; then
	XSZ="$(wc -c < "$BOOT/initramfs-extra")"; BFREE="$(avail_kb "$BOOT")"
	echo "/boot/initramfs-extra: $XSZ bytes; free on /boot: ${BFREE:-unknown} kB"
	if [ -n "$BFREE" ] && [ "$BFREE" -lt $(( XSZ / 1024 + 10240 )) ]; then
		echo "/boot is too full for mkinitfs to rewrite initramfs-extra: abort"; echo "done"; exit 1
	fi
fi

if [ ! -e "$LOG" ]; then
	sec "2 snapshot before the install (kept in /root/dm1q-plasma)"
	lsf "$BOOT" > "$STATE/boot-before.txt"; cat "$STATE/boot-before.txt"
	if [ -e "$BOOT/initramfs-extra" ]; then
		"$SHA" "$BOOT/initramfs-extra" > "$STATE/initramfs-extra.sha-before" 2>&1; cat "$STATE/initramfs-extra.sha-before"
		cp -p "$BOOT/initramfs-extra" "$STATE/initramfs-extra.pre-plasma" && echo "saved initramfs-extra.pre-plasma"
	else
		echo "no $BOOT/initramfs-extra to save"
	fi
	"$APK" info -v > "$STATE/apk-info-before.txt" 2>&1
	sc list-unit-files --state=enabled > "$STATE/units-enabled-before.txt"
	[ -r "$ROOT/lib/apk/db/triggers" ] && cp "$ROOT/lib/apk/db/triggers" "$STATE/triggers-before.txt"
	echo "packages before: $(wc -l < "$STATE/apk-info-before.txt")"

	sec "3 precaution: mask usb-moded.service (undo: systemctl unmask usb-moded.service)"
	if [ -e "$ROOT/etc/systemd/system/usb-moded.service" ]; then
		echo "an /etc/systemd/system/usb-moded.service already exists, left alone"
	else
		sc mask usb-moded.service
	fi

	sec "4 starting the install, detached (log: /root/dm1q-plasma/install.log)"
	: > "$LOG"
	"$NOHUP" "$SETSID" sh -c "$APK add $PKGS >> '$LOG' 2>&1; echo \"INSTALL-FINISHED rc=\$?\" >> '$LOG'" >/dev/null 2>&1 &
	echo "started"
else
	sec "2-4 an install log already exists: not starting a second install"
fi

sec "5 following the install (Ctrl-C or a dropped ssh does not stop it; run this script again to follow or finish)"
SHOWN=0; WAITED=0
while :; do
	TOTAL="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
	if [ "$TOTAL" -gt "$SHOWN" ]; then
		tail -n +"$((SHOWN + 1))" "$LOG" | head -n "$((TOTAL - SHOWN))"
		SHOWN="$TOTAL"
	fi
	finished && break
	if [ "$WAITED" -ge "$MAXWAIT" ]; then
		echo "still running after ${MAXWAIT}s: stopped following, the install continues in the background. Run this script again later."
		echo "done"; exit 2
	fi
	sleep "$POLL"; WAITED=$((WAITED + POLL))
done
RC="$(sed -n 's/^INSTALL-FINISHED rc=//p' "$LOG" | tail -n 1)"
echo "install finished, rc=$RC"

sec "6 state after the install"
lsf "$BOOT" > "$STATE/boot-after.txt"; cat "$STATE/boot-after.txt"
if [ -e "$BOOT/initramfs-extra" ]; then
	"$SHA" "$BOOT/initramfs-extra" > "$STATE/initramfs-extra.sha-after" 2>&1; cat "$STATE/initramfs-extra.sha-after"
	if [ -r "$STATE/initramfs-extra.sha-before" ] && [ "$(cut -d' ' -f1 "$STATE/initramfs-extra.sha-before")" != "$(cut -d' ' -f1 "$STATE/initramfs-extra.sha-after")" ]; then
		echo "INITRAMFS-EXTRA: CHANGED by the install -> the TWRP fix is REQUIRED before any reboot into the system"
	else
		echo "INITRAMFS-EXTRA: unchanged (unexpected given the udev packages; still run the TWRP check before rebooting)"
	fi
	if have gzip && have cpio; then
		echo "--- usr-merge symlink entries in the new initramfs-extra (bin/lib/sbin -> ... break our stage 1):"
		gzip -dc "$BOOT/initramfs-extra" 2>/dev/null | cpio -itv 2>/dev/null | grep -E ' (bin|lib|sbin) -> ' || echo "  (none found / not listable here)"
	fi
fi
echo "--- relevant units (enabled / active):"
for u in plasma-mobile.service display-manager.service usb-moded.service NetworkManager.service wpa_supplicant.service systemd-resolved.service; do
	echo "$u: $(sc is-enabled "$u" | tr '\n' ' ')/ $(sc is-active "$u" | tr '\n' ' ')"
done
echo "--- unit files matching usb / moded:"
sc list-unit-files | grep -iE 'usb|moded|umtprd' || echo "  (none)"

sec "7 disable autostart of the UI if the install enabled it"
for u in plasma-mobile.service display-manager.service; do
	if [ "$(sc is-enabled "$u" | tr -d '\n')" = enabled ]; then
		echo "$u is enabled: disabling it (UI must be started by hand first)"; sc disable "$u"
	fi
done
echo "now: plasma-mobile=$(sc is-enabled plasma-mobile.service | tr '\n' ' ') display-manager=$(sc is-enabled display-manager.service | tr '\n' ' ')"

sec "8 what the session unit looks like (read this before the first start)"
sc cat plasma-mobile.service
echo "--- /etc/default_user:"; cat "$ROOT/etc/default_user" 2>/dev/null || echo "  (absent)"
echo "--- files of plasma-mobile-systemd and usb-moded packages:"
"$APK" info -L plasma-mobile-systemd postmarketos-usb-moded postmarketos-usb-moded-systemd postmarketos-usb-moded-default-profile-developer 2>&1 | head -80

sec "9 USB / network still as before?"
if have ip; then ip -br a 2>&1; fi
for g in "$ROOT"/sys/kernel/config/usb_gadget/*; do
	[ -d "$g" ] && echo "gadget ${g##*/}: UDC=$(cat "$g/UDC" 2>/dev/null) functions=$(ls "$g/functions" 2>/dev/null | tr '\n' ' ')"
done
echo "packages now: $("$APK" info 2>/dev/null | wc -l)"
[ -r "$ROOT/lib/apk/db/triggers" ] && cp "$ROOT/lib/apk/db/triggers" "$STATE/triggers-after.txt"

echo
echo "################################################################################"
echo "# DO NOT REBOOT INTO THE SYSTEM. /boot/initramfs-extra was regenerated by the install."
echo "# Next: reboot to TWRP (adb reboot recovery, or the key combo), then on the PC:"
echo "#   bash scripts/fix-phone-initramfs-extra.sh          (dry run)"
echo "#   bash scripts/fix-phone-initramfs-extra.sh --yes    (installs the fixed file)"
echo "# Rollback copy of the previous working file: /root/dm1q-plasma/initramfs-extra.pre-plasma"
echo "################################################################################"
echo
echo "done"
