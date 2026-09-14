#!/bin/sh
# Stage the ADSP (audio DSP) firmware for firmware-samsung-gts9uwifi.
#
# These are Samsung/Qualcomm signed blobs and are NOT redistributable, so they
# are never committed - exactly like the Wi-Fi, Bluetooth, GPU and CS35L45
# firmware.  They live in the stock `apnhlos` partition of the tablet itself,
# under /image/, so every owner of an SM-X910 can regenerate them from their own
# device.  Every file is checked against the pinned manifest
# `adsp-firmware.sha512` before it is accepted.
#
# The partition is mounted READ-ONLY.  Nothing on the device is modified.
#
# Usage:
#   GTS9U_HOST=phablet@10.0.0.5 GTS9U_PW=... scripts/stage-stock-adsp-firmware.sh
# Environment:
#   GTS9U_HOST   ssh target of the tablet   (required)
#   GTS9U_PW     sudo password on the tablet (required)
#   GTS9U_KEY    ssh private key            (default ~/.ssh/gts9u_pmos)
set -eu

project=${PROJECT_ROOT:-"$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"}
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"
manifest="$target/adsp-firmware.sha512"
key=${GTS9U_KEY:-"$HOME/.ssh/gts9u_pmos"}

[ -f "$manifest" ] || {
	echo "missing manifest: $manifest" >&2
	exit 1
}

# Nothing to do if every pinned file is already staged and intact.
if (cd "$target" && sha512sum -c --status "$manifest") 2>/dev/null; then
	echo "SM-X910 ADSP firmware already staged and verified."
	exit 0
fi

host=${GTS9U_HOST:?set GTS9U_HOST to the ssh target of the tablet}
pw=${GTS9U_PW:?set GTS9U_PW to the sudo password on the tablet}

echo "Staging ADSP firmware from the device's own apnhlos partition..."
mkdir -p "$target"

ssh_opts="-i $key -o BatchMode=yes -o ConnectTimeout=10"

# Build the archive on the device and fetch it with scp.  Streaming tar over the
# ssh channel would interleave the binary with mount's chatter on the same
# stdout, which silently produces an empty archive.
ssh $ssh_opts "$host" 'sh -s' <<REMOTE
set -eu
echo '$pw' | sudo -S sh -c '
	rm -f /tmp/adsp-stage.tar
	mkdir -p /tmp/apnhlos-ro
	mountpoint -q /tmp/apnhlos-ro || \
		mount -o ro /dev/disk/by-partlabel/apnhlos /tmp/apnhlos-ro
	cd /tmp/apnhlos-ro/image
	tar -cf /tmp/adsp-stage.tar \
		adsp.mdt adsp.b* adsp_dtb.mdt adsp_dtb.b* \
		adspr.jsn adsps.jsn adspua.jsn cdspr.jsn
	cd /
	umount /tmp/apnhlos-ro
	chmod 644 /tmp/adsp-stage.tar
' 2>&1 | grep -v '^\[sudo' || true
test -s /tmp/adsp-stage.tar
REMOTE

scp $ssh_opts "$host:/tmp/adsp-stage.tar" "$target/.adsp-stage.tar" >/dev/null

# The archive is owned by root in a sticky /tmp, so clean it up as root too.
ssh $ssh_opts "$host" "echo '$pw' | sudo -S rm -f /tmp/adsp-stage.tar" \
	>/dev/null 2>&1 || true

tar -xf "$target/.adsp-stage.tar" -C "$target"
rm -f "$target/.adsp-stage.tar"

# Refuse to hand the build anything that does not match the pinned hashes.
if ! (cd "$target" && sha512sum -c --status "$manifest"); then
	echo "ADSP firmware does not match the pinned manifest; refusing." >&2
	(cd "$target" && sha512sum -c "$manifest" 2>&1 | grep -v ': OK$' | head) >&2
	exit 1
fi

echo "SM-X910 ADSP firmware staged and verified ($(wc -l < "$manifest") files)."
