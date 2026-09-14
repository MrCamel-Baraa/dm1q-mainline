#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
source_package="$project/pmaports/extra-repos/systemd/iio-sensor-proxy"
target_package="$base/pmaports/extra-repos/systemd/iio-sensor-proxy"
apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/iio-sensor-proxy-3.9-r3.apk"

if [ "${FORCE_IIO_SENSOR_PROXY_BUILD:-0}" != 1 ] && test -f "$apk"; then
	echo "Reusing already-built iio-sensor-proxy 3.9-r3 package"
	exit 0
fi

install -d "$target_package"
install -m 0644 "$source_package/APKBUILD" "$target_package/APKBUILD"
install -m 0755 "$source_package/iio-sensor-proxy.initd" \
	"$target_package/iio-sensor-proxy.initd"
install -m 0644 "$source_package/notify-slow-sensor-discovery.patch" \
	"$target_package/notify-slow-sensor-discovery.patch"

"$base/pmbootstrap/pmbootstrap.py" --as-root \
	build --arch aarch64 --force iio-sensor-proxy

test -f "$apk"
printf '%s\n' "$apk"
