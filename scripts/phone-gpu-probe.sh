#!/bin/sh
# Phone-side, READ-ONLY probe of the Adreno 740 / GPU stack (docs/11-gpu-bringup.md section 7). POSIX sh, run as
# root (collect-phone-state.sh --gpu does that). It touches nothing: no modprobe, no MMIO, no writes, and it never
# OPENS /dev/dri/* (the msm driver loads the GPU firmware and powers the GPU up on the first open of ANY node of
# the unified DRM device, msm_open() -> load_gpu(), docs/11 section 5; this probe only lists the nodes). Prints:
#   1. kernel release, command line (msm / firmware_class / *_ignore_unused flags), firmware_class.path
#   2. the RUNNING kernel's GPU-related CONFIG_ lines (/proc/config.gz)
#   3. GPU-related modules on disk and loaded, msm module parameters
#   4. GPU platform devices (bound driver, DT status, waiting_for_supplier) and the DT gpu node, its zap-shader
#      child, the gpu_micro_code reserved region and its /proc/iomem entry
#   5. DRM cards/render nodes, devfreq devices
#   6. firmware files the kernel can find (a740/gmu/zap) and the staging directories, with sizes and sha256
#   6b. the firmware LOOKUP as the loader does it (custom path, updates/<rel>, updates, <rel>, root; plain and .xz), seen from this shell,
#      from pid 1 and from pid 2 (the kernel threads: /proc/<pid>/root), with what a read of each existing path says (docs/11 section 9.13),
#      the directory chain, the symlinks below the firmware root, symlink loops (find -L) and the mounts carrying the path
#   7. installed packages (firmware, Mesa), the Mesa msm/freedreno userspace files, GPU tools in PATH
#   8. /boot/initramfs-extra fingerprint (docs/06 rule 3 baseline: did something regenerate it?)
#   9. interrupts, GPU clocks, GPU power domains, deferred probes, GPU/SMMU dmesg lines
#  10. a key=value summary
# Env overrides (the PC-side test uses them): SYSFS DEBUGFS PROC DMESG LSMOD MODROOT UNAME_R ZCAT FWROOT FWSTAGE
#   BOOTDIR PLASMA_SAVED APK SHA DEVDRI USRLIB ICD
SYSFS="${SYSFS:-/sys}"
DEBUGFS="${DEBUGFS:-/sys/kernel/debug}"
PROC="${PROC:-/proc}"
DMESG="${DMESG:-dmesg}"
LSMOD="${LSMOD:-lsmod}"
MODROOT="${MODROOT:-/lib/modules}"
UNAME_R="${UNAME_R:-$(uname -r)}"
ZCAT="${ZCAT:-zcat}"
FWROOT="${FWROOT:-/lib/firmware}"
FWSTAGE="${FWSTAGE:-/root/dm1q-gpu-fw /var/lib/dm1q-gpu-fw}"
BOOTDIR="${BOOTDIR:-/boot}"
PLASMA_SAVED="${PLASMA_SAVED:-/root/dm1q-plasma/initramfs-extra.pre-plasma}"
APK="${APK:-apk}"
SHA="${SHA:-sha256sum}"
DEVDRI="${DEVDRI:-/dev/dri}"
USRLIB="${USRLIB:-/usr/lib}"
ICD="${ICD:-/usr/share/vulkan/icd.d}"

say() { echo; echo "== $*"; }
drvname() { # $1 = device dir -> bound driver name or "no driver"
	if [ -L "$1/driver" ]; then basename "$(readlink "$1/driver")"; else echo "no driver"; fi
}
strprop() { # $1 = DT property file -> its string value (NUL bytes dropped)
	tr -d '\000' 2>/dev/null < "$1"
}
listprop() { # $1 = DT string-list property file -> its strings, NUL separators shown as spaces
	tr '\000' ' ' 2>/dev/null < "$1" | sed 's/ *$//'
}
hexprop() { # $1 = DT property file -> bytes in hex
	od -An -v -tx1 "$1" 2>/dev/null | tr -s ' \n' ' '
}
fwfiles() { # $1 = directory -> a740 / gmu / zap / gen70 firmware files below it, with size and sha256
	[ -d "$1" ] || { echo "  $1: no such directory"; return 0; }
	fwl=$(find "$1" -maxdepth 6 \( -name 'a740*' -o -name 'gmu_gen*' -o -name 'gen70*' -o -name 'a7*_zap*' -o -name 'a7*_sqe*' \) 2>/dev/null | sort)
	if [ -z "$fwl" ]; then echo "  $1: no a740 / gmu / zap files"; return 0; fi
	echo "$fwl" | while read -r f; do
		[ -f "$f" ] || continue
		echo "  $f $(wc -c < "$f") bytes sha256=$("$SHA" "$f" 2>/dev/null | cut -d' ' -f1)"
	done
}

say "1. kernel"
echo "release: $UNAME_R"
echo "cmdline: $(cat "$PROC/cmdline" 2>/dev/null)"
for w in clk_ignore_unused pd_ignore_unused regulator_ignore_unused modprobe.blacklist msm. firmware_class.path; do
	if grep -qF -- "$w" "$PROC/cmdline" 2>/dev/null; then echo "cmdline has $w"; else echo "cmdline lacks $w"; fi
done
fwp=$(cat "$SYSFS/module/firmware_class/parameters/path" 2>/dev/null)
if [ -r "$SYSFS/module/firmware_class/parameters/path" ]; then echo "firmware_class.path (custom search dir): '$fwp'"; else echo "firmware_class.path: unreadable"; fi

say "2. running kernel config (GPU-related)"
if [ -r "$PROC/config.gz" ]; then
	"$ZCAT" "$PROC/config.gz" | grep -E '^(# )?CONFIG_(DRM_MSM[A-Z_]*|DRM_GPUVM|DRM_SCHED|DRM_EXEC|DRM_SIMPLEDRM|SM_GPUCC_8550|SM_GCC_8550|SM_DISPCC_8550|QCOM_SCM|QCOM_PAS[A-Z_]*|QCOM_MDT_LOADER|QCOM_PIL_INFO|QCOM_TZMEM[A-Z_]*|QCOM_RPMHPD|QCOM_RPMH|QCOM_COMMAND_DB|QCOM_AOSS_QMP|QCOM_LLCC|QCOM_UBWC_CONFIG|QCOM_QFPROM|NVMEM_QCOM_QFPROM|ARM_SMMU[A-Z_]*|INTERCONNECT_QCOM_SM8550|PM_DEVFREQ|DEVFREQ_GOV_[A-Z_]*|PM_OPP|FW_LOADER[A-Z_]*|EXTRA_FIRMWARE|WANT_DEV_COREDUMP|DEV_COREDUMP|ARM64_SVE|MODULE_SIG[A-Z_]*|LOCK_DOWN_KERNEL_FORCE_[A-Z]*)[= ]' || echo "(no matching lines)"
else
	echo "NO $PROC/config.gz (CONFIG_IKCONFIG_PROC off?)"
fi

say "3. GPU modules"
echo "on disk under $MODROOT/$UNAME_R:"
if [ -d "$MODROOT/$UNAME_R" ]; then
	find "$MODROOT/$UNAME_R" \( -name 'msm.ko*' -o -name 'gpucc-sm8550*' -o -name 'clk-sm8550-gpucc*' -o -name 'qcom_mdt_loader*' -o -name 'mdt_loader*' -o -name 'qcom_pil_info*' -o -name 'gpu-sched*' -o -name 'drm_gpuvm*' -o -name 'drm_exec*' -o -name 'ubwc_config*' -o -name 'llcc-qcom*' \) 2>/dev/null | sed "s|^$MODROOT/$UNAME_R/||" | sort
else
	echo "(no $MODROOT/$UNAME_R)"
fi
echo "loaded:"
"$LSMOD" 2>/dev/null | grep -iE '^(msm|gpucc|gpu_sched|drm_gpuvm|drm_exec|ubwc|qcom_mdt|qcom_pil|mdt_loader|llcc|gpu_cc)' || echo "(none)"
echo "msm module parameters:"
nparm=0
for q in "$SYSFS"/module/msm/parameters/*; do
	[ -f "$q" ] || continue
	nparm=1
	echo "  $(basename "$q")=$(cat "$q" 2>/dev/null)"
done
[ "$nparm" = 1 ] || echo "  (none readable: msm not loaded?)"

say "4. GPU platform devices and the DT gpu node"
for d in 3d00000.gpu 3d6a000.gmu 3d90000.clock-controller 3da0000.iommu ae00000.display-subsystem ae01000.display-controller; do
	p="$SYSFS/bus/platform/devices/$d"
	if [ -e "$p" ]; then
		st=$(strprop "$p/of_node/status")
		[ -n "$st" ] || st="(no status property = okay)"
		ws=$(cat "$p/waiting_for_supplier" 2>/dev/null || echo n/a)
		echo "$d: driver=$(drvname "$p") dt-status=$st waiting_for_supplier=$ws"
	else
		echo "$d: absent"
	fi
done
ngpu=0
for g in "$PROC"/device-tree/soc*/gpu@3d00000; do
	[ -d "$g" ] || continue
	ngpu=1
	st=$(strprop "$g/status")
	echo "DT gpu node: status='${st:-(absent = okay)}' compatible='$(listprop "$g/compatible")'"
	z="$g/zap-shader"
	if [ -d "$z" ]; then
		zs=$(strprop "$z/status")
		echo "DT zap-shader child: present status='${zs:-(absent = okay)}' firmware-name='$(strprop "$z/firmware-name")' memory-region(phandle)=$(hexprop "$z/memory-region")"
	else
		echo "DT zap-shader child: ABSENT (the driver would then write RBBM_SECVID_TRUST_CNTL itself: docs/11 section 5)"
	fi
done
[ "$ngpu" = 1 ] || echo "DT gpu node: not found under $PROC/device-tree/soc*"
nres=0
for r in "$PROC"/device-tree/reserved-memory/gpu-micro-code*; do
	[ -d "$r" ] || continue
	nres=1
	echo "DT reserved $(basename "$r"): reg=$(hexprop "$r/reg")"
done
[ "$nres" = 1 ] || echo "DT reserved gpu-micro-code region: absent"
echo "/proc/iomem lines for the zap carveout:"
grep -iE 'gpu|micro-code|9b09a000' "$PROC/iomem" 2>/dev/null || echo "  (none)"

say "5. DRM nodes and devfreq"
if [ -d "$DEVDRI" ]; then ls -l "$DEVDRI" 2>&1 | sed 's/^/  /'; else echo "  no $DEVDRI"; fi
ncards=0
for c in "$SYSFS"/class/drm/card[0-9]* "$SYSFS"/class/drm/renderD[0-9]*; do
	[ -e "$c" ] || continue
	case "$(basename "$c")" in card[0-9]|renderD[0-9]*) ;; *) continue ;; esac
	ncards=1
	echo "$(basename "$c"): driver=$(drvname "$c/device")"
done
[ "$ncards" = 1 ] || echo "(no DRM devices)"
ndf=0
for f in "$SYSFS"/class/devfreq/*; do
	[ -e "$f" ] || continue
	ndf=1
	echo "devfreq $(basename "$f"): governor=$(cat "$f/governor" 2>/dev/null) cur=$(cat "$f/cur_freq" 2>/dev/null) min=$(cat "$f/min_freq" 2>/dev/null) max=$(cat "$f/max_freq" 2>/dev/null) available=$(cat "$f/available_frequencies" 2>/dev/null)"
done
[ "$ndf" = 1 ] || echo "(no devfreq devices)"

say "6. firmware the kernel can find"
echo "under $FWROOT:"
fwfiles "$FWROOT"
echo "staging directories:"
# shellcheck disable=SC2086
for s in $FWSTAGE; do fwfiles "$s"; done

say "6b. the firmware lookup as the kernel loader does it (docs/11 section 9.13)"
echo "The loader tries <dir>/<name> and then <dir>/<name>.xz for these directories, in this order: the firmware_class.path directory, updates/<release>,"
echo "updates, <release>, the root. Shown per view (this shell / pid 1 / pid 2 = the kernel threads) are the lookups that did NOT end in 'no such file',"
echo "each followed by what a read of the path says."
fwdirs="$FWROOT/updates/$UNAME_R $FWROOT/updates $FWROOT/$UNAME_R $FWROOT"
[ -n "$fwp" ] && fwdirs="$fwp $fwdirs"
for view in "this-shell:" "pid1:$PROC/1/root" "pid2-kthreads:$PROC/2/root"; do
	vname=${view%%:*}
	vroot=${view#*:}
	if [ -n "$vroot" ]; then
		echo "[$vname] top level of this view: $(ls -1 "$vroot/" 2>&1 | tr '\n' ' ' | cut -c1-300)"
		echo "[$vname] /lib: $(ls -ld "$vroot/lib" 2>&1)"
	fi
	nno=0
	nall=0
	# shellcheck disable=SC2086
	for d in $fwdirs; do
		for rel in qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/sm8550/a740_zap.mbn; do
			for suffix in "" .xz; do
				p="$vroot$d/$rel$suffix"
				nall=$((nall + 1))
				out=$(ls -ld "$p" 2>&1)
				case "$out" in
				*"No such file"*) nno=$((nno + 1)) ;;
				*)
					echo "  [$vname] $out"
					err=$(cat "$p" 2>&1 >/dev/null)
					if [ -n "$err" ]; then echo "      read fails: $err"; else echo "      read ok"; fi
					;;
				esac
			done
		done
	done
	echo "[$vname] $nno of $nall lookups ended in 'no such file or directory'"
done
echo "-- the path chain (ls -ld) and the symlinks below $FWROOT:"
for p in "$(dirname "$FWROOT")" "$FWROOT" "$fwp" "${fwp:+$fwp/qcom}"; do
	[ -n "$p" ] || continue
	ls -ld "$p" 2>&1 | sed 's/^/  /'
done
nsl=$(find "$FWROOT" -maxdepth 6 -type l 2>/dev/null | wc -l)
echo "  symlinks below $FWROOT: $nsl (first 12)"
find "$FWROOT" -maxdepth 6 -type l 2>/dev/null | head -n 12 | while read -r l; do ls -l "$l" 2>&1 | sed 's/^/    /'; done
loops=$(find -L "$FWROOT" -maxdepth 6 2>&1 >/dev/null | grep -i 'symbolic link' | head -n 5)
if [ -n "$loops" ]; then echo "  SYMLINK LOOPS found by find -L:"; echo "$loops" | sed 's/^/    /'; else echo "  symlink loops below $FWROOT (find -L): none reported"; fi
echo "-- mounts that carry the firmware path:"
[ -r "$PROC/mounts" ] || echo "  (no $PROC/mounts)"
grep -E ' (/|/lib|/usr|/lib/firmware|/lib/firmware/postmarketos) ' "$PROC/mounts" 2>/dev/null | sed 's/^/  /'

say "7. packages and userspace"
echo "installed packages (local apk database, no network):"
"$APK" info -vv 2>/dev/null | grep -iE '^(linux-firmware|firmware-|mesa|libdrm|vulkan|libgbm|libepoxy|kmscube|eglinfo|virglrenderer)' | sort || echo "  (none matched or apk unavailable)"
echo "Mesa msm / freedreno files:"
nmesa=0
for f in "$USRLIB"/dri/msm_dri.so "$USRLIB"/dri/kgsl_dri.so "$USRLIB"/libvulkan_freedreno.so "$USRLIB"/libvulkan_freedreno.so.* "$ICD"/freedreno_icd*.json; do
	[ -e "$f" ] || continue
	nmesa=1
	echo "  $f"
done
[ "$nmesa" = 1 ] || echo "  (none)"
echo "GPU tools in PATH:"
for t in eglinfo vulkaninfo kmscube glxinfo modetest weston-info; do
	if command -v "$t" >/dev/null 2>&1; then echo "  $t: $(command -v "$t")"; else echo "  $t: not installed"; fi
done

say "8. initramfs-extra fingerprint (docs/06 rule 3)"
for f in "$BOOTDIR/initramfs-extra" "$PLASMA_SAVED"; do
	if [ -f "$f" ]; then echo "$(ls -l "$f" | sed 's/  */ /g') sha256=$("$SHA" "$f" 2>/dev/null | cut -d' ' -f1)"; else echo "$f: absent"; fi
done

say "9a. interrupts"
grep -iE 'adreno|a6xx|gmu|gpu|3d00000' "$PROC/interrupts" 2>/dev/null || echo "(none)"

say "9b. clocks (GPU) and power domains"
if [ -r "$DEBUGFS/clk/clk_summary" ]; then grep -E 'gpu_cc|gpu_' "$DEBUGFS/clk/clk_summary" | head -60; else echo "(no clk_summary)"; fi
echo "-- genpd (gpu / cx / gx / mx):"
if [ -r "$DEBUGFS/pm_genpd/pm_genpd_summary" ]; then grep -iE 'gpu|_cx|_gx|^(cx|gx|mx|mmcx)' "$DEBUGFS/pm_genpd/pm_genpd_summary" | head -40; else echo "(no pm_genpd_summary)"; fi

say "9c. deferred probes"
cat "$DEBUGFS/devices_deferred" 2>/dev/null || echo "(no devices_deferred)"

say "9d. dmesg (GPU / SMMU related)"
echo "smmu context faults in dmesg: $("$DMESG" 2>/dev/null | grep -c 'Unhandled context fault')"
echo "'no GPU device was found' lines: $("$DMESG" 2>/dev/null | grep -c 'no GPU device was found')"
"$DMESG" 2>/dev/null | grep -iE 'adreno|a6xx|gmu|gpu_cc|gpucc|kgsl|zap|qcom_pas|PAS is not|auth_and_reset|3d00000|3d6a000|3d90000|3da0000|no GPU|hangcheck|\[drm\]|msm_dpu|failed to load|sqe|coredump' | tail -n 200

say "10. summary"
gdrv="absent"; [ -e "$SYSFS/bus/platform/devices/3d00000.gpu" ] && gdrv="$(drvname "$SYSFS/bus/platform/devices/3d00000.gpu")"
echo "gpu_driver=$gdrv"
ccdrv="absent"; [ -e "$SYSFS/bus/platform/devices/3d90000.clock-controller" ] && ccdrv="$(drvname "$SYSFS/bus/platform/devices/3d90000.clock-controller")"
echo "gpucc_driver=$ccdrv"
smdrv="absent"; [ -e "$SYSFS/bus/platform/devices/3da0000.iommu" ] && smdrv="$(drvname "$SYSFS/bus/platform/devices/3da0000.iommu")"
echo "adreno_smmu_driver=$smdrv"
rn=no
for n in "$DEVDRI"/renderD*; do [ -e "$n" ] && rn=yes; done
echo "render_node_present=$rn"
for f in a740_sqe.fw gmu_gen70200.bin; do
	have=no
	for d in "$FWROOT/qcom" "$FWROOT" $FWSTAGE; do [ -f "$d/$f" ] && have=yes; done
	echo "firmware_$f=$have"
done
zap=no
for d in "$FWROOT" $FWSTAGE; do
	if find "$d" -maxdepth 6 -name 'a740_zap*' 2>/dev/null | grep -q .; then zap=yes; fi
done
echo "firmware_zap_files=$zap"
echo "dmesg_gpu_errors=$("$DMESG" 2>/dev/null | grep -ciE 'adreno.*(fail|error|unable)|gmu.*(fail|error|timeout)|hangcheck|zap.*(fail|unable)|Unable to (load|authorize)')"

echo
echo "done"
