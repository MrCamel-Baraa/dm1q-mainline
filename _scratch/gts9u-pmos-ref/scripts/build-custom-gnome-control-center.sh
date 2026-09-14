#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}
source_package="$project/pmaports/extra-repos/systemd/gnome-control-center"
target_package="$base/pmaports/extra-repos/systemd/gnome-control-center"
package_dir="$base/pmbootstrap-work/packages/systemd-edge/aarch64"
main_apk="$package_dir/gnome-control-center-999950.3-r2.apk"
lang_apk="$package_dir/gnome-control-center-lang-999950.3-r2.apk"

if [ "${FORCE_GCC_BUILD:-0}" != 1 ] &&
	test -f "$main_apk" &&
	test -f "$lang_apk"; then
	echo "Reusing already-built gnome-control-center 999950.3-r2 packages"
	exit 0
fi

rm -rf -- "$target_package"
mkdir -p "${target_package%/*}"
cp -a "$source_package" "$target_package"

"$base/pmbootstrap/pmbootstrap.py" --as-root \
	build --arch aarch64 --force gnome-control-center

test -f "$main_apk"
test -f "$lang_apk"
