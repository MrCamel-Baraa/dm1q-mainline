#!/usr/bin/env bash
# Collect the phone's WLAN/PCIe state + full kernel logs over the phone's USB network and save
# them into the repo, so nothing has to go through the chat while the PC is on the phone's network.
#
# Why: the PC is either on the phone's USB network or on the internet, never both -- and a chat
# session that runs on the PC drops (taking any in-flight output with it) when the network
# switches. So: run this script yourself, in a terminal, while connected to the phone; when it says
# "done", reconnect to the internet and tell Claude, who reads the files from disk.
#
# Usage:  scripts/collect-phone-state.sh <label> [--reboot] [--reload] [--regdump[=idle|load|reload]] [--fresh] [--touch] [--display] [--drm-test] [--backlight] [--plasma-preflight] [--apknet] [--apk-https] [--plasma-install]
#   <label>      names the output dir: notes/<YYYY-MM-DD>-<label>/   (e.g. v8-wlan-rails); reusing a
#                label on the same day overwrites files with the same name
#   --reboot     first `adb reboot` (phone sitting in recovery -> boots the system)
#   --reload     also run scripts/phone-ath11k-reload.sh (reload ath11k_pci, sample the PCIe link for ~30 s)
#   --regdump    also run scripts/phone-mhi-regdump.sh in the given mode (default load): sample the chip's
#                MHI/BHI registers (and the interrupt counters, the endpoint's MSI state and the PCIe controller's
#                BDF-to-SID table) while ath11k's power-up runs (adds regdump.txt). It reads MMIO through the static
#                helper scripts/bin/mmio-read-aarch64, which this script copies to the phone (build it once with
#                `bash scripts/build-mmio-read.sh`; docs/07 section 14 says why dd on /dev/mem cannot do it).
#   --fresh      the representative experiment, in one go: blacklist ath11k_pci, reboot the phone over ssh,
#                log in again (second password prompt), then on the freshly powered, untouched chip run the
#                probe, the register sampler in idle mode (chip in PBL, nobody talking to it) and then in
#                load mode (a clean ath11k attempt), and collect everything. The blacklist file is removed
#                again right after the reboot, so later boots are normal.
#   --touch      also run scripts/phone-touch-spi-probe.sh (docs/08 step B1: needs the spidev test image; loads
#                gpi / spi_geni_qcom / spidev, talks the FTS2BA61Y protocol over /dev/spidev*, adds touch.txt). It uses
#                the static helper scripts/bin/spi-xfer-aarch64 (build once with `bash scripts/build-spi-xfer.sh`).
#   --display    also run scripts/phone-display-probe.sh (docs/09: read-only; running kernel config, display modules,
#                DRM/fbdev state, platform devices and their drivers, clocks, panel rails and GPIOs, display dmesg
#                lines; adds display.txt). No modprobe, no MMIO.
#   --drm-test   also run scripts/phone-drm-test.sh with the static helper scripts/bin/drm-fill-aarch64 (build once with
#                `bash scripts/build-drm-fill.sh`): lists the msm DRM card's connectors, then SHOWS TEST PATTERNS on the
#                panel (bars 12 s, then red/green/blue/white 5 s each, ~35 s) -- watch the phone; adds drm-test.txt.
#   --backlight  also run scripts/phone-backlight-test.sh (docs/09 section 17): shows solid white (drm-fill, same helper as
#                --drm-test) and sweeps the panel's brightness 100 % -> raw 1 -> 0, then restores it (~1 min) -- watch the
#                phone; adds backlight.txt.
#   --plasma-preflight  also run scripts/phone-plasma-preflight.sh (docs/10: read-only; init system, Wi-Fi / USB-gadget
#                managers, free space, apk triggers, UI packages, DRM/input/backlight, sessions, and an `apk add --simulate`
#                of postmarketos-ui-plasma-mobile; the only write is `apk update`, which needs the phone's Wi-Fi internet;
#                adds plasma-preflight.txt, which prints no SSIDs/MACs/passwords but is still not for committing raw).
#   --apknet     also run scripts/phone-apknet-diag.sh (docs/10 section 5: read-only; why `apk update` fails on the phone:
#                clock, route/DNS/MTU, ICMP, HTTP/HTTPS fetch of the index files with headers, `apk update -vv`; adds apknet.txt).
#   --apk-https  also run scripts/phone-apk-https.sh (docs/10 section 6: CHANGES /etc/apk/repositories http:// -> https:// (original
#                kept as repositories.dm1q-orig) because the ISP middlebox hijacks plain HTTP, runs `apk update`, and SIMULATES the
#                Plasma Mobile install with the pipewire backend pinned; installs nothing; adds apk-https.txt).
#   --plasma-install  also run scripts/phone-plasma-install.sh (docs/10 section 8): INSTALLS Plasma Mobile (apk add, ~2.7 GB, 15-40 min,
#                detached on the phone so a dropped ssh does not kill it; re-run the same command to follow/finish), masks usb-moded,
#                saves the working initramfs-extra, does NOT start the UI and does NOT reboot. The install regenerates
#                /boot/initramfs-extra: DO NOT boot the system afterwards, go to TWRP and run scripts/fix-phone-initramfs-extra.sh
#                first (docs/06 rule 3). Adds plasma-install.txt.
# Env:  PHONE=172.16.42.1  PHONE_USER=user  WAIT_PING=240 (seconds to wait for the USB network)
#
# What it does on the phone: only reads (plus module loads and the temporary modprobe blacklist), writes
# under /tmp/dm1q-collect (probe.txt from scripts/phone-wlan-probe.sh, dmesg.txt, journal-kernel.txt,
# regulator_summary.txt, gpio.txt[, reload.txt, regdump*.txt]), as root through one sudo call per login.
# Everything shown on the terminal during the collection is also kept in session.log on the PC.
set -u
LABEL=""; REBOOT=0; RELOAD=0; REGDUMP=""; FRESH=0; TOUCH=0; DISPLAY_PROBE=0; DRM_TEST=0; BACKLIGHT=0; PLASMA_PRE=0; APKNET=0; APK_HTTPS=0; PLASMA_INSTALL=0
for a in "$@"; do
	case "$a" in
	--reboot) REBOOT=1 ;;
	--reload) RELOAD=1 ;;
	--regdump) REGDUMP=load ;;
	--regdump=idle|--regdump=load|--regdump=reload) REGDUMP="${a#--regdump=}" ;;
	--fresh) FRESH=1 ;;
	--touch) TOUCH=1 ;;
	--display) DISPLAY_PROBE=1 ;;
	--drm-test) DRM_TEST=1 ;;
	--backlight) BACKLIGHT=1 ;;
	--plasma-preflight) PLASMA_PRE=1 ;;
	--apknet) APKNET=1 ;;
	--apk-https) APK_HTTPS=1 ;;
	--plasma-install) PLASMA_INSTALL=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) LABEL="$a" ;;
	esac
done
[ -n "$LABEL" ] || { sed -n '2,/^[^#]/p' "$0" | sed '$d'; exit 2; }
PHONE="${PHONE:-172.16.42.1}"
PUSER="${PHONE_USER:-user}"
WAIT_PING="${WAIT_PING:-240}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MMIO_BIN="$REPO/scripts/bin/mmio-read-aarch64"
if [ "$FRESH" = 1 ] || [ -n "$REGDUMP" ]; then
	[ -f "$MMIO_BIN" ] || { echo "no $MMIO_BIN -- run: bash scripts/build-mmio-read.sh   (needs clang + lld)"; exit 1; }
fi
SPI_BIN="$REPO/scripts/bin/spi-xfer-aarch64"
DRM_BIN="$REPO/scripts/bin/drm-fill-aarch64"
if [ "$DRM_TEST" = 1 ] || [ "$BACKLIGHT" = 1 ]; then
	[ -f "$DRM_BIN" ] || { echo "no $DRM_BIN -- run: bash scripts/build-drm-fill.sh   (needs clang + lld)"; exit 1; }
fi
if [ "$TOUCH" = 1 ]; then
	[ -f "$SPI_BIN" ] || { echo "no $SPI_BIN -- run: bash scripts/build-spi-xfer.sh   (needs clang + lld)"; exit 1; }
fi
DEST="$REPO/notes/$(date +%Y-%m-%d)-$LABEL"
CP="/tmp/dm1q-ssh-$$"
SSH_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR
          -o ControlPath="$CP" -o ConnectTimeout=10)
mkdir -p "$DEST"

push_scripts() {
	scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-wlan-probe.sh" "$REPO/scripts/phone-ath11k-reload.sh" "$REPO/scripts/phone-mhi-regdump.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the scripts failed"; exit 1; }
	if [ -f "$MMIO_BIN" ]; then
		scp "${SSH_OPTS[@]}" -q "$MMIO_BIN" "$PUSER@$PHONE:/tmp/mmio-read" || { echo "scp of the MMIO helper failed"; exit 1; }
	fi
	if [ "$DISPLAY_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-display-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the display probe failed"; exit 1; }
	fi
	if [ "$PLASMA_INSTALL" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-plasma-install.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the Plasma install script failed"; exit 1; }
	fi
	if [ "$APK_HTTPS" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-apk-https.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the apk https script failed"; exit 1; }
	fi
	if [ "$APKNET" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-apknet-diag.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the apk network diagnosis failed"; exit 1; }
	fi
	if [ "$PLASMA_PRE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-plasma-preflight.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the Plasma preflight failed"; exit 1; }
	fi
	if [ "$DRM_TEST" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-drm-test.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the DRM test failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$DRM_BIN" "$PUSER@$PHONE:/tmp/drm-fill" || { echo "scp of drm-fill failed"; exit 1; }
	fi
	if [ "$BACKLIGHT" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-backlight-test.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the backlight test failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$DRM_BIN" "$PUSER@$PHONE:/tmp/drm-fill" || { echo "scp of drm-fill failed"; exit 1; }
	fi
	if [ "$TOUCH" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-spi-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch probe failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$SPI_BIN" "$PUSER@$PHONE:/tmp/spi-xfer" || { echo "scp of the SPI helper failed"; exit 1; }
	fi
}
wait_up() {
	local t=0
	echo "waiting up to ${WAIT_PING}s for the phone at $PHONE (connect the PC to the phone's USB network if it does not switch by itself) ..."
	until ping -c1 -W1 "$PHONE" >/dev/null 2>&1; do
		sleep 2; t=$((t + 3)); [ $((t % 30)) -lt 3 ] && echo "  ... ${t}s"
		if [ "$t" -ge "$WAIT_PING" ]; then
			echo "no answer from $PHONE after ${WAIT_PING}s: the phone did not reach userspace (or the USB network is not up)."
			echo "Reboot it to recovery and ask Claude to pull the stage-1 log from the dtbo partition."
			exit 1
		fi
	done
	echo "phone answers after ~${t}s -- userspace is up"
	t=0; until timeout 3 bash -c "exec 3<>/dev/tcp/$PHONE/22" 2>/dev/null; do
		sleep 2; t=$((t + 3)); [ "$t" -ge 90 ] && { echo "ssh port 22 never opened"; exit 1; }
	done
}
login() {
	echo "== log in (password prompt; the connection is reused afterwards) =="
	ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -o ControlPersist=900 -fN "$PUSER@$PHONE" || { echo "ssh login failed"; exit 1; }
}
trap 'ssh "${SSH_OPTS[@]}" -O exit "$PUSER@$PHONE" 2>/dev/null' EXIT

if [ "$REBOOT" = 1 ]; then
	[ "$(adb get-state 2>/dev/null || true)" = recovery ] || echo "note: adb does not see the phone in recovery; trying the reboot anyway"
	echo "adb reboot ..."; adb reboot || true
	sleep 5
fi

wait_up
login
push_scripts

if [ "$FRESH" = 1 ]; then
	echo "== phase 1: blacklist ath11k_pci for the next boot and reboot the phone (sudo asks for the password) =="
	ssh "${SSH_OPTS[@]}" -t "$PUSER@$PHONE" "sudo sh -c \"echo 'blacklist ath11k_pci' > /etc/modprobe.d/zz-dm1q-test.conf; sync; nohup sh -c 'sleep 2; reboot' >/dev/null 2>&1 &\"" 2>&1 | tee "$DEST/session-phase1.log"
	ssh "${SSH_OPTS[@]}" -O exit "$PUSER@$PHONE" 2>/dev/null
	echo "waiting for the phone to go down ..."
	t=0; while ping -c1 -W1 "$PHONE" >/dev/null 2>&1; do sleep 1; t=$((t + 1)); [ "$t" -ge 90 ] && { echo "the phone did not go down"; exit 1; }; done
	echo "down after ~${t}s; waiting for it to come back (a normal boot reaches userspace in ~15 s)"
	wait_up
	login
	push_scripts
fi

BODY='rm -f /etc/modprobe.d/zz-dm1q-test.conf
chmod +x /tmp/mmio-read /tmp/spi-xfer 2>/dev/null
rm -rf /tmp/dm1q-collect; mkdir -p /tmp/dm1q-collect
mount | grep -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug'
if [ "$FRESH" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-wlan-probe.sh 2>&1 | tee /tmp/dm1q-collect/probe-idle.txt
sh /tmp/phone-mhi-regdump.sh idle 2>&1 | tee /tmp/dm1q-collect/regdump-idle.txt
sh /tmp/phone-mhi-regdump.sh load 2>&1 | tee /tmp/dm1q-collect/regdump-load.txt"
elif [ -n "$REGDUMP" ]; then
	BODY="$BODY
sh /tmp/phone-mhi-regdump.sh $REGDUMP 2>&1 | tee /tmp/dm1q-collect/regdump.txt"
fi
if [ "$TOUCH" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-touch-spi-probe.sh 2>&1 | tee /tmp/dm1q-collect/touch.txt"
fi
if [ "$DISPLAY_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-display-probe.sh 2>&1 | tee /tmp/dm1q-collect/display.txt"
fi
if [ "$PLASMA_INSTALL" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-plasma-install.sh 2>&1 | tee /tmp/dm1q-collect/plasma-install.txt"
fi
if [ "$APK_HTTPS" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-apk-https.sh 2>&1 | tee /tmp/dm1q-collect/apk-https.txt"
fi
if [ "$APKNET" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-apknet-diag.sh 2>&1 | tee /tmp/dm1q-collect/apknet.txt"
fi
if [ "$PLASMA_PRE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-plasma-preflight.sh 2>&1 | tee /tmp/dm1q-collect/plasma-preflight.txt"
fi
if [ "$DRM_TEST" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-drm-test.sh /tmp/drm-fill 2>&1 | tee /tmp/dm1q-collect/drm-test.txt"
fi
if [ "$BACKLIGHT" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-backlight-test.sh /tmp/drm-fill 2>&1 | tee /tmp/dm1q-collect/backlight.txt"
fi
BODY="$BODY
sh /tmp/phone-wlan-probe.sh 2>&1 | tee /tmp/dm1q-collect/probe.txt
dmesg > /tmp/dm1q-collect/dmesg.txt 2>&1
journalctl -k -b --no-pager > /tmp/dm1q-collect/journal-kernel.txt 2>&1
cat /sys/kernel/debug/regulator/regulator_summary > /tmp/dm1q-collect/regulator_summary.txt 2>&1
cat /sys/kernel/debug/gpio > /tmp/dm1q-collect/gpio.txt 2>&1"
if [ "$RELOAD" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-ath11k-reload.sh 2>&1 | tee /tmp/dm1q-collect/reload.txt
dmesg > /tmp/dm1q-collect/dmesg-after-reload.txt 2>&1"
fi
BODY="$BODY
chmod -R a+rX /tmp/dm1q-collect
ls -la /tmp/dm1q-collect"

RMSG=""
[ "$RELOAD" = 1 ] && RMSG="; the reload step takes ~30 s"
[ -n "$REGDUMP" ] && RMSG="$RMSG; the regdump step takes ~40 s"
[ "$TOUCH" = 1 ] && RMSG="$RMSG; the touch probe takes ~10 s"
[ "$PLASMA_INSTALL" = 1 ] && RMSG="$RMSG; THE PLASMA MOBILE INSTALL takes 15-40 min and changes the system: stay on the USB network, do NOT reboot the phone into the system afterwards (TWRP + fix-phone-initramfs-extra.sh first)"
[ "$APK_HTTPS" = 1 ] && RMSG="$RMSG; the apk https step downloads ~7 MB of indexes and runs a simulation (~1-2 min); it edits /etc/apk/repositories"
[ "$APKNET" = 1 ] && RMSG="$RMSG; the apk network diagnosis takes ~2 min (it fetches index files and runs apk update -vv)"
[ "$PLASMA_PRE" = 1 ] && RMSG="$RMSG; the Plasma preflight takes ~1 min (apk update + simulation need the phone's Wi-Fi internet)"
[ "$DRM_TEST" = 1 ] && RMSG="$RMSG; the DRM pattern test takes ~35 s: WATCH THE PHONE SCREEN"
[ "$BACKLIGHT" = 1 ] && RMSG="$RMSG; the backlight sweep takes ~1 min: WATCH THE PHONE SCREEN (white, getting dimmer)"
[ "$FRESH" = 1 ] && RMSG="; the idle + load steps take ~1.5 min"
echo "== collecting on the phone (sudo asks for the password once$RMSG) =="
# everything shown is also kept in session.log, so a hang on the phone does not lose the partial output
ssh "${SSH_OPTS[@]}" -t "$PUSER@$PHONE" "sudo sh -c \"$BODY\"" 2>&1 | tee "$DEST/session.log"

echo "== pulling the files =="
scp "${SSH_OPTS[@]}" -q "$PUSER@$PHONE:/tmp/dm1q-collect/*" "$DEST/" || { echo "scp of the results failed (see $DEST/session.log for what was printed)"; exit 1; }
ssh "${SSH_OPTS[@]}" "$PUSER@$PHONE" 'rm -rf /tmp/dm1q-collect /tmp/phone-wlan-probe.sh /tmp/phone-ath11k-reload.sh /tmp/phone-mhi-regdump.sh /tmp/mmio-read /tmp/phone-touch-spi-probe.sh /tmp/spi-xfer /tmp/phone-display-probe.sh /tmp/phone-drm-test.sh /tmp/phone-backlight-test.sh /tmp/drm-fill /tmp/phone-plasma-preflight.sh /tmp/phone-apknet-diag.sh /tmp/phone-apk-https.sh /tmp/phone-plasma-install.sh' 2>/dev/null || true
for f in "$DEST"/*; do tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
ls -la "$DEST"
echo
echo "done. Saved in $DEST"
echo "You can reconnect the PC to the internet now and tell Claude."
