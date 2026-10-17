#!/bin/sh
# Fix "apk update" on the phone and re-simulate the Plasma Mobile install (docs/10 section 6). Runs on the phone as
# root (sudo sh phone-apk-https.sh), POSIX sh / busybox ash.
#
# Why: the home ISP's middlebox answers every plain-HTTP request (the repositories in /etc/apk/repositories are
# http://) with a 307 redirect to a captive-portal HTML page, so apk gets HTML instead of an index ("HTTP:
# unrecognized server error"). HTTPS passes through untouched (notes/2026-10-17-apknet).
#
# What it changes: /etc/apk/repositories, http:// -> https:// (the original is kept once as
# /etc/apk/repositories.dm1q-orig; restore with `cp -p /etc/apk/repositories.dm1q-orig /etc/apk/repositories`),
# and the apk index cache through `apk update`. Nothing is installed: the installation is only SIMULATED
# (`apk add --simulate`), with the pipewire audio backend pinned so pulseaudio is not pulled in next to pipewire.
# No apk trigger runs, so /boot/initramfs-extra is not regenerated (docs/06 rule 3 does not apply to this script).
#
# Test overrides (scripts/test-phone-apk-https.sh): ROOT, APK.
ROOT="${ROOT:-}"
APK="${APK:-apk}"
REPOS="$ROOT/etc/apk/repositories"
BAK="$REPOS.dm1q-orig"

sec() { echo; echo "=== $1"; }

sec "1 repositories"
if [ ! -r "$REPOS" ]; then echo "no $REPOS"; echo "done"; exit 1; fi
if grep -q '^http://' "$REPOS"; then
	[ -e "$BAK" ] || cp -p "$REPOS" "$BAK"
	if sed 's|^http://|https://|' "$REPOS" > "$REPOS.new" && cat "$REPOS.new" > "$REPOS"; then
		echo "switched http:// -> https:// (original kept as ${BAK#"$ROOT"})"
	else
		echo "FAILED to rewrite the repositories file"
	fi
	rm -f "$REPOS.new"
else
	echo "no http:// lines left, nothing to switch"
fi
cat "$REPOS"

sec "2 apk update"
if command -v "$APK" >/dev/null 2>&1; then
	UPD="$("$APK" update 2>&1)"
	echo "$UPD"
	if echo "$UPD" | grep -qE 'WARNING|ERROR|unrecognized'; then
		echo "UPDATE-STATUS: FAILED (see lines above)"; UPDATE_OK=0
	else
		echo "UPDATE-STATUS: OK"; UPDATE_OK=1
	fi
else
	echo "  (no apk)"; UPDATE_OK=0
fi

sec "3 simulation: apk add --simulate postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile"
if [ "$UPDATE_OK" = 1 ]; then
	SIM="$("$APK" add --simulate postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile 2>&1)"
	echo "$SIM"
	echo "--- summary"
	echo "installs: $(echo "$SIM" | grep -c 'Installing')  upgrades: $(echo "$SIM" | grep -c 'Upgrading')  purges: $(echo "$SIM" | grep -c 'Purging')"
	echo "$SIM" | grep -E '^OK:|ERROR|conflict|unable to' || echo "  (no OK/ERROR line)"
	echo "pulseaudio lines: $(echo "$SIM" | grep -c 'pulseaudio')"
	echo "--- selected packages:"
	echo "$SIM" | grep -E 'Installing (postmarketos-base-ui |postmarketos-ui-plasma-mobile |postmarketos-base-ui-plasma |plasma-mobile |kwin |postmarketos-usb-moded |mesa-vulkan-freedreno |plasma-workspace )|Upgrading mesa'
else
	echo "  (skipped: the index update did not succeed; fix that first or restore the original repositories file)"
fi

echo
echo "done"
