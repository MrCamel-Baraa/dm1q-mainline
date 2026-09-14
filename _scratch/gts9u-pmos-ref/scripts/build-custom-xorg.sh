#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
source_package="$project/pmaports/extra-repos/systemd/xorg-server"
target_package="$base/pmaports/extra-repos/systemd/xorg-server"

install -d "$target_package"
install -m 0644 "$source_package/APKBUILD" "$target_package/APKBUILD"
install -m 0644 "$source_package/enable-software-prime-sink.patch" \
	"$target_package/enable-software-prime-sink.patch"

"$base/pmbootstrap/pmbootstrap.py" --as-root \
	build --arch aarch64 --force xorg-server

apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/xorg-server-999921.1.23-r10.apk"
test -f "$apk"
printf '%s\n' "$apk"
