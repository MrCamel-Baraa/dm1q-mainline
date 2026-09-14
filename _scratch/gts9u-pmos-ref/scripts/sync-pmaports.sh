#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
target="$base/pmaports"

test -d "$target/.git"
test -d "$project/pmaports/device/testing"

for package in \
	device-samsung-gts9uwifi \
	firmware-samsung-gts9uwifi \
	hexagonrpcd \
	linux-samsung-gts9uwifi-mainline; do
	mkdir -p "$target/device/testing/$package"
	cp -a "$project/pmaports/device/testing/$package/." \
		"$target/device/testing/$package/"
done

mkdir -p "$target/extra-repos/systemd/mutter"
cp -a "$project/pmaports/extra-repos/systemd/mutter/." \
	"$target/extra-repos/systemd/mutter/"
mkdir -p "$target/extra-repos/systemd/gnome-control-center"
cp -a "$project/pmaports/extra-repos/systemd/gnome-control-center/." \
	"$target/extra-repos/systemd/gnome-control-center/"
mkdir -p "$target/extra-repos/systemd/iio-sensor-proxy"
cp -a "$project/pmaports/extra-repos/systemd/iio-sensor-proxy/." \
	"$target/extra-repos/systemd/iio-sensor-proxy/"

git -C "$target" status --short -- \
	device/testing/device-samsung-gts9uwifi \
	device/testing/firmware-samsung-gts9uwifi \
	device/testing/hexagonrpcd \
	device/testing/linux-samsung-gts9uwifi-mainline \
	extra-repos/systemd/iio-sensor-proxy \
	extra-repos/systemd/gnome-control-center \
	extra-repos/systemd/mutter
