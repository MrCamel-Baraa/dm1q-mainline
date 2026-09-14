#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
kernel_src="${KERNEL_SRC:-$base/linux-mainline}"
kernel_tree="${KERNEL_WORKTREE:-$base/build/linux-src-gts9uwifi}"
build_dir="${KERNEL_BUILD_DIR:-$base/build/linux-gts9uwifi}"
out_dir="${KERNEL_OUT_DIR:-$base/out/kernel-gts9uwifi}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
package="$project/pmaports/device/testing/linux-samsung-gts9uwifi-mainline"

test -d "$kernel_src/.git"
test -f "$package/sm8550-samsung-gts9uwifi.dts"

mkdir -p "$(dirname "$kernel_tree")" "$build_dir" "$out_dir"
cd "$base"

if [ ! -e "$kernel_tree/.git" ]; then
	git -C "$kernel_src" worktree add --detach "$kernel_tree" HEAD
fi

# Keep the pinned upstream checkout pristine.  The board DTS is supplied by
# this project and the build output lives in a separate O= directory.
install -m 0644 "$package/sm8550-samsung-gts9uwifi.dts" \
	"$build_dir/sm8550-samsung-gts9uwifi.dts"

cp "$package/sm8550-samsung-gts9uwifi.dts" \
	"$kernel_tree/arch/arm64/boot/dts/qcom/sm8550-samsung-gts9uwifi.dts"

if ! grep -q 'sm8550-samsung-gts9uwifi.dtb' \
	"$kernel_tree/arch/arm64/boot/dts/qcom/Makefile"; then
	patch -d "$kernel_tree" -p1 < "$package/add-gts9uwifi-dtb.patch"
fi
if [ ! -f "$kernel_tree/drivers/soc/qcom/samsung-gts9uwifi-sec-log.c" ]; then
	patch -d "$kernel_tree" -p1 < "$package/add-samsung-sec-log-console.patch"
fi
if ! grep -q 'previous_index, index' \
	"$kernel_tree/drivers/soc/qcom/samsung-gts9uwifi-sec-log.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/keep-sec-log-previous-index-current.patch"
fi
if ! grep -q 'Match Samsung SM8550 sequencing' \
	"$kernel_tree/drivers/phy/phy-snps-eusb2.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/match-samsung-sm8550-eusb2-phy-init.patch"
fi
if ! grep -q 'forcing 16-byte Samsung events for firmware PID 6936' \
	"$kernel_tree/drivers/input/touchscreen/goodix_berlin_core.c"; then
	if grep -q 'GOODIX_BERLIN_SAMSUNG_EVENT_ID_MASK' \
		"$kernel_tree/drivers/input/touchscreen/goodix_berlin_core.c"; then
		patch -d "$kernel_tree" -p1 \
			< "$package/upgrade-partial-goodix-samsung-events.patch"
	else
		patch -d "$kernel_tree" -p1 \
			< "$package/support-samsung-goodix-16-byte-events.patch"
	fi
fi
if ! grep -q 'PTN3222_MAX_INIT_CELLS' \
	"$kernel_tree/drivers/phy/phy-nxp-ptn3222.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/configure-nxp-ptn3222-from-dt.patch"
fi
# WCN7850 functional fixes: cold-reset WLAN_EN before PCIe probe and program
# the stock AOP WLAN PDC table over the QMP mailbox.  Bring-up diagnostics were
# removed; this is the consolidated functional-only patch.
if ! grep -q 'pwrseq_qcom_wcn_program_wlan_pdc' \
	"$kernel_tree/drivers/power/sequencing/pwrseq-qcom-wcn.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/wcn7850-pwrseq-cold-reset-aop.patch"
fi
if ! grep -q 'default y if ARCH_QCOM' \
	"$kernel_tree/drivers/pci/pwrctrl/Kconfig"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/build-wcn-pcie-providers-in.patch"
fi
# Unpark the PCIe0 PIPE clock mux the boot chain left on XO (functional fix).
if ! grep -q 'clk_set_rate(qmp->pipe_clks\[0\].clk, ULONG_MAX)' \
	"$kernel_tree/drivers/phy/qualcomm/phy-qcom-qmp-pcie.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/unpark-pcie0-pipe-mux.patch"
fi
# sc8280xp_snd_init() tells the CPU side that the LPASS provides bit clock and
# frame sync on MI2S, but nothing tells the codec the matching format, so an I2S
# codec keeps its reset default.  AudioReach programs the port itself, so only
# the codec side needs setting (q6apm has no .set_sysclk: it returns -ENOTSUPP).
if ! grep -q 'sc8280xp_snd_startup' \
	"$kernel_tree/sound/soc/qcom/sc8280xp.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/set-mi2s-codec-dai-format.patch"
fi
# Xorg only creates a PRIME GPU screen when MODE_GETRESOURCES succeeds.  Keep
# the split GPU/DPU topology, but expose an empty KMS resource list on Adreno.
if sed -n '/static const struct drm_driver msm_gpu_driver/,/^};/p' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c" | \
	grep -q 'DRIVER_FEATURES_GPU,$'; then
	patch -d "$kernel_tree" -p1 \
		< "$package/expose-separate-gpu-kms-resources.patch"
elif ! sed -n '/static const struct drm_driver msm_gpu_driver/,/^};/p' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c" | \
	grep -q 'DRIVER_FEATURES_GPU | DRIVER_MODESET'; then
	echo 'unexpected msm_gpu_driver features; refusing to build' >&2
	exit 1
elif ! sed -n '/static int msm_drm_init/,/^}/p' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c" | \
	grep -q 'drm_core_check_feature(ddev, DRIVER_MODESET)'; then
	echo 'separate GPU mode_config guard missing; refusing to build' >&2
	exit 1
elif ! sed -n '/static const struct drm_driver msm_gpu_driver/,/^};/p' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c" | \
	grep -q 'dumb_create[[:space:]]*= msm_gem_dumb_create'; then
	echo 'separate GPU dumb-buffer hook missing; refusing to build' >&2
	exit 1
elif ! grep -q 'msm_gpu_mode_config_funcs' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c"; then
	echo 'separate GPU framebuffer hook missing; refusing to build' >&2
	exit 1
elif ! grep -q 'mode_config.max_width = 16384' \
	"$kernel_tree/drivers/gpu/drm/msm/msm_drv.c"; then
	echo 'separate GPU framebuffer bounds missing; refusing to build' >&2
	exit 1
fi
# The USB-C connector beyond the QMP/PS5169 path is not a DRM bridge.  External
# DP remains usable through msm_dp's own connector operations; do not let the
# unresolved optional tail defer the complete MSM component master (and DSI).
if ! grep -q 'ret != -ENODEV && ret != -EPROBE_DEFER' \
	"$kernel_tree/drivers/gpu/drm/msm/dp/dp_display.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/msm-dp-allow-unresolved-usbc-bridge.patch"
fi
# Type-C DP HPD is carried out-of-band in the PD Status VDO on this board.
# Preserve the DP controller fwnode on the terminal bridge so the generic
# altmode driver can match that event to the DRM connector.
if ! grep -q 'bridge->of_node = msm_dp_display->pdev->dev.of_node' \
	"$kernel_tree/drivers/gpu/drm/msm/dp/dp_drm.c"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/msm-dp-associate-bridge-of-node.patch"
fi
# The internal panel needs one platform-level suspend/resume on every cold
# boot.  Keep an already attached dock negotiated, but delay its OOB HPD until
# that recovery has completed so the external DPU encoder cannot wedge suspend.
if ! grep -q 'defer_hpd_until_resume' \
	"$kernel_tree/drivers/gpu/drm/msm/dp/dp_drm.h"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/msm-dp-defer-oob-hpd-until-resume.patch"
fi
# A powered charge-through dock can retain Source/UFP while the tablet reboots.
# Let the SM5714 opt in to adopting DFP rather than looping in error recovery.
if ! grep -q 'adopt_retained_source_ufp' \
	"$kernel_tree/include/linux/usb/tcpm.h"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/tcpm-adopt-retained-source-ufp-role.patch"
fi
# A powered Source/UFP dock can retain both its connection and the SM5714's
# previous local DFP bit while the tablet reboots, yet omit Source_Capabilities
# on the next boot.  Seed the matching Sink/DFP role before waiting for PD.
if ! grep -q 'consume_retained_sink_dfp' \
	"$kernel_tree/include/linux/usb/tcpm.h"; then
	patch -d "$kernel_tree" -p1 \
		< "$package/tcpm-use-retained-sink-data-role.patch"
fi
if ! grep -q '^DTC_FLAGS_sm8550-samsung-gts9uwifi := -@$' \
	"$kernel_tree/arch/arm64/boot/dts/qcom/Makefile"; then
	sed -i '/sm8550-samsung-gts9uwifi\.dtb/a DTC_FLAGS_sm8550-samsung-gts9uwifi := -@' \
		"$kernel_tree/arch/arm64/boot/dts/qcom/Makefile"
fi

# ANA38407 (gts9u) DSI panel driver.  Ship the .c into the pristine panel dir and
# register it in Kconfig/Makefile, mirroring how the board DTS is supplied.
panel_dir="$kernel_tree/drivers/gpu/drm/panel"
install -m 0644 "$package/panel-samsung-ana38407.c" \
	"$panel_dir/panel-samsung-ana38407.c"
if ! grep -q 'DRM_PANEL_SAMSUNG_ANA38407' "$panel_dir/Kconfig"; then
	sed -i '/^endmenu$/i \
config DRM_PANEL_SAMSUNG_ANA38407\
\ttristate "Samsung ANA38407 AMSA46AS02 (gts9u) DSI command-mode panel"\
\tdepends on OF\
\tdepends on DRM_MIPI_DSI\
\tdepends on BACKLIGHT_CLASS_DEVICE\
\thelp\
\t  DSC command-mode DSI panel on the Galaxy Tab S9 Ultra Wi-Fi (SM-X910).\
' "$panel_dir/Kconfig"
fi
if ! grep -q 'panel-samsung-ana38407.o' "$panel_dir/Makefile"; then
	printf 'obj-$(CONFIG_DRM_PANEL_SAMSUNG_ANA38407) += panel-samsung-ana38407.o\n' \
		>> "$panel_dir/Makefile"
fi

# Silicon Mitus SM5714 charger/fuel gauge.  Shipped the same way as the panel:
# the .c goes into the pristine tree and Kconfig/Makefile learn about it here.
supply_dir="$kernel_tree/drivers/power/supply"
install -m 0644 "$package/sm5714_battery.c" "$supply_dir/sm5714_battery.c"
if ! grep -q 'BATTERY_SM5714' "$supply_dir/Kconfig"; then
	sed -i '/^endif # POWER_SUPPLY$/i \
config BATTERY_SM5714\
\ttristate "Silicon Mitus SM5714 charger and fuel gauge"\
\tdepends on I2C\
\tdepends on IIO\
\thelp\
\t  Battery state of charge and charging status on boards that drive the\
\t  SM5714 combo PMIC from the AP, such as the Galaxy Tab S9 Ultra Wi-Fi.\
' "$supply_dir/Kconfig"
fi
if ! grep -q 'sm5714_battery.o' "$supply_dir/Makefile"; then
	printf 'obj-$(CONFIG_BATTERY_SM5714)\t+= sm5714_battery.o\n' \
		>> "$supply_dir/Makefile"
fi

# Silicon Mitus SM5440 2:1 charge pump.  TCPM remains responsible for PPS;
# this board driver coordinates the pump with the SM5714 switching path.
install -m 0644 "$package/sm5440_direct.c" "$supply_dir/sm5440_direct.c"
if ! grep -q 'CHARGER_SM5440_DIRECT' "$supply_dir/Kconfig"; then
	sed -i '/^endif # POWER_SUPPLY$/i \
config CHARGER_SM5440_DIRECT\
\ttristate "Silicon Mitus SM5440 direct charger for Samsung SM-X910"\
\tdepends on I2C\
\tdepends on BATTERY_SM5714\
\thelp\
\t  Conservative PPS-controlled 2:1 direct charging on the Galaxy Tab S9\
\t  Ultra Wi-Fi, with automatic fallback to the SM5714 switching charger.\
' "$supply_dir/Kconfig"
fi
if ! grep -q 'sm5440_direct.o' "$supply_dir/Makefile"; then
	printf 'obj-$(CONFIG_CHARGER_SM5440_DIRECT)\t+= sm5440_direct.o\n' \
		>> "$supply_dir/Makefile"
fi

# SM5714 Type-C/PD transport.  The generic Linux TCPM core remains the policy
# engine; this driver only maps the Samsung-documented CC/PD register protocol.
tcpm_dir="$kernel_tree/drivers/usb/typec/tcpm"
install -m 0644 "$package/sm5714_usbpd.c" "$tcpm_dir/sm5714_usbpd.c"
if ! grep -q 'TYPEC_SM5714' "$tcpm_dir/Kconfig"; then
	sed -i '/^endif # TYPEC_TCPM$/i \
config TYPEC_SM5714\
\ttristate "Silicon Mitus SM5714 USB Type-C and PD controller"\
\tdepends on I2C\
\tdepends on TYPEC_TCPM\
\tdepends on BATTERY_SM5714\
\thelp\
\t  USB Type-C CC and USB-PD message transport for the SM5714 PDIC.\
' "$tcpm_dir/Kconfig"
fi
if ! grep -q 'sm5714_usbpd.o' "$tcpm_dir/Makefile"; then
	printf 'obj-$(CONFIG_TYPEC_SM5714)\t+= sm5714_usbpd.o\n' \
		>> "$tcpm_dir/Makefile"
fi

# Parade PS5169 Type-C SuperSpeed/DisplayPort redriver.  Its register
# programming is taken from Samsung's GPL source, while policy and chaining use
# the mainline orientation-switch/retimer graph.
typec_mux_dir="$kernel_tree/drivers/usb/typec/mux"
install -m 0644 "$package/ps5169.c" "$typec_mux_dir/ps5169.c"
if ! grep -q 'TYPEC_MUX_PS5169' "$typec_mux_dir/Kconfig"; then
	cat >> "$typec_mux_dir/Kconfig" <<'EOF'

config TYPEC_MUX_PS5169
	tristate "Parade PS5169 Type-C redriver"
	depends on I2C
	depends on TYPEC
	depends on USB_ROLE_SWITCH
	help
	  USB 3.x and DisplayPort lane redriver used by the SM-X910.
EOF
fi
if ! grep -q 'ps5169.o' "$typec_mux_dir/Makefile"; then
	printf 'obj-$(CONFIG_TYPEC_MUX_PS5169)\t+= ps5169.o\n' \
		>> "$typec_mux_dir/Makefile"
fi

cp "$base/pmaports/device/main/linux-postmarketos-mainline/config-mainline.aarch64" \
	"$build_dir/.config"

while IFS= read -r setting; do
	case "$setting" in
		CONFIG_*=y)
			symbol=${setting%%=*}
			"$kernel_tree/scripts/config" --file "$build_dir/.config" \
				--enable "${symbol#CONFIG_}"
			;;
		CONFIG_*=m)
			symbol=${setting%%=*}
			"$kernel_tree/scripts/config" --file "$build_dir/.config" \
				--module "${symbol#CONFIG_}"
			;;
		'# CONFIG_'*' is not set')
			symbol=${setting#\# CONFIG_}
			symbol=${symbol% is not set}
			"$kernel_tree/scripts/config" --file "$build_dir/.config" \
				--disable "$symbol"
			;;
	esac
done < "$package/config-gts9uwifi.fragment"

make -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 olddefconfig

# A fragment line naming a symbol that does not exist (typo, or the wrong
# vendor naming convention) is dropped by olddefconfig without a word: that is
# how the GPU once shipped with no clock controller.  Assert every requested
# setting survived.  A =m promoted to =y by some select is fine; anything else
# missing is a build error.
# An unknown or disabled symbol is fatal; a =y that a `select` could only
# satisfy as =m (e.g. ATH_COMMON under ATH12K=m) is normal and only warned about.
missing=
downgraded=
while IFS= read -r setting; do
	case "$setting" in
		CONFIG_*=y|CONFIG_*=m)
			symbol=${setting%%=*}
			want=${setting##*=}
			if grep -qxF "$symbol=y" "$build_dir/.config"; then
				:
			elif grep -qxF "$symbol=m" "$build_dir/.config"; then
				[ "$want" = y ] && downgraded="$downgraded $symbol"
			else
				missing="$missing $symbol"
			fi
			;;
	esac
done < "$package/config-gts9uwifi.fragment"
if [ -n "$downgraded" ]; then
	echo "warning: fragment asked =y, kconfig could only give =m:$downgraded" >&2
fi
if [ -n "$missing" ]; then
	echo "config fragment symbols unknown or disabled:$missing" >&2
	exit 1
fi

make -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 -j"$(nproc)" \
	Image.gz qcom/sm8550-samsung-gts9uwifi.dtb

if [ "${BUILD_WIFI_MODULES:-0}" = 1 ]; then
	modules_root="$out_dir/modules-root"
	case "$modules_root" in
		"$base"/out/*/modules-root) rm -rf -- "$modules_root" ;;
		*) echo "unsafe modules output path: $modules_root" >&2; exit 1 ;;
	esac

	# Building Image produces the complete built-in export table as
	# vmlinux.symvers.  An isolated in-tree M= build expects the same table
	# under the external-module name before it can resolve core symbols.
	# A clean O= tree also lacks scripts/module.lds until modules_prepare;
	# stale worktrees hid this dependency in older builds.  Keep M= absolute
	# so its source/output location is unambiguous across callers.
	module_tree="$kernel_tree/drivers/net/wireless/ath/ath12k"
	make -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 \
		modules_prepare
	cp "$build_dir/vmlinux.symvers" "$build_dir/Module.symvers"
	make -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 -j"$(nproc)" \
		M="$module_tree" modules
	make -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 \
		M="$module_tree" \
		INSTALL_MOD_PATH="$modules_root" INSTALL_MOD_STRIP=1 \
		DEPMOD=true modules_install

	release=$(make -s -C "$kernel_tree" O="$build_dir" ARCH=arm64 LLVM=1 kernelrelease)
	release_dir="$modules_root/lib/modules/$release"
	install -m 0644 "$build_dir/modules.builtin" \
		"$release_dir/modules.builtin"
	install -m 0644 "$build_dir/modules.builtin.modinfo" \
		"$release_dir/modules.builtin.modinfo"
	find "$release_dir/updates" -type f -name '*.ko*' -printf '%P\n' \
		| sed 's#^#updates/#' | sort > "$release_dir/modules.order"
	depmod -b "$modules_root" "$release"
	mkdir -p "$modules_root/usr/lib"
	mv "$modules_root/lib/modules" "$modules_root/usr/lib/modules"
	rmdir "$modules_root/lib"
	printf '%s\n' "$release" > "$out_dir/kernel.release"
fi

install -m 0644 "$build_dir/arch/arm64/boot/Image.gz" "$out_dir/Image.gz"
install -m 0644 \
	"$build_dir/arch/arm64/boot/dts/qcom/sm8550-samsung-gts9uwifi.dtb" \
	"$out_dir/sm8550-samsung-gts9uwifi.dtb"
install -m 0644 "$build_dir/.config" "$out_dir/config"

sha256sum "$out_dir/Image.gz" \
	"$out_dir/sm8550-samsung-gts9uwifi.dtb" \
	"$out_dir/config" > "$out_dir/SHA256SUMS"

cat "$out_dir/SHA256SUMS"
