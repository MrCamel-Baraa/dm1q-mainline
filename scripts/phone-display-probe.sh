#!/bin/sh
# Phone-side, READ-ONLY probe of the display stack (docs/09 section 9). POSIX sh, run as root
# (collect-phone-state.sh --display does that). Touches nothing: no modprobe, no MMIO, only reads /proc,
# /sys, debugfs and dmesg. Prints what docs/09 still needs from the running r6/r7 system:
#   1. kernel release, command line (does it carry clk_ignore_unused / pd_ignore_unused?)
#   2. the RUNNING kernel's display-related CONFIG_ lines (/proc/config.gz)
#   3. which display modules exist on disk (msm, the panel, dispcc, gpucc) and which are loaded
#   4. DRM cards with their driver, fbdev geometry (simpledrm or msm), connector status and modes
#   5. the display platform devices and the driver bound to each (or "no driver")
#   6. deferred probes, display/GPU clocks, panel rails, the panel GPIOs, relevant dmesg lines
# Env overrides (the PC-side test uses them): SYSFS DEBUGFS PROC DMESG LSMOD MODROOT UNAME_R ZCAT
SYSFS="${SYSFS:-/sys}"
DEBUGFS="${DEBUGFS:-/sys/kernel/debug}"
PROC="${PROC:-/proc}"
DMESG="${DMESG:-dmesg}"
LSMOD="${LSMOD:-lsmod}"
MODROOT="${MODROOT:-/lib/modules}"
UNAME_R="${UNAME_R:-$(uname -r)}"
ZCAT="${ZCAT:-zcat}"

say() { echo; echo "== $*"; }
drvname() { # $1 = device dir -> bound driver name or "no driver"
	if [ -L "$1/driver" ]; then basename "$(readlink "$1/driver")"; else echo "no driver"; fi
}

say "1. kernel"
echo "release: $UNAME_R"
echo "cmdline: $(cat "$PROC/cmdline" 2>/dev/null)"
for w in clk_ignore_unused pd_ignore_unused regulator_ignore_unused; do
	if grep -q "$w" "$PROC/cmdline" 2>/dev/null; then echo "cmdline has $w"; else echo "cmdline lacks $w"; fi
done

say "2. running kernel config (display-related)"
if [ -r "$PROC/config.gz" ]; then
	"$ZCAT" "$PROC/config.gz" | grep -E '^(# )?CONFIG_(DRM_MSM|DRM_SIMPLEDRM|DRM_PANEL_SAMSUNG[A-Z0-9_]*|DRM_DISPLAY_[A-Z_]*HELPER|DRM_PANEL_BRIDGE|DRM_FBDEV_EMULATION|FB_SIMPLE|SYSFB_SIMPLEFB|SM_DISPCC_8550|SM_GPUCC_8550|SM_GCC_8550|QCOM_LLCC|QCOM_COMMAND_DB|QCOM_UBWC_CONFIG|BACKLIGHT_CLASS_DEVICE|ARM_SMMU|QCOM_IOMMU|INTERCONNECT_QCOM_SM8550|PHY_QCOM_QMP|REGULATOR_FIXED_VOLTAGE|PINCTRL_MSM|PINCTRL_SM8550|MODULE_SIG[A-Z_]*|LOCK_DOWN_KERNEL_FORCE_[A-Z]*)[= ]' || echo "(no matching lines)"
else
	echo "NO $PROC/config.gz (CONFIG_IKCONFIG_PROC off?)"
fi

say "3. display modules"
echo "on disk under $MODROOT/$UNAME_R:"
if [ -d "$MODROOT/$UNAME_R" ]; then
	find "$MODROOT/$UNAME_R" \( -name 'msm.ko*' -o -name 'panel-samsung-s6e3fac*' -o -name 'clk-sm8550-dispcc*' -o -name 'dispcc-sm8550*' -o -name 'gpucc-sm8550*' -o -name 'clk-sm8550-gpucc*' -o -name 'llcc-qcom*' -o -name 'drm_display_helper*' -o -name 'simpledrm*' \) 2>/dev/null | sed "s|^$MODROOT/$UNAME_R/||" | sort
else
	echo "(no $MODROOT/$UNAME_R)"
fi
echo "loaded:"
"$LSMOD" 2>/dev/null | grep -iE '^(msm|drm|panel|dispcc|gpucc|llcc|simpledrm|backlight|drm_display|drm_dp|drm_exec|drm_gpuvm|gpu_sched|ubwc)' || echo "(none)"

say "4. DRM / fbdev"
ncards=0
for c in "$SYSFS"/class/drm/card[0-9]*; do
	[ -e "$c" ] || continue
	case "$(basename "$c")" in card[0-9]) ;; *) continue ;; esac
	ncards=1
	echo "$(basename "$c"): driver=$(drvname "$c/device")"
done
[ "$ncards" = 1 ] || echo "(no DRM devices)"
for k in "$SYSFS"/class/drm/card*-*; do
	[ -e "$k" ] || continue
	echo "$(basename "$k"): status=$(cat "$k/status" 2>/dev/null) enabled=$(cat "$k/enabled" 2>/dev/null)"
	[ -r "$k/modes" ] && sed 's/^/    mode /' "$k/modes"
done
for f in "$SYSFS"/class/graphics/fb[0-9]*; do
	[ -e "$f" ] || continue
	echo "$(basename "$f"): name=$(cat "$f/name" 2>/dev/null) size=$(cat "$f/virtual_size" 2>/dev/null) bpp=$(cat "$f/bits_per_pixel" 2>/dev/null) stride=$(cat "$f/stride" 2>/dev/null)"
done
for b in "$SYSFS"/class/backlight/*; do
	[ -e "$b" ] || continue
	echo "backlight $(basename "$b"): $(cat "$b/brightness" 2>/dev/null)/$(cat "$b/max_brightness" 2>/dev/null)"
done

say "5. display platform devices"
for d in ae00000.display-subsystem ae01000.display-controller ae94000.dsi ae95000.phy af00000.clock-controller 3d90000.clock-controller 3da0000.iommu 3d00000.gpu 3d6a000.gmu framebuffer0 simple-framebuffer.0; do
	p="$SYSFS/bus/platform/devices/$d"
	if [ -e "$p" ]; then echo "$d: $(drvname "$p")"; else echo "$d: absent"; fi
done

say "6a. deferred probes"
cat "$DEBUGFS/devices_deferred" 2>/dev/null || echo "(no devices_deferred)"

say "6b. clocks (display / GPU / DSI)"
grep -E 'disp_cc|mdss|gpu_cc|byte|pclk|dsi|esc' "$DEBUGFS/clk/clk_summary" 2>/dev/null | head -60 || echo "(no clk_summary)"

say "6c. regulators (panel rails, DSI/PHY supplies)"
grep -iE 'panel|avdd|vreg_l3e|vreg_l1e|ae94000|ae95000|display' "$DEBUGFS/regulator/regulator_summary" 2>/dev/null || echo "(none)"

say "6d. panel GPIO state (TLMM 20 21 86 125 187; PM8550 gpio11)"
grep -E '^ gpio(20|21|86|87|108|125|186|187|202) |^ gpio11:' "$DEBUGFS/gpio" 2>/dev/null || echo "(no gpio debugfs lines)"

say "6e. dmesg (display related)"
"$DMESG" 2>/dev/null | grep -iE 'drm|msm_|dpu|mdss|dsi|simpledrm|simple-framebuffer|dispcc|gpucc|3da0000|panel|llcc|fb0|aperture|backlight|s6e3fac' | head -150
echo
echo "done"
