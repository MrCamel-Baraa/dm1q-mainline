#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
rootfs_chroot="${ROOTFS_CHROOT_DIR:-$base/pmbootstrap-work/chroot_rootfs_samsung-gts9uwifi}"
initramfs="${INITRAMFS:?Set INITRAMFS to the exported postmarketOS initramfs}"
linux_out="${BUNDLE_OUT_DIR:-$base/out/gts9uwifi-mainline-v0}"
export_out="${BUNDLE_EXPORT_DIR:-$project/artifacts/gts9uwifi-mainline-v0}"

boot_size=100663296
init_boot_size=8388608
vendor_boot_size=100663296
dtbo_size=16777216
vbmeta_size=131072

find_tool() {
	for candidate in "$@"; do
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

mkbootimg=${MKBOOTIMG:-$(find_tool \
	/root/mkbootimg/mkbootimg.py \
	"$base/mkbootimg/mkbootimg.py" \
	"$rootfs_chroot/usr/share/android-tools/mkbootimg/mkbootimg.py")}
mkdtimg=${MKDTIMG:-$(find_tool \
	/root/mkbootimg/mkdtimg.py \
	"$base/mkbootimg/mkdtimg.py" \
	"$rootfs_chroot/usr/bin/mkdtboimg")}
avbtool=${AVBTOOL:-$(find_tool \
	/root/avb/avbtool.py \
	/root/avb/avbtool \
	/root/avbtool/avbtool.py \
	/root/avbtool/avbtool \
	"$rootfs_chroot/usr/bin/avbtool")}

package_zboot="${PACKAGE_ZBOOT:-$rootfs_chroot/boot/vmlinuz}"
package_config="${PACKAGE_CONFIG:-$rootfs_chroot/boot/config}"
dtb="${KERNEL_DTB:-$rootfs_chroot/boot/sm8550-samsung-gts9uwifi.dtb}"
cmdline_file="$project/configs/vendor_boot/cmdline.txt"
bootconfig="$project/configs/vendor_boot/bootconfig.txt"
dtbo_configs="$project/configs/dtbo"
# Samsung X910 ABL cannot apply our mainline base DTB through its downstream
# ufdt path.  The physically validated route since v0.4 is an appended DTB and
# a deliberately non-DT-table dtbo image, which makes ABL use that fallback.
append_dtb="${APPEND_DTB_TO_KERNEL:-1}"
disable_runtime_dtbo="${DISABLE_RUNTIME_DTBO:-1}"
generic_ramdisk_format="${GENERIC_RAMDISK_FORMAT:-lz4-legacy}"
initramfs_overlay="${INITRAMFS_OVERLAY_DIR:-}"

for file in "$mkbootimg" "$mkdtimg" "$avbtool" "$dtb" "$package_zboot" \
	"$package_config" "$initramfs" "$cmdline_file" "$bootconfig"; do
	test -f "$file" || { echo "missing input: $file" >&2; exit 1; }
done
if [ -n "$initramfs_overlay" ]; then
	test -d "$initramfs_overlay" || {
		echo "missing initramfs overlay: $initramfs_overlay" >&2
		exit 1
	}
fi

add_hash_footer() {
	local target=$1
	local partition_name=$2
	local partition_size=$3
	local salt

	salt=$(sha256sum "$target" | cut -d' ' -f1)
	python3 "$avbtool" add_hash_footer \
		--image "$target" \
		--partition_name "$partition_name" \
		--partition_size "$partition_size" \
		--salt "$salt"
}

mkdir -p "$base/build" "$linux_out" "$export_out"
tmp=$(mktemp -d "$base/build/boot-bundle.XXXXXX")
cleanup() {
	case "$tmp" in
		"$base"/build/boot-bundle.*) rm -rf -- "$tmp" ;;
	esac
}
trap cleanup EXIT

image="${KERNEL_IMAGE:-$tmp/Image.gz}"
if [ -z "${KERNEL_IMAGE:-}" ]; then
	python3 "$project/scripts/extract-zboot-payload.py" \
		"$package_zboot" "$image"
else
	test -f "$image" || { echo "missing input: $image" >&2; exit 1; }
fi

cmdline=$(tr '\n' ' ' < "$cmdline_file" | sed 's/[[:space:]]*$//')

# Samsung's X910 ABL concatenates the generic init_boot ramdisk with the
# vendor_boot fragments.  Stock X910XXS5CYG1 uses the legacy LZ4 stream format
# (magic 02 21 4c 18) for both parts.  Feeding ABL a gzip generic ramdisk is a
# valid Android v4 image, but the resulting initrd is rejected by Linux before
# /init with "invalid magic at start of compressed archive".  Recompress the
# same pmOS CPIO to the stock format; this changes no initramfs contents.
case "$generic_ramdisk_format" in
	lz4-legacy)
		gzip -t "$initramfs"
		generic_ramdisk="$tmp/initramfs.lz4"
		gzip -dc "$initramfs" | lz4 -l -12 - "$generic_ramdisk" >/dev/null
		;;
	input)
		generic_ramdisk="$initramfs"
		;;
	*)
		echo "unsupported GENERIC_RAMDISK_FORMAT: $generic_ramdisk_format" >&2
		exit 1
		;;
esac

boot_kernel="$image"
if [ "$append_dtb" = 1 ]; then
	boot_kernel="$tmp/Image.gz-dtb"
	cat "$image" "$dtb" > "$boot_kernel"
fi

# Android boot header v4: kernel (plus optional raw appended DTB) only.  X910
# ABL obtains the generic ramdisk from init_boot and vendor cmdline from
# vendor_boot.
python3 "$mkbootimg" \
	--kernel "$boot_kernel" \
	--cmdline '' \
	--header_version 4 \
	--os_version 13 \
	--os_patch_level 2025-07 \
	-o "$linux_out/boot.img"
add_hash_footer "$linux_out/boot.img" boot "$boot_size"

python3 "$mkbootimg" \
	--ramdisk "$generic_ramdisk" \
	--header_version 4 \
	-o "$linux_out/init_boot.img"
add_hash_footer "$linux_out/init_boot.img" init_boot "$init_boot_size"

mkdir -p "$tmp/empty-vendor-ramdisk"
if [ -n "$initramfs_overlay" ]; then
	# ABL concatenates this platform fragment after the generic initramfs.
	# Firmware placed here is therefore available to built-in drivers during
	# their first probe, while init_boot itself remains unchanged.
	cp -a "$initramfs_overlay/." "$tmp/empty-vendor-ramdisk/"
fi
touch -d '@0' "$tmp/empty-vendor-ramdisk"
(
	cd "$tmp/empty-vendor-ramdisk"
	find . -print0 | cpio --reproducible --null -o --format=newc 2>/dev/null
) | lz4 -l -12 - "$tmp/vendor_ramdisk.lz4" >/dev/null

python3 "$mkbootimg" \
	--ramdisk_type platform \
	--ramdisk_name '' \
	--vendor_ramdisk_fragment "$tmp/vendor_ramdisk.lz4" \
	--dtb "$dtb" \
	--vendor_cmdline "$cmdline" \
	--header_version 4 \
	--vendor_boot "$linux_out/vendor_boot.img" \
	--base 0x80000000 \
	--kernel_offset 0x8000 \
	--ramdisk_offset 0x02000000 \
	--tags_offset 0x01e00000 \
	--pagesize 4096 \
	--dtb_offset 0x1f00000 \
	--vendor_bootconfig "$bootconfig"
add_hash_footer "$linux_out/vendor_boot.img" vendor_boot "$vendor_boot_size"

if [ "$disable_runtime_dtbo" = 1 ]; then
	# Qualcomm ABL falls back to an appended kernel DTB when the dtbo partition
	# is not an Android DT table.  The zero prefix is deliberate; AVB still
	# authenticates the full partition-sized image below.
	rm -f "$linux_out/dtbo.img"
	truncate -s 4096 "$linux_out/dtbo.img"
else
	dtc -@ -I dts -O dtb \
		-o "$tmp/board00.dtbo" "$dtbo_configs/gts9uwifi-board00-noop.dts"
	dtc -@ -I dts -O dtb \
		-o "$tmp/board03.dtbo" "$dtbo_configs/gts9uwifi-board03-noop.dts"
	python3 "$mkdtimg" create "$linux_out/dtbo.img" \
		--page_size=4096 "$tmp/board00.dtbo" "$tmp/board03.dtbo"
fi
add_hash_footer "$linux_out/dtbo.img" dtbo "$dtbo_size"

python3 "$avbtool" make_vbmeta_image \
	--output "$linux_out/vbmeta.img" \
	--flags 2 \
	--padding_size "$vbmeta_size"

for spec in \
	"boot.img:$boot_size" \
	"init_boot.img:$init_boot_size" \
	"vendor_boot.img:$vendor_boot_size" \
	"dtbo.img:$dtbo_size" \
	"vbmeta.img:$vbmeta_size"; do
	name=${spec%%:*}
	expected=${spec##*:}
	actual=$(stat -c %s "$linux_out/$name")
	[ "$actual" -eq "$expected" ] || {
		echo "$name: expected $expected bytes, got $actual" >&2
		exit 1
	}
done

(
	cd "$linux_out"
	sha256sum *.img > SHA256SUMS
)
{
	printf 'kernel_source=%s\n' "$(git -C "$base/linux-mainline" rev-parse HEAD)"
	printf 'kernel_release=%s\n' "$(cat "$rootfs_chroot/usr/share/kernel/samsung-gts9uwifi-mainline/kernel.release")"
	printf 'kernel_zboot_sha256=%s\n' "$(sha256sum "$package_zboot" | cut -d' ' -f1)"
	printf 'kernel_payload_sha256=%s\n' "$(sha256sum "$image" | cut -d' ' -f1)"
	printf 'boot_kernel_sha256=%s\n' "$(sha256sum "$boot_kernel" | cut -d' ' -f1)"
	printf 'kernel_config_sha256=%s\n' "$(sha256sum "$package_config" | cut -d' ' -f1)"
	printf 'kernel_dtb_sha256=%s\n' "$(sha256sum "$dtb" | cut -d' ' -f1)"
	printf 'append_dtb_to_kernel=%s\n' "$append_dtb"
	printf 'disable_runtime_dtbo=%s\n' "$disable_runtime_dtbo"
	printf 'initramfs_source_sha256=%s\n' "$(sha256sum "$initramfs" | cut -d' ' -f1)"
	printf 'initramfs_packaging=%s\n' "$generic_ramdisk_format"
	printf 'initramfs_packaged_sha256=%s\n' "$(sha256sum "$generic_ramdisk" | cut -d' ' -f1)"
} > "$linux_out/BUILD-METADATA.txt"

install -m 0644 "$linux_out"/*.img "$export_out/"
install -m 0644 "$linux_out/SHA256SUMS" "$linux_out/BUILD-METADATA.txt" \
	"$export_out/"

cat "$linux_out/SHA256SUMS"
