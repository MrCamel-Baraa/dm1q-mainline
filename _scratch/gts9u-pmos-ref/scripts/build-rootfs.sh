#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
pmb_py="$base/pmbootstrap/pmbootstrap.py"
pmaports="$base/pmaports"
work="$base/pmbootstrap-work"
config="${PMBOOTSTRAP_CONFIG:-/root/.config/pmbootstrap_v3.cfg}"
export_dir="${ROOTFS_EXPORT_DIR:-$base/out/rootfs-gts9uwifi}"

test -f "$pmb_py"
test -d "$pmaports/device/testing/device-samsung-gts9uwifi"

pmb() {
	python3 "$pmb_py" --as-root \
		-c "$config" -p "$pmaports" -w "$work" \
		--details-to-stdout "$@"
}

if [ ! -f "$config" ]; then
	echo "pmbootstrap config is not initialized: $config" >&2
	echo "Run once: python3 $pmb_py --as-root -c $config -p $pmaports -w $work init" >&2
	exit 2
fi

pmb config aports "$pmaports"
pmb config work "$work"
pmb config device samsung-gts9uwifi
# GNOME by default; GTS9U_UI=xfce4 still builds the original desktop.
pmb config ui "${GTS9U_UI:-gnome}"
pmb config service_manager systemd
pmb config user phablet
pmb config hostname gts9u
pmb config timezone Europe/Madrid
pmb config locale es_ES.UTF-8
pmb config extra_packages openssh

# Build a two-partition image file only.  The boot partition stores
# initramfs-extra so the early initramfs can fit the X910 8 MiB init_boot
# partition; the root partition holds the desktop.  No --disk/--sdcard
# argument is accepted here, so this cannot overwrite a physical microSD.
#
# The image stays small on purpose: it is written to whatever microSD the owner
# has, and gts9uwifi-grow-rootfs.service expands the root partition and its
# filesystem to fill the card on first boot.  Sizing the image to one
# particular card would only move the problem to the next card.
pmb -E "${GTS9U_EXTRA_MB:-2048}" install \
	--sector-size 512 \
	--filesystem ext4 \
	--password "${GTS9U_PW:?set GTS9U_PW to the password for the phablet user}" \
	--add openssh

mkdir -p "$export_dir"
pmb export "$export_dir"

printf '%s\n' '===== exported rootfs/initramfs files ====='
find "$export_dir" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
