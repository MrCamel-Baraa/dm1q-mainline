#!/usr/bin/env bash
# PC-side test of scripts/phone-display-probe.sh (docs/06 rule 3). The phone's /proc, /sys, debugfs, module
# tree, lsmod and dmesg are replaced by a scratch tree through the script's env overrides; the script runs with
# dash (closest to the phone's busybox ash: no bashisms allowed) and with bash. Two scenarios:
#   full   msm bound, a connector with a mode, backlight, modules on disk, config.gz, deferred probe entries
#   bare   simpledrm only, no config.gz, no module dir, no debugfs: every section must still print, no crash
# Usage: bash scripts/test-phone-display-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

mk_common() { # $1 = root
	mkdir -p "$1/bin"
	printf '#!/bin/sh\ncat "%s/dmesg.txt"\n' "$1" > "$1/bin/dmesg"
	printf '#!/bin/sh\ncat "%s/lsmod.txt"\n' "$1" > "$1/bin/lsmod"
	chmod +x "$1/bin/dmesg" "$1/bin/lsmod"
}

# ---- scenario full
F="$W/full"; mkdir -p "$F"; mk_common "$F"
mkdir -p "$F/proc" "$F/sys/class/drm/card0-DSI-1" "$F/sys/class/graphics/fb0" "$F/sys/class/backlight/ae94000.dsi.0" \
	"$F/sys/bus/platform/devices/ae94000.dsi" "$F/sys/bus/platform/devices/3da0000.iommu" "$F/sys/bus/platform/drivers/msm_dsi" \
	"$F/sys/devices/ae00000" "$F/sys/bus/platform/devices/ae00000.display-subsystem" \
	"$F/dbg/clk" "$F/dbg/regulator" "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/msm" \
	"$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/panel" "$F/sys/drivers-real/msm"
echo "console=ttyMSM0 clk_ignore_unused pd_ignore_unused" > "$F/proc/cmdline"
mkdir -p "$F/proc/sys/kernel"; printf '4\t4\t1\t7\n' > "$F/proc/sys/kernel/printk"
printf 'CONFIG_DRM_MSM=m\nCONFIG_DRM_SIMPLEDRM=y\n# CONFIG_DRM_PANEL_SAMSUNG_S6E3FAC_AMB606AW01 is not set\nCONFIG_UNRELATED=y\nCONFIG_SM_DISPCC_8550=m\n' | gzip > "$F/proc/config.gz"
touch "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/msm/msm.ko.zst" "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/panel/panel-samsung-s6e3fac-amb606aw01.ko.zst"
mkdir -p "$F/sys/class/drm/card0"; ln -s "$F/sys/drivers-real/msm" "$F/sys/class/drm/card0/dev-driver-target"
mkdir -p "$F/sys/class/drm/card0/device"; ln -s "$F/sys/drivers-real/msm" "$F/sys/class/drm/card0/device/driver"
echo connected > "$F/sys/class/drm/card0-DSI-1/status"; echo enabled > "$F/sys/class/drm/card0-DSI-1/enabled"
echo "1080x2340" > "$F/sys/class/drm/card0-DSI-1/modes"
echo "msmdrmfb" > "$F/sys/class/graphics/fb0/name"; echo "1080,2340" > "$F/sys/class/graphics/fb0/virtual_size"
echo 32 > "$F/sys/class/graphics/fb0/bits_per_pixel"; echo 4320 > "$F/sys/class/graphics/fb0/stride"
echo 2047 > "$F/sys/class/backlight/ae94000.dsi.0/brightness"; echo 2047 > "$F/sys/class/backlight/ae94000.dsi.0/max_brightness"
ln -s "$F/sys/drivers-real/msm" "$F/sys/bus/platform/devices/ae94000.dsi/driver"
echo "3da0000.iommu  arm-smmu: wait for supplier" > "$F/dbg/devices_deferred"
echo " disp_cc_mdss_byte0_clk   1  1  0  118886400" > "$F/dbg/clk/clk_summary"
echo "panel_vci   1  1  0  3000mV" > "$F/dbg/regulator/regulator_summary"
printf ' gpio20  : out high func0 2mA no pull\n gpio125 : out high func0 2mA no pull\n gpio202 : in  low  func0 2mA pull down\n gpio21  : out high func0 2mA no pull\n gpio11: in   low  normal  vin-0 pull-down 10uA\n gpio1 : out  high normal\n' > "$F/dbg/gpio"
printf 'msm 1 0\nsnd 1 0\n' > "$F/lsmod.txt"
printf '[1.0] msm_dpu ae01000.display-controller: bound\n[2.0] unrelated line\n[3.0] panel-samsung-s6e3fac-amb606aw01 ae94000.dsi.0: panel id 81 02 25\n[0.3] arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402\n[0.4] arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402\n' > "$F/dmesg.txt"
# section 7: one group with a direct region (and one without), splash DT nodes (octal escapes: dash-safe)
mkdir -p "$F/sys/kernel/iommu_groups/4/devices" "$F/sys/kernel/iommu_groups/5/devices" "$F/proc/device-tree/reserved-memory/splash_region" "$F/proc/device-tree/soc@0/display-subsystem@ae00000"
touch "$F/sys/kernel/iommu_groups/4/devices/ae00000.display-subsystem"
printf '0x0000000000000000 0x00000000b7ffffff reserved\n0x00000000b8000000 0x00000000baafffff direct\n' > "$F/sys/kernel/iommu_groups/4/reserved_regions"
printf '0x00000000fffff000 0x00000000ffffffff msi\n' > "$F/sys/kernel/iommu_groups/5/reserved_regions"
printf '\000\000\000\123\270\000\000\000' > "$F/proc/device-tree/reserved-memory/splash_region/iommu-addresses"
printf '\000\000\000\123' > "$F/proc/device-tree/soc@0/display-subsystem@ae00000/memory-region"

run_full() { # shell
	env SYSFS="$F/sys" DEBUGFS="$F/dbg" PROC="$F/proc" DMESG="$F/bin/dmesg" LSMOD="$F/bin/lsmod" MODROOT="$F/mod" UNAME_R=7.3.0-rc3-dm1q ZCAT=zcat "$1" "$HERE/phone-display-probe.sh" > "$F/out" 2>&1
}

# ---- scenario bare
B="$W/bare"; mkdir -p "$B/proc" "$B/sys/class/drm/card0/device" "$B/sys/class/graphics/fb0" "$B/sys/drivers-real/simple-framebuffer"; mk_common "$B"
echo "console=ttyMSM0" > "$B/proc/cmdline"
ln -s "$B/sys/drivers-real/simple-framebuffer" "$B/sys/class/drm/card0/device/driver"
echo "simpledrmdrmfb" > "$B/sys/class/graphics/fb0/name"; echo "1080,2340" > "$B/sys/class/graphics/fb0/virtual_size"
: > "$B/lsmod.txt"; : > "$B/dmesg.txt"
run_bare() {
	env SYSFS="$B/sys" DEBUGFS="$B/nodbg" PROC="$B/proc" DMESG="$B/bin/dmesg" LSMOD="$B/bin/lsmod" MODROOT="$B/nomod" UNAME_R=7.3.0-rc3-dm1q ZCAT=zcat "$1" "$HERE/phone-display-probe.sh" > "$B/out" 2>&1
}

expect() { # file name regex
	if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi
}
reject() { # file name regex
	if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi
}

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	echo "== $sh, scenario full"
	run_full "$sh" || bad "$sh exits non-zero"
	expect "$F/out" "cmdline flags seen" "cmdline has clk_ignore_unused"
	expect "$F/out" "kernel.printk shown" "kernel\\.printk .*: 4[[:space:]]+4[[:space:]]+1[[:space:]]+7"
	expect "$F/out" "missing flag reported" "cmdline lacks regulator_ignore_unused"
	expect "$F/out" "config lines kept" "CONFIG_DRM_MSM=m"
	expect "$F/out" "'not set' line kept" "# CONFIG_DRM_PANEL_SAMSUNG_S6E3FAC_AMB606AW01 is not set"
	reject "$F/out" "unrelated config dropped" "CONFIG_UNRELATED"
	expect "$F/out" "msm.ko found on disk" "msm\\.ko"
	expect "$F/out" "panel module found" "panel-samsung-s6e3fac-amb606aw01\\.ko"
	expect "$F/out" "loaded module listed" "^msm 1 0"
	reject "$F/out" "unrelated module dropped" "^snd "
	expect "$F/out" "drm card driver" "card0: driver=msm"
	expect "$F/out" "connector status" "card0-DSI-1: status=connected enabled=enabled"
	expect "$F/out" "mode listed" "mode 1080x2340"
	expect "$F/out" "fb geometry" "fb0: name=msmdrmfb size=1080,2340 bpp=32 stride=4320"
	expect "$F/out" "backlight" "backlight ae94000\\.dsi\\.0: 2047/2047"
	expect "$F/out" "bound platform device" "ae94000\\.dsi: msm"
	expect "$F/out" "absent platform device" "ae95000\\.phy: absent"
	expect "$F/out" "deferred" "3da0000\\.iommu"
	expect "$F/out" "clock line" "disp_cc_mdss_byte0_clk"
	expect "$F/out" "regulator line" "panel_vci"
	expect "$F/out" "gpio20" "gpio20 +: out high"
	expect "$F/out" "pm8550 gpio11" "gpio11: in +low"
	reject "$F/out" "pm8550 gpio1 not confused with gpio11/gpio125 filter" "^ gpio1 :"
	expect "$F/out" "dmesg filtered in" "msm_dpu"
	expect "$F/out" "dmesg panel id" "panel id 81 02 25"
	reject "$F/out" "dmesg unrelated dropped" "unrelated line"
	expect "$F/out" "smmu fault count" "smmu context faults in dmesg: 2"
	expect "$F/out" "non-direct warning count" "non-direct resv warnings in dmesg: 0"
	expect "$F/out" "direct group listed" "iommu group 4 has direct regions; devices: ae00000\\.display-subsystem"
	expect "$F/out" "direct region line" "0x00000000b8000000 0x00000000baafffff direct"
	reject "$F/out" "group without direct region not listed" "iommu group 5"
	reject "$F/out" "reserved (non-direct) line not listed" "b7ffffff reserved"
	expect "$F/out" "splash iommu-addresses hex" "iommu-addresses: +00 00 00 53 b8 00 00 00"
	expect "$F/out" "splash reg absent reported" "splash_region/reg: absent"
	expect "$F/out" "mdss memory-region hex" "memory-region: +00 00 00 53"
	expect "$F/out" "ends with done" "^done$"

	echo "== $sh, scenario bare"
	run_bare "$sh" || bad "$sh exits non-zero (bare)"
	expect "$B/out" "no config.gz message" "NO .*config\\.gz"
	expect "$B/out" "no module dir message" "no .*7\\.3\\.0-rc3-dm1q"
	expect "$B/out" "simple-framebuffer driver" "card0: driver=simple-framebuffer"
	expect "$B/out" "fb0 reported" "fb0: name=simpledrmdrmfb"
	expect "$B/out" "no deferred file message" "no devices_deferred"
	expect "$B/out" "cmdline without flags" "cmdline lacks clk_ignore_unused"
	expect "$B/out" "bare: kernel.printk unreadable" "kernel\\.printk .*: unreadable"
	expect "$B/out" "bare: zero smmu faults" "smmu context faults in dmesg: 0"
	expect "$B/out" "bare: no direct group" "no iommu group with a direct region"
	expect "$B/out" "bare: DT nodes absent" "splash_region/iommu-addresses: absent"
	expect "$B/out" "ends with done (bare)" "^done$"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
