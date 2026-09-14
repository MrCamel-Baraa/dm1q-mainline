#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
source_package="$project/pmaports/device/testing/hexagonrpcd"
target_package="$base/pmaports/device/testing/hexagonrpcd"

rm -rf "$target_package"
install -d "$target_package"
cp -a "$source_package/." "$target_package/"

"$base/pmbootstrap/pmbootstrap.py" --as-root \
	build --arch aarch64 --force hexagonrpcd

package_dir="$base/pmbootstrap-work/packages/edge/aarch64"
for package in \
	hexagonrpcd-0.4.0-r4.apk \
	hexagonrpcd-systemd-0.4.0-r4.apk \
	hexagonrpcd-udev-0.4.0-r4.apk; do
	test -f "$package_dir/$package"
	printf '%s\n' "$package_dir/$package"
done
