#!/bin/bash
set -euo pipefail

base=${PMOS_WORKDIR:-/root/pmos-gts9u}
project=${PROJECT_MNT:-'/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS'}
version=${WIFI_BUILD_VERSION:-0.42}
kernel="$base/out/kernel-gts9uwifi-v${version/./}"
bundle="$base/out/gts9uwifi-mainline-v$version"
overlay="$base/out/rootfs-overlay-v$version"
initramfs_overlay="$base/out/initramfs-overlay-v$version"
artifact=${ARTIFACT:-"$project/artifacts/postmarketos-edge-xfce-mainline-v$version-wcn7850-pcie-cold-reset-sm-x910-twrp.zip"}
firmware="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"
sensor_packages="$base/cache/sensor-userspace"
xorg_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/xorg-server-999921.1.23-r10.apk"
iio_sensor_proxy_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/iio-sensor-proxy-3.9-r3.apk"
iio_sensor_proxy_systemd_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/iio-sensor-proxy-systemd-3.9-r3.apk"
iio_sensor_proxy_udev_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/iio-sensor-proxy-udev-3.9-r3.apk"
mutter_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/mutter-999950.2-r6.apk"
mutter_lang_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/mutter-lang-999950.2-r6.apk"
mutter_schemas_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/mutter-schemas-999950.2-r6.apk"
mutter_udev_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/mutter-udev-999950.2-r6.apk"
gnome_control_center_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/gnome-control-center-999950.3-r2.apk"
gnome_control_center_lang_apk="$base/pmbootstrap-work/packages/systemd-edge/aarch64/gnome-control-center-lang-999950.3-r2.apk"

if [ "${REUSE_BUILD_OUTPUTS:-0}" = 1 ]; then
	# Packaging-only recovery after a late overlay/bundle failure.  Never use
	# this unless the same version's kernel and custom Xorg were already built.
	test -f "$kernel/Image.gz"
	test -f "$kernel/sm8550-samsung-gts9uwifi.dtb"
	test -d "$kernel/modules-root"
	test -f "$xorg_apk"
	test -f "$iio_sensor_proxy_apk"
	test -f "$iio_sensor_proxy_systemd_apk"
	test -f "$iio_sensor_proxy_udev_apk"
	test -f "$mutter_apk"
	test -f "$mutter_lang_apk"
	test -f "$mutter_schemas_apk"
	test -f "$mutter_udev_apk"
	test -f "$gnome_control_center_apk"
	test -f "$gnome_control_center_lang_apk"
else
	bash "$project/scripts/stage-gpu-firmware.sh"
	bash "$project/scripts/stage-stock-audio-firmware.sh"
	bash "$project/scripts/stage-stock-sensor-hexagonfs.sh"
	bash "$project/scripts/stage-sensor-userspace.sh"
	bash "$project/scripts/stage-audioreach-topology.sh"
	if [ "${SKIP_XORG_BUILD:-0}" = 1 ]; then
		# GNOME/Wayland does not consume this legacy reverse-PRIME package.
		# Sensor-only builds may reuse the already validated r10 APK when an
		# unrelated edge toolchain transition prevents rebuilding Xorg.
		test -f "$xorg_apk"
	else
		bash "$project/scripts/build-custom-xorg.sh"
	fi
	bash "$project/scripts/build-custom-iio-sensor-proxy.sh"
	bash "$project/scripts/build-custom-mutter.sh"
	bash "$project/scripts/build-custom-gnome-control-center.sh"

	KERNEL_OUT_DIR="$kernel" BUILD_WIFI_MODULES=1 \
		bash "$project/scripts/build-mainline-kernel.sh"
fi

case "$overlay" in
	"$base"/out/rootfs-overlay-v*) rm -rf -- "$overlay" ;;
	*) echo "unsafe overlay path: $overlay" >&2; exit 1 ;;
esac
case "$initramfs_overlay" in
	"$base"/out/initramfs-overlay-v*) rm -rf -- "$initramfs_overlay" ;;
	*) echo "unsafe initramfs overlay path: $initramfs_overlay" >&2; exit 1 ;;
esac
mkdir -p \
	"$overlay/etc/modules-load.d" \
	"$overlay/etc/modprobe.d" \
	"$overlay/etc/ssh/sshd_config.d" \
	"$overlay/etc/X11/xorg.conf.d" \
	"$overlay/etc/lightdm/lightdm.conf.d" \
	"$overlay/etc/xdg/autostart" \
	"$overlay/etc/systemd/system/lightdm.service.d" \
	"$overlay/etc/systemd/system/bluetooth.service.d" \
	"$overlay/etc/systemd/system/pd-mapper.service.d" \
	"$overlay/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service.d" \
	"$overlay/etc/systemd/logind.conf.d" \
	"$overlay/etc/systemd/journald.conf.d" \
	"$overlay/etc/xdg/fastfetch" \
	"$overlay/usr/lib/udev/rules.d" \
	"$overlay/usr/share/alsa/ucm2/conf.d/sm8550" \
	"$overlay/usr/share/alsa/ucm2/Qualcomm/sm8550/GTS9U" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0" \
	"$overlay/usr/lib/firmware/qca" \
	"$overlay/usr/lib/firmware/qcom" \
	"$overlay/usr/lib/firmware/qcom/sm8550" \
	"$overlay/usr/libexec" \
	"$overlay/usr/share/glib-2.0/schemas" \
	"$overlay/usr/lib/systemd/system" \
	"$overlay/usr/lib/systemd/system-sleep" \
	"$overlay/usr/lib/systemd/system/graphical.target.wants" \
	"$overlay/usr/lib/systemd/system/multi-user.target.wants" \
	"$overlay/usr/share/gts9uwifi/packages" \
	"$overlay/usr/share/qcom/sm8550/Samsung/gts9uwifi" \
	"$overlay/usr/share/X11/xorg.conf.d" \
	"$initramfs_overlay/usr/lib/firmware/qca"

cp -a "$kernel/modules-root/." "$overlay/"
install -m 0644 "$project/configs/wifi/ath12k.conf" \
	"$overlay/etc/modules-load.d/ath12k.conf"
# Adreno 740 GPU firmware under /lib/firmware/qcom (msm is built-in).
for f in a740_zap.mdt a740_zap.b00 a740_zap.b01 a740_zap.b02 a740_sqe.fw gmu_gen70200.bin; do
	install -m 0644 "$firmware/$f" "$overlay/usr/lib/firmware/qcom/$f"
done
# ADSP (audio DSP) boot image under qcom/sm8550 — Samsung's own signed adsp.mdt
# + segments (matches DTS firmware-name = "qcom/sm8550/adsp.mdt").  The mainline
# qcom_q6v5_pas mdt loader reads adsp.mdt and pulls each adsp.bNN segment.
for f in "$firmware"/adsp.mdt "$firmware"/adsp.b* \
	 "$firmware"/adsp_dtb.mdt "$firmware"/adsp_dtb.b*; do
	install -m 0644 "$f" "$overlay/usr/lib/firmware/qcom/sm8550/${f##*/}"
done
# X910-specific CS35L45 Halo DSP speaker-protection firmware. The codec probes
# without these files, but playback cannot safely enable its protected path.
for f in \
	cs35l45-dsp1-spk-prot.wmfw \
	cs35l45-dsp1-spk-prot.bin \
	cs35l45-dsp1-spk-prot-calib.bin; do
	install -m 0644 "$firmware/$f" "$overlay/usr/lib/firmware/$f"
done
# AudioReach refuses to register its PCM graphs without this topology. The
# filename must exactly match qcom/<card driver>/<DTS model>-tplg.bin.
install -m 0644 "$firmware/Samsung-Galaxy-Tab-S9-Ultra-tplg.bin" \
	"$overlay/usr/lib/firmware/qcom/sm8550/Samsung-Galaxy-Tab-S9-Ultra-tplg.bin"
# Protection-domain maps consumed by pd-mapper.  It locates them by reading
# /sys/class/remoteproc/*/firmware and scanning that firmware's own directory,
# so they must sit beside adsp.mdt; adspua.jsn carries the avs/audio mapping the
# q6apm/q6prm nodes block on.
for f in adspr.jsn adsps.jsn adspua.jsn cdspr.jsn; do
	install -m 0644 "$firmware/$f" \
		"$overlay/usr/lib/firmware/qcom/sm8550/$f"
done
# Sensor HexagonFS: board-specific JSON configuration and a deterministic
# registry generated from Samsung's MTP/SoC-519 selectors.  It intentionally
# contains no copy of writable persist or per-device calibration.
tar -xzf "$firmware/sensor-hexagonfs.tar.gz" \
	-C "$overlay/usr/share/qcom/sm8550/Samsung/gts9uwifi" \
	--strip-components=1
# The current microSD image predates hexagonrpcd. Bundle the signed Alpine APKs
# and install them locally on first boot; freshly generated rootfs images also
# pull these through the device package dependencies.
for package in "$sensor_packages"/hexagonrpcd-*.apk; do
	install -m 0644 "$package" \
		"$overlay/usr/share/gts9uwifi/packages/${package##*/}"
done
install -m 0644 "$iio_sensor_proxy_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${iio_sensor_proxy_apk##*/}"
install -m 0644 "$iio_sensor_proxy_systemd_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${iio_sensor_proxy_systemd_apk##*/}"
install -m 0644 "$iio_sensor_proxy_udev_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${iio_sensor_proxy_udev_apk##*/}"
install -m 0644 "$mutter_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${mutter_apk##*/}"
install -m 0644 "$mutter_lang_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${mutter_lang_apk##*/}"
install -m 0644 "$mutter_schemas_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${mutter_schemas_apk##*/}"
install -m 0644 "$mutter_udev_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${mutter_udev_apk##*/}"
install -m 0644 "$gnome_control_center_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${gnome_control_center_apk##*/}"
install -m 0644 "$gnome_control_center_lang_apk" \
	"$overlay/usr/share/gts9uwifi/packages/${gnome_control_center_lang_apk##*/}"
install -m 0755 "$project/configs/sensors/gts9uwifi-install-sensor-packages" \
	"$overlay/usr/libexec/gts9uwifi-install-sensor-packages"
install -m 0644 "$project/configs/sensors/gts9uwifi-install-sensor-packages.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-install-sensor-packages.service"
ln -sf ../gts9uwifi-install-sensor-packages.service \
	"$overlay/usr/lib/systemd/system/multi-user.target.wants/gts9uwifi-install-sensor-packages.service"
install -m 0644 "$project/configs/sensors/10-gts9uwifi-hexagonfs.conf" \
	"$overlay/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-gts9uwifi-hexagonfs.conf"
install -m 0644 "$project/configs/sensors/10-gts9uwifi-lid.conf" \
	"$overlay/etc/systemd/logind.conf.d/10-gts9uwifi-lid.conf"
install -m 0644 "$project/configs/sensors/61-gts9uwifi-sensor-mount-matrix.rules" \
	"$overlay/usr/lib/udev/rules.d/61-gts9uwifi-sensor-mount-matrix.rules"
install -m 0755 "$project/configs/sensors/gts9uwifi-wait-sensor-proxy" \
	"$overlay/usr/libexec/gts9uwifi-wait-sensor-proxy"
install -m 0644 "$project/configs/sensors/gts9uwifi-wait-sensor-proxy.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-wait-sensor-proxy.service"
ln -sf ../gts9uwifi-wait-sensor-proxy.service \
	"$overlay/usr/lib/systemd/system/multi-user.target.wants/gts9uwifi-wait-sensor-proxy.service"
install -m 0755 "$project/configs/sensors/gts9uwifi-sensors-resume" \
	"$overlay/usr/libexec/gts9uwifi-sensors-resume"
install -m 0755 "$project/configs/sensors/gts9uwifi-sensors-resume-system-sleep" \
	"$overlay/usr/lib/systemd/system-sleep/gts9uwifi-sensors-resume"
install -m 0755 "$project/configs/display-native/gts9uwifi-display-wake" \
	"$overlay/usr/libexec/gts9uwifi-display-wake"
install -m 0644 "$project/configs/display-native/gts9uwifi-display-wake.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-display-wake.service"
install -m 0755 "$project/configs/display-native/gts9uwifi-display-wake-system-sleep" \
	"$overlay/usr/lib/systemd/system-sleep/gts9uwifi-display-wake"
install -m 0755 "$project/configs/usb/gts9uwifi-usb-host-resume" \
	"$overlay/usr/libexec/gts9uwifi-usb-host-resume"
install -m 0755 "$project/configs/usb/gts9uwifi-usb-host-resume-system-sleep" \
	"$overlay/usr/lib/systemd/system-sleep/gts9uwifi-usb-host-resume"
install -m 0644 "$project/configs/usb/99-gts9uwifi-logitech-lightspeed.rules" \
	"$overlay/usr/lib/udev/rules.d/99-gts9uwifi-logitech-lightspeed.rules"
install -m 0644 "$project/configs/sensors/99_gts9uwifi-sensors.gschema.override" \
	"$overlay/usr/share/glib-2.0/schemas/99_gts9uwifi-sensors.gschema.override"
install -m 0644 "$project/configs/sensors/gts9uwifi-compile-sensor-schemas.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-compile-sensor-schemas.service"
ln -sf ../gts9uwifi-compile-sensor-schemas.service \
	"$overlay/usr/lib/systemd/system/multi-user.target.wants/gts9uwifi-compile-sensor-schemas.service"
install -m 0644 "$project/configs/development-ssh/00-gts9uwifi-development-key.conf" \
	"$overlay/etc/ssh/sshd_config.d/00-gts9uwifi-development-key.conf"
install -m 0644 "$project/configs/development-ssh/phablet.authorized_keys" \
	"$overlay/etc/ssh/gts9uwifi_authorized_keys"
install -m 0755 "$project/configs/bluetooth/gts9uwifi-bluetooth-address" \
	"$overlay/usr/libexec/gts9uwifi-bluetooth-address"
install -m 0644 "$project/configs/bluetooth/gts9uwifi-bluetooth-address.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-bluetooth-address.service"
install -m 0644 "$project/configs/bluetooth/20-gts9uwifi-address.conf" \
	"$overlay/etc/systemd/system/bluetooth.service.d/20-gts9uwifi-address.conf"
# Internal audio step 1: late-start the ADSP remoteproc once the rootfs (which
# carries the ~34 MB Samsung ADSP firmware) is mounted.  auto_boot fires too
# early to see the microSD firmware, so a oneshot service does the real start.
install -m 0755 "$project/configs/audio/gts9uwifi-adsp-boot" \
	"$overlay/usr/libexec/gts9uwifi-adsp-boot"
install -m 0644 "$project/configs/audio/gts9uwifi-adsp-boot.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-adsp-boot.service"
ln -sf ../gts9uwifi-adsp-boot.service \
	"$overlay/usr/lib/systemd/system/multi-user.target.wants/gts9uwifi-adsp-boot.service"
# Order pd-mapper after that late ADSP start; it needs a running remoteproc both
# to find its maps and to have someone to serve.
install -m 0644 "$project/configs/audio/10-gts9uwifi-adsp-order.conf" \
	"$overlay/etc/systemd/system/pd-mapper.service.d/10-gts9uwifi-adsp-order.conf"
# Keep the CS35L45 amplifiers awake: hibernation loses their PLL configuration
# while the driver's regmap cache still claims it is programmed.
install -m 0644 "$project/configs/audio/90-gts9uwifi-cs35l45-no-hibernate.rules" \
	"$overlay/usr/lib/udev/rules.d/90-gts9uwifi-cs35l45-no-hibernate.rules"
# ALSA UCM profile.  Without it the sound server sees a card it cannot route and
# falls back to a null sink; with it PulseAudio exposes the speakers and the
# DMICs as ordinary devices, so every application and the desktop volume control
# just work.  The reference SM8550 profile is useless here (no WSA/WCD codecs).
install -m 0644 "$project/configs/audio/ucm2/Samsung-Galaxy-Tab-S9-Ultra.conf" \
	"$overlay/usr/share/alsa/ucm2/conf.d/sm8550/Samsung-Galaxy-Tab-S9-Ultra.conf"
install -m 0644 "$project/configs/audio/ucm2/HiFi.conf" \
	"$overlay/usr/share/alsa/ucm2/Qualcomm/sm8550/GTS9U/HiFi.conf"
install -m 0755 "$project/configs/display-baseline/gts9uwifi-display-handoff" \
	"$overlay/usr/libexec/gts9uwifi-display-handoff"
install -m 0644 "$project/configs/display-baseline/20-gts9uwifi-fbdev.conf" \
	"$overlay/usr/share/X11/xorg.conf.d/20-gts9uwifi-fbdev.conf"
install -m 0644 "$project/configs/display-native/10-msm-dpu.conf" \
	"$overlay/etc/X11/xorg.conf.d/10-msm-dpu.conf"
# A 3.6 GB rootfs plus an uncapped journal is what put lightdm into a permanent
# crash loop once the filesystem hit 100%.  Cap it from the start.
install -m 0644 "$project/configs/development-ssh/10-gts9uwifi-journal-cap.conf" \
	"$overlay/etc/systemd/journald.conf.d/10-gts9uwifi-journal-cap.conf"
install -m 0644 "$project/configs/system-info/fastfetch-config.jsonc" \
	"$overlay/etc/xdg/fastfetch/config.jsonc"

install -m 0755 "$project/configs/display-native/gts9uwifi-install-xorg-package" \
	"$overlay/usr/libexec/gts9uwifi-install-xorg-package"
install -m 0644 "$project/configs/display-native/10-gts9uwifi-xorg-package.conf" \
	"$overlay/etc/systemd/system/lightdm.service.d/10-gts9uwifi-xorg-package.conf"
install -m 0755 "$project/configs/display-native/gts9uwifi-panel-reinit" \
	"$overlay/usr/libexec/gts9uwifi-panel-reinit"
install -m 0644 "$project/configs/display-native/20-gts9uwifi-panel-reinit.conf" \
	"$overlay/etc/systemd/system/lightdm.service.d/20-gts9uwifi-panel-reinit.conf"
install -m 0644 "$project/configs/display-native/20-gts9uwifi-display.conf" \
	"$overlay/etc/lightdm/lightdm.conf.d/20-gts9uwifi-display.conf"
install -m 0755 "$project/configs/display-native/gts9uwifi-panel-coldboot-recover" \
	"$overlay/usr/libexec/gts9uwifi-panel-coldboot-recover"
install -m 0644 "$project/configs/display-native/gts9uwifi-panel-coldboot-recover.service" \
	"$overlay/usr/lib/systemd/system/gts9uwifi-panel-coldboot-recover.service"
ln -sf ../gts9uwifi-panel-coldboot-recover.service \
	"$overlay/usr/lib/systemd/system/graphical.target.wants/gts9uwifi-panel-coldboot-recover.service"
install -m 0755 "$project/configs/display-native/gts9uwifi-lightdm-hidpi" \
	"$overlay/usr/libexec/gts9uwifi-lightdm-hidpi"
install -m 0644 "$project/configs/display-native/slick-greeter.conf" \
	"$overlay/etc/lightdm/slick-greeter.conf"
install -m 0755 "$project/configs/display-native/gts9uwifi-xfce-hidpi" \
	"$overlay/usr/libexec/gts9uwifi-xfce-hidpi"
install -m 0644 "$project/configs/display-native/gts9uwifi-xfce-hidpi.desktop" \
	"$overlay/etc/xdg/autostart/gts9uwifi-xfce-hidpi.desktop"
install -m 0644 "$xorg_apk" \
	"$overlay/usr/share/gts9uwifi/packages/$(basename "$xorg_apk")"
# Official linux-firmware amss: Samsung's WLAN.HMT downstream amss never
# raises WMI ready under mainline ath12k because it expects the phy_ucode
# QMI download that only cnss2 implements.
install -m 0644 "$firmware/official-amss.bin" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin"
# Canonical linux-firmware M3 image; Samsung ships no m3 for kiwi and the
# earlier phy_ucode20.elf mapping fed the chip PHY microcode as M3.
install -m 0644 "$firmware/m3.bin" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin"
# Keep the official container first while the X910-specific Samsung BDF is
# being validated. It has no matching X910/board-id 255 entry, so ath12k falls
# back to the proven QRD ELF in board.bin.
install -m 0644 "$firmware/official-board-2.bin" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin"
install -m 0644 "$firmware/qrd-board.bin" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin"
install -m 0644 "$firmware/regdb.bin" \
	"$overlay/usr/lib/firmware/ath12k/WCN7850/hw2.0/regdb.bin"

# WCN7850 Bluetooth firmware and Samsung board-NVM variants.  Mainline's
# hci_qca requests these from qca/ after bringing up the QUP SE14 serdev.
for f in hmtbtfw20.tlv hmtnv20.bin hmtnv20.b21 hmtnv20.b22 hmtnv20.b38; do
	install -m 0644 "$firmware/$f" "$overlay/usr/lib/firmware/qca/$f"
done
# hci_qca is built-in and probes before the microSD rootfs is mounted.  Keep
# the patch and the validated GTS9U b21 NVM in the generic initramfs so the
# first HCI setup succeeds.  Userspace then supplies the native EFS address.
install -m 0644 "$firmware/hmtbtfw20.tlv" \
	"$initramfs_overlay/usr/lib/firmware/qca/hmtbtfw20.tlv"
install -m 0644 "$firmware/hmtnv20.b21" \
	"$initramfs_overlay/usr/lib/firmware/qca/hmtnv20.b21"

BUNDLE_OUT_DIR="$bundle" \
BUNDLE_EXPORT_DIR="$bundle/export" \
INITRAMFS="$base/out/rootfs-gts9uwifi/initramfs" \
KERNEL_IMAGE="$kernel/Image.gz" \
KERNEL_DTB="$kernel/sm8550-samsung-gts9uwifi.dtb" \
PACKAGE_CONFIG="$kernel/config" \
INITRAMFS_OVERLAY_DIR="$initramfs_overlay" \
APPEND_DTB_TO_KERNEL=1 \
DISABLE_RUNTIME_DTBO=1 \
	bash "$project/scripts/build-android-v4-bundle.sh"

python3 "$project/scripts/make-twrp-zip.py" "$bundle" "$artifact" \
	--project "$project" \
	--rootfs-overlay "$overlay" \
	--label "postmarketOS mainline v$version for SM-X910 (WCN7850 PCIe cold-reset bring-up, isolated ath12k)"

stat -c '%n %s bytes' "$artifact"
