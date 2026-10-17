#!/bin/sh
# Read-only preflight for installing Plasma Mobile on the phone (docs/10-plasma-mobile.md). Runs on the phone as
# root (sudo sh phone-plasma-preflight.sh), POSIX sh / busybox ash. It changes nothing on the system: the only
# write is `apk update` (refreshes the package index cache under /var/cache/apk, no triggers, no mkinitfs run);
# set APK_UPDATE=0 to skip even that (then the simulation uses the cached index). The package installation is
# only SIMULATED (`apk add --simulate`).
#
# What it answers: which init system and which Wi-Fi manager / USB gadget manager the rootfs uses today (a UI
# install must not break the USB ssh path or the running Wi-Fi), what free space there is, which packages
# would be installed, which apk triggers exist (docs/06 rule 3: anything touching the mkinitfs trigger dirs
# regenerates /boot/initramfs-extra), and the DRM / input / backlight / session state.
# It prints no SSIDs, no MAC addresses and no password material (connection files are only counted).
#
# Test overrides (scripts/test-phone-plasma-preflight.sh): ROOT (prefix for every file path), APK, IP, DF, FREE,
# PS, LOGINCTL, UNAME_R, APK_UPDATE.
ROOT="${ROOT:-}"
APK="${APK:-apk}"; IP="${IP:-ip}"; DF="${DF:-df}"; FREE="${FREE:-free}"; PS="${PS:-ps}"
LOGINCTL="${LOGINCTL:-loginctl}"
UNAME_R="${UNAME_R:-$(uname -r 2>/dev/null)}"
APK_UPDATE="${APK_UPDATE:-1}"

sec() { echo; echo "=== $1"; }
run() { # run a command if it exists, never fail the script
	if command -v "$1" >/dev/null 2>&1; then "$@" 2>&1; else echo "  (no $1)"; fi
}
show() { if [ -r "$1" ]; then cat "$1"; else echo "  (absent: ${1#"$ROOT"})"; fi; }
have_pkg() { "$APK" info -e "$1" >/dev/null 2>&1; }

sec "1 system"
echo "kernel: $UNAME_R"
show "$ROOT/etc/os-release"
echo "hostname: $(cat "$ROOT/etc/hostname" 2>/dev/null)"
run "$FREE" -m

sec "2 init system"
echo "/sbin/init -> $(readlink "$ROOT/sbin/init" 2>/dev/null || echo '(not a link or absent)')"
if [ -d "$ROOT/run/systemd/system" ]; then echo "running init: systemd"
elif [ -d "$ROOT/run/openrc" ] || [ -d "$ROOT/etc/runlevels" ]; then echo "running init: openrc"
else echo "running init: unknown"; fi
if [ -d "$ROOT/etc/runlevels" ]; then
	for rl in "$ROOT"/etc/runlevels/*; do
		[ -d "$rl" ] || continue
		echo "runlevel ${rl##*/}: $(ls "$rl" 2>/dev/null | tr '\n' ' ')"
	done
fi

sec "3 disk and apk"
run "$DF" -h /
echo "installed packages: $("$APK" info 2>/dev/null | wc -l)"
echo "--- /etc/apk/repositories"; show "$ROOT/etc/apk/repositories"
echo "--- /etc/apk/world"; show "$ROOT/etc/apk/world"

sec "4 apk triggers (docs/06 rule 3: a trigger dir touched by an install regenerates /boot/initramfs-extra)"
show "$ROOT/lib/apk/db/triggers"
echo "--- mkinitfs trigger lines:"
grep -h mkinitfs "$ROOT/lib/apk/db/triggers" 2>/dev/null || echo "  (none found)"
echo "--- dirs in /etc/mkinitfs and /usr/share/mkinitfs:"
ls "$ROOT/etc/mkinitfs" "$ROOT/usr/share/mkinitfs" 2>&1 | head -30

sec "5 network and who manages it"
run "$IP" -br a
echo "--- network-related processes:"
"$PS" 2>/dev/null | grep -E 'wpa_supplicant|iwd|NetworkManager|dhcpcd|udhcpc|connmand|usb-moded|chronyd|sshd|networkmanager' | grep -v grep || echo "  (none matched)"
echo "--- config presence (names of files only, never contents):"
for d in /etc/wpa_supplicant /etc/NetworkManager/conf.d /etc/NetworkManager/system-connections /var/lib/iwd /etc/network; do
	if [ -d "$ROOT$d" ]; then echo "$d: $(ls "$ROOT$d" 2>/dev/null | wc -l) entries"; else echo "$d: absent"; fi
done
[ -r "$ROOT/etc/network/interfaces" ] && { echo "--- /etc/network/interfaces (non-psk lines)"; grep -viE 'psk|key|pass|ssid' "$ROOT/etc/network/interfaces"; }

sec "6 USB gadget (a UI install pulls postmarketos-usb-moded, which may take the gadget over)"
if [ -d "$ROOT/sys/kernel/config/usb_gadget" ]; then
	for g in "$ROOT"/sys/kernel/config/usb_gadget/*; do
		[ -d "$g" ] || continue
		echo "gadget ${g##*/}: UDC=$(cat "$g/UDC" 2>/dev/null) functions=$(ls "$g/functions" 2>/dev/null | tr '\n' ' ')"
	done
else
	echo "  (no configfs usb_gadget dir)"
fi
for f in /etc/conf.d/usb-moded /etc/usb-moded /usr/share/usb-moded /etc/deviceinfo /usr/share/deviceinfo/deviceinfo; do
	[ -e "$ROOT$f" ] && echo "present: $f"
done
echo "--- deviceinfo usb/ui keys:"
grep -hE 'deviceinfo_(usb|drm|screen|ui|dev_touchscreen|rootfs|dtb)' "$ROOT/etc/deviceinfo" "$ROOT/usr/share/deviceinfo/deviceinfo" 2>/dev/null | sort -u

sec "7 UI, session and graphics packages (installed = yes)"
for p in postmarketos-ui-plasma-mobile plasma-mobile kwin plasma-workspace tinydm tinydm-openrc greetd sddm \
	networkmanager iwd wpa_supplicant postmarketos-usb-moded elogind seatd polkit dbus \
	mesa-dri-gallium mesa-gbm mesa-egl mesa-gles mesa-vulkan-freedreno mesa-kmsro pipewire wireplumber \
	callaudiod feedbackd modemmanager iio-sensor-proxy powerdevil xorg-server; do
	if have_pkg "$p"; then echo "yes  $p"; else echo "no   $p"; fi
done

sec "8 DRM, backlight, input, fb"
ls -l "$ROOT/dev/dri" 2>&1
for c in "$ROOT"/sys/class/drm/card*; do
	[ -e "$c" ] || continue
	echo "${c##*/}: driver=$(basename "$(readlink "$c/device/driver" 2>/dev/null)" 2>/dev/null)"
done
for c in "$ROOT"/sys/class/drm/card*-*; do
	[ -e "$c/status" ] && echo "${c##*/}: status=$(cat "$c/status") enabled=$(cat "$c/enabled" 2>/dev/null) modes=$(tr '\n' ' ' < "$c/modes" 2>/dev/null)"
done
for b in "$ROOT"/sys/class/backlight/*; do
	[ -d "$b" ] && echo "backlight ${b##*/}: $(cat "$b/brightness" 2>/dev/null)/$(cat "$b/max_brightness" 2>/dev/null) type=$(cat "$b/type" 2>/dev/null)"
done
for i in "$ROOT"/sys/class/input/input*; do
	[ -d "$i" ] && echo "${i##*/}: $(cat "$i/name" 2>/dev/null)"
done
ls -l "$ROOT"/dev/input 2>&1 | head -20
for f in "$ROOT"/sys/class/graphics/fb*; do
	[ -d "$f" ] && echo "${f##*/}: $(cat "$f/name" 2>/dev/null) $(cat "$f/virtual_size" 2>/dev/null)"
done

sec "9 sessions and users"
run "$LOGINCTL" list-seats
run "$LOGINCTL" list-sessions
echo "--- users with uid >= 1000:"
awk -F: '$3 >= 1000 && $3 < 65534 { print $1, "uid=" $3, "home=" $6, "shell=" $7 }' "$ROOT/etc/passwd" 2>/dev/null
echo "--- relevant groups:"
grep -E '^(wheel|video|input|render|seat|audio|plugdev|netdev|polkitd):' "$ROOT/etc/group" 2>/dev/null
echo "--- sudo/doas:"
for f in /usr/bin/sudo /usr/bin/doas; do [ -e "$ROOT$f" ] && echo "present: $f"; done

sec "10 package index and installation simulation (nothing is installed)"
if [ "$APK_UPDATE" = 1 ]; then
	echo "--- apk update"; run "$APK" update
fi
for p in postmarketos-ui-plasma-mobile plasma-mobile kwin mesa-dri-gallium mesa-vulkan-freedreno postmarketos-usb-moded tinydm; do
	echo "--- apk policy $p"; "$APK" policy "$p" 2>&1 | head -8
done
echo "--- apk add --simulate postmarketos-ui-plasma-mobile"
SIM="$("$APK" add --simulate postmarketos-ui-plasma-mobile 2>&1)"
echo "$SIM"
echo "--- simulated installs: $(echo "$SIM" | grep -c 'Installing')  upgrades: $(echo "$SIM" | grep -c 'Upgrading')  purges: $(echo "$SIM" | grep -c 'Purging')"
echo "--- simulated packages that may touch mkinitfs trigger dirs (names only, a hint not a proof):"
echo "$SIM" | grep -E 'Installing (linux-firmware|postmarketos-base|device-|udev|eudev|mkinitfs|wireless-regdb|postmarketos-base-ui)' || echo "  (none by name; the real list is /lib/apk/db/triggers after the install)"

sec "11 baseline load and temperature"
show "$ROOT/proc/loadavg"
n=0
for z in "$ROOT"/sys/class/thermal/thermal_zone*; do
	[ -d "$z" ] || continue
	n=$((n + 1)); [ "$n" -gt 14 ] && break
	echo "${z##*/} $(cat "$z/type" 2>/dev/null) $(cat "$z/temp" 2>/dev/null)"
done

echo
echo "done"
