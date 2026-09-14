#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
bundle="${BUNDLE_DIR:-$base/out/gts9uwifi-mainline-v0}"
rootfs_export="${ROOTFS_EXPORT_DIR:-$base/out/rootfs-gts9uwifi}"
rootfs_chroot="${ROOTFS_CHROOT_DIR:-$base/pmbootstrap-work/chroot_rootfs_samsung-gts9uwifi}"
package_zboot="${PACKAGE_ZBOOT:-$rootfs_chroot/boot/vmlinuz}"
package_config="${PACKAGE_CONFIG:-$rootfs_chroot/boot/config}"
package_dtb="${KERNEL_DTB:-$rootfs_chroot/boot/sm8550-samsung-gts9uwifi.dtb}"
kernel_image="${KERNEL_IMAGE:-}"
tools_root="$base/pmbootstrap-work/chroot_rootfs_samsung-gts9uwifi/usr"
unpack="${UNPACK_BOOTIMG:-$tools_root/bin/unpack_bootimg}"
avbtool="${AVBTOOL:-$tools_root/bin/avbtool}"
tmp=$(mktemp -d "$base/build/validate-bundle.XXXXXX")
append_dtb="${APPEND_DTB_TO_KERNEL:-0}"
disable_runtime_dtbo="${DISABLE_RUNTIME_DTBO:-0}"

cleanup() {
	case "$tmp" in
		"$base"/build/validate-bundle.*) rm -rf -- "$tmp" ;;
	esac
}
trap cleanup EXIT

if [ -n "$kernel_image" ]; then
	cp "$kernel_image" "$tmp/package-Image.gz"
else
	python3 "$project/scripts/extract-zboot-payload.py" \
		"$package_zboot" "$tmp/package-Image.gz"
fi

gzip -dc "$tmp/package-Image.gz" > "$tmp/package-Image"
grep -aFq 'unsupported event layout: header %u point %u' \
	"$tmp/package-Image"
grep -aFq 'forcing 16-byte Samsung events for firmware PID 6936' \
	"$tmp/package-Image"
grep -aFq 'applied %d register overrides' "$tmp/package-Image"

for symbol in \
	CONFIG_DRM_SIMPLEDRM \
	CONFIG_MMC \
	CONFIG_MMC_SDHCI \
	CONFIG_MMC_SDHCI_MSM \
	CONFIG_EXT4_FS \
	CONFIG_USB_GADGET \
	CONFIG_USB_CONFIGFS \
	CONFIG_USB_CONFIGFS_NCM \
	CONFIG_SERIAL_QCOM_GENI \
	CONFIG_QCOM_GPI_DMA \
	CONFIG_PHY_NXP_PTN3222 \
	CONFIG_TOUCHSCREEN_GOODIX_BERLIN_CORE \
	CONFIG_INPUT_EVDEV \
	CONFIG_INPUT_UINPUT \
	CONFIG_UHID \
	CONFIG_SAMSUNG_GTS9UWIFI_SEC_LOG \
	CONFIG_PSTORE \
	CONFIG_PSTORE_RAM; do
	grep -qx "$symbol=y" "$package_config" || {
		echo "$symbol must be built-in" >&2
		exit 1
	}
done

release=$(cat "$rootfs_chroot/usr/share/kernel/samsung-gts9uwifi-mainline/kernel.release")
test -d "$rootfs_chroot/usr/lib/modules/$release"

for spec in \
	'boot.img:100663296' \
	'init_boot.img:8388608' \
	'vendor_boot.img:100663296' \
	'dtbo.img:16777216' \
	'vbmeta.img:131072'; do
	name=${spec%%:*}
	expected=${spec##*:}
	test "$(stat -c %s "$bundle/$name")" -eq "$expected"
done

(
	cd "$bundle"
	sha256sum -c SHA256SUMS
)

for image in boot init_boot vendor_boot; do
	mkdir -p "$tmp/$image"
	python3 "$unpack" --boot_img "$bundle/$image.img" \
		--out "$tmp/$image" --format=info > "$tmp/$image.info"
	grep -q 'header version: 4' "$tmp/$image.info"
done

if [ "$append_dtb" = 1 ]; then
	package_size=$(stat -c %s "$tmp/package-Image.gz")
	dtb_size=$(stat -c %s "$package_dtb")
	test "$(stat -c %s "$tmp/boot/kernel")" -eq "$((package_size + dtb_size))"
	cmp <(head -c "$package_size" "$tmp/boot/kernel") "$tmp/package-Image.gz"
	cmp <(tail -c "$dtb_size" "$tmp/boot/kernel") "$package_dtb"
else
	cmp "$tmp/boot/kernel" "$tmp/package-Image.gz"
fi
test ! -s "$tmp/boot/ramdisk"
test ! -s "$tmp/init_boot/kernel"
test "$(xxd -p -l 4 "$tmp/init_boot/ramdisk")" = '02214c18'
gzip -t "$rootfs_export/initramfs"
lz4 -t "$tmp/init_boot/ramdisk" >/dev/null
cmp <(lz4 -dc "$tmp/init_boot/ramdisk" 2>/dev/null) \
	<(gzip -dc "$rootfs_export/initramfs")
cmp "$tmp/vendor_boot/dtb" "$package_dtb"
cmp "$tmp/vendor_boot/bootconfig" "$project/configs/vendor_boot/bootconfig.txt"
test "$(xxd -p -l 4 "$tmp/vendor_boot/vendor_ramdisk00")" = '02214c18'
lz4 -t "$tmp/vendor_boot/vendor_ramdisk00" >/dev/null

# Samsung ABL uses these downstream root properties before it hands control to
# Linux.  Without them it reports "No match found for Soc Dtb type" and enters
# Odin instead of booting the kernel.
test "$(fdtget -t s "$tmp/vendor_boot/dtb" / compatible)" = \
	'qcom,kalama-mtp qcom,kalama qcom,mtp samsung,gts9uwifi qcom,sm8550'
test "$(fdtget -t x "$tmp/vendor_boot/dtb" / qcom,msm-id)" = \
	'218 20000 207 20000 207 10000 218 10000'
test "$(fdtget -t x "$tmp/vendor_boot/dtb" / qcom,board-id)" = '10008 3'
fdtget -l "$tmp/vendor_boot/dtb" / | grep -qx '__symbols__'

# The stock overlay normally contributes these X910-only protected ranges.
# With runtime DTBO disabled they must already exist in the appended base DTB,
# otherwise Linux can allocate secure memory and TrustZone resets the SoC.
check_reserved() {
	local node=$1 expected=$2
	test "$(fdtget -t x "$tmp/vendor_boot/dtb" "/reserved-memory/$node" reg)" = "$expected"
}
check_reserved 'kaslr@b01ff000' '0 b01ff000 0 1000'
check_reserved 'uh-heap@b0200000' '0 b0200000 0 40000'
check_reserved 'uh-guest@b1000000' '0 b1000000 0 3a00000'
check_reserved 'chipinfo@81cf4000' '0 81cf4000 0 1000'
check_reserved 'sec-xbl-ramdump@a7d00000' '0 a7d00000 0 300000'
check_reserved 'llcc-lpi@ff800000' '0 ff800000 0 600000'
check_reserved 'sec-debug-pool@880100000' '8 80100000 0 ff000'
check_reserved 'sec-reset-info@8801ff000' '8 801ff000 0 1000'
check_reserved 'sec-log@880200000' '8 80200000 0 200000'
check_reserved 'sec-debug-bl@880400000' '8 80400000 0 500000'
check_reserved 'sec-pmsg@880900000' '8 80900000 0 200000'
check_reserved 'google-debug-kinfo@880b00000' '8 80b00000 0 1000'
check_reserved 'hdm@880b01000' '8 80b01000 0 1000'
check_reserved 'sec-qcom-rdx@880c00000' '8 80c00000 0 ad00000'
check_reserved 'hwfence-shbuf-region@e6440000' '0 e6440000 0 2dd000'
test "$(fdtget -t s "$tmp/vendor_boot/dtb" /sec-kernel-log compatible)" = \
	'samsung,gts9uwifi-sec-kernel-log'
test "$(fdtget -t s "$tmp/vendor_boot/dtb" \
	/soc@0/interconnect@7e40000 status 2>/dev/null || \
	fdtget -t s "$tmp/vendor_boot/dtb" /soc/interconnect@7e40000 status)" = \
	'disabled'

# The first graphical boot proved that the X910 touch and USB buses must not
# depend on late modules. Both relevant GENI I2C controllers use GPI DMA, and
# the eUSB2 HS PHY is physically chained through an NXP PTN3222 on I2C6.
gpi_dma='/soc@0/dma-controller@a00000'
i2c4='/soc@0/geniqup@ac0000/i2c@a90000'
i2c6='/soc@0/geniqup@ac0000/i2c@a98000'
repeater="$i2c6/redriver@4f"
hsphy='/soc@0/phy@88e3000'
usb='/soc@0/usb@a600000'
touchscreen="$i2c4/touchscreen@5d"
repeater_reset='/soc@0/spmi@c400000/pmic@3/gpio@8800/eusb2-reset-state'

for node in "$gpi_dma" "$i2c4" "$i2c6" "$hsphy" "$usb"; do
	test "$(fdtget -t s "$tmp/vendor_boot/dtb" "$node" status)" = 'okay'
done
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$i2c4" clock-frequency)" = '400000'
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$i2c6" clock-frequency)" = '400000'
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$touchscreen" touchscreen-size-x)" = '1848'
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$touchscreen" touchscreen-size-y)" = '2960'
fdtget "$tmp/vendor_boot/dtb" "$touchscreen" touchscreen-inverted-x >/dev/null
fdtget "$tmp/vendor_boot/dtb" "$touchscreen" touchscreen-swapped-x-y >/dev/null
test "$(fdtget -t s "$tmp/vendor_boot/dtb" "$repeater" compatible)" = \
	'nxp,ptn3222'
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$repeater" '#phy-cells')" = '0'
reset_spec=" $(fdtget -t i "$tmp/vendor_boot/dtb" "$repeater" reset-gpios) "
case "$reset_spec" in
	*' 4 1 ') ;;
	*) echo "PTN3222 reset must be PM8550VS-D GPIO4 active-low" >&2; exit 1 ;;
esac
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$repeater_reset" power-source)" = '1'
test "$(fdtget -t i "$tmp/vendor_boot/dtb" "$repeater_reset" qcom,drive-strength)" = '2'
test "$(fdtget -t x "$tmp/vendor_boot/dtb" "$repeater" qcom,param-override-seq)" = \
	'20 6 21 7 63 8 1 a'
for property in input-enable output-enable drive-push-pull bias-disable; do
	fdtget "$tmp/vendor_boot/dtb" "$repeater_reset" "$property" >/dev/null
done
test "$(fdtget -t x "$tmp/vendor_boot/dtb" "$hsphy" phys)" = \
	"$(fdtget -t x "$tmp/vendor_boot/dtb" "$repeater" phandle)"
test "$(fdtget -t s "$tmp/vendor_boot/dtb" "$usb" dr_mode)" = 'peripheral'
test "$(fdtget -t s "$tmp/vendor_boot/dtb" "$usb" maximum-speed)" = 'high-speed'
fdtget "$tmp/vendor_boot/dtb" "$usb" qcom,select-utmi-as-pipe-clk >/dev/null

grep -q '^page size: 0x00001000$' "$tmp/vendor_boot.info"
grep -q '^kernel load address: 0x80008000$' "$tmp/vendor_boot.info"
grep -q '^ramdisk load address: 0x82000000$' "$tmp/vendor_boot.info"
grep -q '^kernel tags load address: 0x81e00000$' "$tmp/vendor_boot.info"
grep -q '^dtb address: 0x0000000081f00000$' "$tmp/vendor_boot.info"

for image in boot init_boot vendor_boot dtbo; do
	python3 "$avbtool" verify_image --image "$bundle/$image.img"
	python3 "$avbtool" info_image --image "$bundle/$image.img" \
		> "$tmp/$image.avb"
	grep -q "Partition Name:        ${image}" "$tmp/$image.avb"
done
python3 "$avbtool" info_image --image "$bundle/vbmeta.img" > "$tmp/vbmeta.avb"
grep -q '^Flags:                    2$' "$tmp/vbmeta.avb"
grep -q '^Algorithm:                NONE$' "$tmp/vbmeta.avb"

if [ "$disable_runtime_dtbo" = 1 ]; then
	test "$(od -An -N4 -tx1 "$bundle/dtbo.img" | tr -d ' \n')" = '00000000'
else
	python3 "$project/scripts/inspect-android-dtbo.py" "$bundle/dtbo.img" \
		> "$tmp/dtbo.txt"
	grep -q '^total=.* entries=2 .* page=4096 version=0$' "$tmp/dtbo.txt"
	grep -q "qcom,board-id = <0x10008 0x0>" "$tmp/dtbo.txt"
	grep -q "qcom,board-id = <0x10008 0x3>" "$tmp/dtbo.txt"
	grep -q 'dtbo-hw_rev_end = <0x20>' "$tmp/dtbo.txt"
fi

echo 'Android v4 bundle validated byte-for-byte.'
cat "$bundle/SHA256SUMS"
