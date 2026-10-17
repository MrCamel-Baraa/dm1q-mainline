#!/usr/bin/env bash
# PC-side test of scripts/phone-plasma-preflight.sh (docs/06 rule 3). The phone's root is replaced by a scratch
# tree (ROOT=) and apk / ip / df / free / ps / loginctl by stubs; the script runs with dash (closest to the phone's
# busybox ash: no bashisms allowed) and with bash. Two scenarios:
#   full   openrc rootfs, usb gadget, Wi-Fi processes, DRM + backlight + touch, a user, apk with packages + a simulation
#   bare   an empty root and no commands at all: every section must still print and the script must end with "done"
# Also checks that nothing secret-shaped (SSID/psk words from the fake config files) reaches the output, and that
# the script never calls `apk add` without --simulate.
# Usage: bash scripts/test-phone-plasma-preflight.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

# ---- scenario full
F="$W/full"; R="$F/root"; mkdir -p "$F/bin" "$R"
mkdir -p "$R/etc/apk" "$R/lib/apk/db" "$R/run/openrc" "$R/etc/runlevels/default" "$R/etc/runlevels/boot" \
	"$R/etc/wpa_supplicant" "$R/etc/NetworkManager/system-connections" "$R/sys/kernel/config/usb_gadget/g1/functions/ncm.usb0" \
	"$R/sys/class/drm/card1/device" "$R/sys/class/drm/card1-DSI-1" "$R/sys/class/backlight/ae94000.dsi.0" \
	"$R/sys/class/input/input3" "$R/sys/class/graphics/fb0" "$R/sys/class/thermal/thermal_zone0" "$R/dev/dri" "$R/dev/input" \
	"$R/sys/drivers-real/msm" "$R/proc" "$R/usr/share/mkinitfs" "$R/etc/mkinitfs" "$R/usr/share/deviceinfo" "$R/etc/network"
printf 'NAME="postmarketOS"\nVERSION_ID=edge\nID=postmarketos\n' > "$R/etc/os-release"
echo samsung-dm1q > "$R/etc/hostname"
printf 'https://mirror.example/edge/main\nhttps://mirror.example/edge/community\n' > "$R/etc/apk/repositories"
printf 'alpine-base\ndevice-samsung-dm1q\n' > "$R/etc/apk/world"
printf 'mkinitfs /lib/firmware\nmkinitfs /usr/lib/udev\nbusybox /etc/mkinitfs\n' > "$R/lib/apk/db/triggers"
ln -s /sbin/openrc-init "$R/sbin-init-target" ; mkdir -p "$R/sbin"; ln -s /sbin/openrc-init "$R/sbin/init"
touch "$R/etc/runlevels/default/sshd" "$R/etc/runlevels/boot/udev"
echo "SUPERSECRETSSID psk=hunter2" > "$R/etc/wpa_supplicant/wpa_supplicant.conf"
echo "ssid=SUPERSECRETSSID" > "$R/etc/NetworkManager/system-connections/home.nmconnection"
echo "a7f4e2" > "$R/sys/kernel/config/usb_gadget/g1/UDC"
ln -s "$F/../full/root/sys/drivers-real/msm" "$R/sys/class/drm/card1/device/driver"
echo connected > "$R/sys/class/drm/card1-DSI-1/status"; echo enabled > "$R/sys/class/drm/card1-DSI-1/enabled"; echo 1080x2340 > "$R/sys/class/drm/card1-DSI-1/modes"
echo 2047 > "$R/sys/class/backlight/ae94000.dsi.0/brightness"; echo 2047 > "$R/sys/class/backlight/ae94000.dsi.0/max_brightness"; echo raw > "$R/sys/class/backlight/ae94000.dsi.0/type"
echo "fts2ba61y" > "$R/sys/class/input/input3/name"
echo msmdrmfb > "$R/sys/class/graphics/fb0/name"; echo 1080,2340 > "$R/sys/class/graphics/fb0/virtual_size"
echo "0.10 0.05 0.01 1/100 1234" > "$R/proc/loadavg"
echo cpu0-thermal > "$R/sys/class/thermal/thermal_zone0/type"; echo 41000 > "$R/sys/class/thermal/thermal_zone0/temp"
touch "$R/dev/dri/card1"
printf 'root:x:0:0:root:/root:/bin/ash\nuser:x:10000:10000::/home/user:/bin/ash\n' > "$R/etc/passwd"
printf 'wheel:x:10:user\nvideo:x:12:user\ninput:x:23:\nunrelated:x:99:\n' > "$R/etc/group"
printf 'deviceinfo_drm="true"\ndeviceinfo_usb_network_function="ncm.usb0"\ndeviceinfo_name="Galaxy S23"\n' > "$R/usr/share/deviceinfo/deviceinfo"
# stubs
cat > "$F/bin/apk" <<EOF
#!/bin/sh
echo "\$*" >> "$F/apk-calls.log"
case "\$1" in
info)
	if [ "\$2" = -e ]; then case "\$3" in elogind|networkmanager|wpa_supplicant|mesa-dri-gallium) exit 0 ;; *) exit 1 ;; esac; fi
	printf 'alpine-base\nbusybox\nelogind\n' ;;
update) echo "fetch https://mirror.example/edge/main/aarch64/APKINDEX.tar.gz"; echo "OK: 99999 distinct packages available" ;;
policy) echo "\$2 policy line"; echo "  1.2.3-r0:"; echo "    https://mirror.example/edge/main" ;;
add) if [ "\$2" != --simulate ]; then echo "REAL ADD ATTEMPTED"; exit 9; fi
	echo "(1/3) Installing plasma-mobile (6.0-r0)"; echo "(2/3) Installing postmarketos-base-ui (62-r0)"; echo "(3/3) Installing kwin (6.0-r0)"; echo "OK: 1500 MiB in 700 packages" ;;
esac
EOF
printf '#!/bin/sh\necho "lo UNKNOWN 127.0.0.1/8"\necho "wlan0 UP 192.168.1.50/24"\necho "usb0 UP 172.16.42.1/24"\n' > "$F/bin/ip"
printf '#!/bin/sh\necho "Filesystem Size Used Avail Use%% Mounted on"\necho "/dev/sda1 222G 4G 218G 2%% /"\n' > "$F/bin/df"
printf '#!/bin/sh\necho "total used free"\necho "Mem: 11800 900 9000"\n' > "$F/bin/free"
printf '#!/bin/sh\necho " 123 root 0:01 /usr/sbin/wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf"\necho " 124 root 0:00 sshd"\necho " 125 root 0:00 ps"\n' > "$F/bin/ps"
printf '#!/bin/sh\necho "SEAT SESSIONS"\n' > "$F/bin/loginctl"
chmod +x "$F"/bin/*

run_full() { # shell
	env ROOT="$R" APK="$F/bin/apk" IP="$F/bin/ip" DF="$F/bin/df" FREE="$F/bin/free" PS="$F/bin/ps" LOGINCTL="$F/bin/loginctl" \
		UNAME_R=7.3.0-rc3-dm1q "$1" "$HERE/phone-plasma-preflight.sh" > "$F/out" 2>&1
}

# ---- scenario bare
B="$W/bare"; mkdir -p "$B/root"
run_bare() {
	env ROOT="$B/root" APK="$B/none-apk" IP="$B/none-ip" DF="$B/none-df" FREE="$B/none-free" PS="$B/none-ps" LOGINCTL="$B/none-loginctl" \
		UNAME_R=7.3.0-rc3-dm1q "$1" "$HERE/phone-plasma-preflight.sh" > "$B/out" 2>&1
}

expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	: > "$F/apk-calls.log"
	echo "== $sh, scenario full"
	run_full "$sh" || bad "$sh exits non-zero"
	expect "$F/out" "kernel shown" "kernel: 7\\.3\\.0-rc3-dm1q"
	expect "$F/out" "os-release" "ID=postmarketos"
	expect "$F/out" "init link" "/sbin/init -> /sbin/openrc-init"
	expect "$F/out" "init openrc" "running init: openrc"
	expect "$F/out" "runlevel listing" "runlevel default: sshd"
	expect "$F/out" "df shown" "218G"
	expect "$F/out" "package count" "installed packages: 3"
	expect "$F/out" "repositories" "mirror\\.example/edge/main"
	expect "$F/out" "triggers file" "mkinitfs /lib/firmware"
	expect "$F/out" "mkinitfs trigger lines" "^mkinitfs /usr/lib/udev"
	expect "$F/out" "ip output" "wlan0 UP"
	expect "$F/out" "wpa_supplicant process" "wpa_supplicant -B -i wlan0"
	expect "$F/out" "config counted, not read" "system-connections: 1 entries"
	expect "$F/out" "usb gadget" "gadget g1: UDC=a7f4e2 functions=ncm\\.usb0"
	expect "$F/out" "deviceinfo keys" "deviceinfo_usb_network_function"
	expect "$F/out" "installed package yes" "^yes  elogind"
	expect "$F/out" "absent package no" "^no   kwin"
	expect "$F/out" "dri listing" "card1"
	expect "$F/out" "drm driver" "card1: driver=msm"
	expect "$F/out" "connector" "card1-DSI-1: status=connected enabled=enabled modes=1080x2340"
	expect "$F/out" "backlight" "backlight ae94000\\.dsi\\.0: 2047/2047 type=raw"
	expect "$F/out" "input name" "input3: fts2ba61y"
	expect "$F/out" "fb" "fb0: msmdrmfb 1080,2340"
	expect "$F/out" "user listed" "^user uid=10000 home=/home/user"
	expect "$F/out" "root not listed as user" "." ; reject "$F/out" "root not in uid>=1000 list" "^root uid=0"
	expect "$F/out" "group line" "^video:x:12:user"
	reject "$F/out" "unrelated group dropped" "^unrelated:"
	expect "$F/out" "apk update ran" "OK: 99999 distinct packages"
	expect "$F/out" "policy" "postmarketos-ui-plasma-mobile policy line"
	expect "$F/out" "simulation printed" "Installing plasma-mobile"
	expect "$F/out" "simulation counts" "simulated installs: 3"
	expect "$F/out" "mkinitfs hint" "Installing postmarketos-base-ui"
	expect "$F/out" "load avg" "0\\.10 0\\.05"
	expect "$F/out" "thermal" "thermal_zone0 cpu0-thermal 41000"
	expect "$F/out" "ends with done" "^done$"
	reject "$F/out" "no SSID leak" "SUPERSECRETSSID"
	reject "$F/out" "no psk leak" "hunter2"
	reject "$F/out" "no real apk add" "REAL ADD ATTEMPTED"
	if grep -E '^add ' "$F/apk-calls.log" | grep -vqE '^add --simulate '; then bad "$sh: apk add without --simulate"; else ok "$sh: every apk add is --simulate"; fi

	echo "== $sh, scenario bare"
	run_bare "$sh" || bad "$sh exits non-zero (bare)"
	expect "$B/out" "bare: os-release absent" "absent: /etc/os-release"
	expect "$B/out" "bare: init unknown" "running init: unknown"
	expect "$B/out" "bare: no apk reported" "\\(no .*none-apk\\)|installed packages: 0"
	expect "$B/out" "bare: gadget dir absent" "no configfs usb_gadget dir"
	expect "$B/out" "bare: all sections printed" "=== 11 baseline load and temperature"
	expect "$B/out" "bare: ends with done" "^done$"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
