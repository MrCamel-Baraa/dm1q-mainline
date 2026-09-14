#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
source_package="$project/pmaports/extra-repos/systemd/mutter"
target_package="$base/pmaports/extra-repos/systemd/mutter"
package_dir="$base/pmbootstrap-work/packages/systemd-edge/aarch64"
main_apk="$package_dir/mutter-999950.2-r6.apk"

if [ "${FORCE_MUTTER_BUILD:-0}" != 1 ] &&
	test -f "$main_apk" &&
	test -f "$package_dir/mutter-lang-999950.2-r6.apk" &&
	test -f "$package_dir/mutter-schemas-999950.2-r6.apk" &&
	test -f "$package_dir/mutter-udev-999950.2-r6.apk"; then
	echo "Reusing already-built mutter 999950.2-r6 packages"
	exit 0
fi

install -d "$target_package"
install -m 0644 "$source_package/APKBUILD" "$target_package/APKBUILD"
for patch in \
	fixudev-req.patch \
	pcversion.patch \
	fix-orientation-inhibit-underflow.patch \
	keep-slate-orientation-with-pointer.patch; do
	install -m 0644 "$source_package/$patch" "$target_package/$patch"
done

"$base/pmbootstrap/pmbootstrap.py" --as-root \
	build --arch aarch64 --force mutter

test -f "$main_apk"
printf '%s\n' "$main_apk"
