#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
target="$base/cache/sensor-userspace"
mkdir -p "$target"

if [ "${REBUILD_HEXAGONRPCD:-0}" = 1 ] ||
   [ ! -f "$base/pmbootstrap-work/packages/edge/aarch64/hexagonrpcd-0.4.0-r4.apk" ]; then
	bash "$project/scripts/build-custom-hexagonrpcd.sh"
fi

package_dir="$base/pmbootstrap-work/packages/edge/aarch64"
for name in \
	hexagonrpcd-0.4.0-r4.apk \
	hexagonrpcd-systemd-0.4.0-r4.apk \
	hexagonrpcd-udev-0.4.0-r4.apk; do
	test -f "$package_dir/$name"
	install -m 0644 "$package_dir/$name" "$target/$name"
done

sha512sum "$target"/hexagonrpcd*-0.4.0-r4.apk
echo "Staged locally built hexagonrpcd sensor userspace packages."
