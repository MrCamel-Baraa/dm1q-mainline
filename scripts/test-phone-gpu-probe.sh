#!/usr/bin/env bash
# PC-side test of scripts/phone-gpu-probe.sh (docs/06 rule 3). The phone's /proc, /sys, debugfs, module tree, /dev/dri,
# firmware tree, lsmod, dmesg and apk are replaced by a scratch tree through the script's env overrides; the script
# runs with dash (closest to the phone's busybox ash: no bashisms allowed; skipped when not installed) and with bash.
# Safety assertions: the probe must NOT open any /dev/dri node (renderD128 is a FIFO: an open() would block, and the
# run is killed by `timeout`), must not call modprobe/insmod/rmmod/mount/umount/reboot/rm/mv/cp/dd (stubs that leave a
# marker), and must not change a single file of the scratch tree. Two scenarios:
#   full   GPU bound, firmware present (root + staging), zap-shader DT child, devfreq, Mesa, config.gz, dmesg errors
#   bare   nothing there (no GPU node, no firmware, no config.gz, no debugfs): every section still prints, no crash
# Usage: bash scripts/test-phone-gpu-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

mk_bin() { # $1 = root: dmesg, lsmod, apk stubs + tripwire stubs
	mkdir -p "$1/bin"
	printf '#!/bin/sh\ncat "%s/dmesg.txt"\n' "$1" > "$1/bin/dmesg"
	printf '#!/bin/sh\ncat "%s/lsmod.txt"\n' "$1" > "$1/bin/lsmod"
	printf '#!/bin/sh\n[ "$1" = info ] && cat "%s/apk-info.txt"\nexit 0\n' "$1" > "$1/bin/apk"
	chmod +x "$1/bin/dmesg" "$1/bin/lsmod" "$1/bin/apk"
	for t in modprobe insmod rmmod mount umount reboot rm mv cp dd; do
		printf '#!/bin/sh\necho "%s $*" >> "%s/CALLED"\nexit 99\n' "$t" "$1" > "$1/bin/$t"
		chmod +x "$1/bin/$t"
	done
}

# ---------------------------------------------------------------- scenario full
F="$W/full"; mkdir -p "$F"; mk_bin "$F"
mkdir -p "$F/proc/sys/kernel" "$F/sys/module/firmware_class/parameters" "$F/sys/module/msm/parameters" \
	"$F/sys/drivers-real/adreno" "$F/sys/drivers-real/gpu_cc-sm8550" "$F/sys/drivers-real/arm-smmu" "$F/sys/drivers-real/msm_dpu" \
	"$F/dbg/clk" "$F/dbg/pm_genpd" "$F/dri" "$F/boot" "$F/root/plasma" "$F/stage/qcom/sm8550/Samsung/dm1q" "$F/fw/qcom" \
	"$F/usr/lib/dri" "$F/usr/share/icd" "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/msm" "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/clk/qcom"
echo "console=ttyMSM0 regulator_ignore_unused msm.separate_gpu_kms=0" > "$F/proc/cmdline"
printf 'CONFIG_DRM_MSM=m\nCONFIG_SM_GPUCC_8550=m\nCONFIG_QCOM_PAS=y\n# CONFIG_ARM_SMMU_QCOM_DEBUG is not set\nCONFIG_UNRELATED=y\nCONFIG_FW_LOADER_USER_HELPER=y\n' | gzip > "$F/proc/config.gz"
: > "$F/sys/module/firmware_class/parameters/path"
echo N > "$F/sys/module/msm/parameters/separate_gpu_kms"
touch "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/gpu/drm/msm/msm.ko.zst" "$F/mod/7.3.0-rc3-dm1q/kernel/drivers/clk/qcom/gpucc-sm8550.ko.zst"
printf 'msm 1 0\nsnd 1 0\ngpu_sched 1 1 msm\n' > "$F/lsmod.txt"
# platform devices: gpu bound to adreno, gpucc bound, smmu bound, gmu present but unbound and waiting
for d in 3d00000.gpu 3d90000.clock-controller 3da0000.iommu 3d6a000.gmu ae00000.display-subsystem; do
	mkdir -p "$F/sys/bus/platform/devices/$d/of_node"
done
ln -s "$F/sys/drivers-real/adreno" "$F/sys/bus/platform/devices/3d00000.gpu/driver"
ln -s "$F/sys/drivers-real/gpu_cc-sm8550" "$F/sys/bus/platform/devices/3d90000.clock-controller/driver"
ln -s "$F/sys/drivers-real/arm-smmu" "$F/sys/bus/platform/devices/3da0000.iommu/driver"
ln -s "$F/sys/drivers-real/msm_dpu" "$F/sys/bus/platform/devices/ae00000.display-subsystem/driver"
printf 'okay\000' > "$F/sys/bus/platform/devices/3d00000.gpu/of_node/status"
echo 1 > "$F/sys/bus/platform/devices/3d6a000.gmu/waiting_for_supplier"
# DT
G="$F/proc/device-tree/soc@0/gpu@3d00000"; mkdir -p "$G/zap-shader" "$F/proc/device-tree/reserved-memory/gpu-micro-code-region@9b09a000"
printf 'okay\000' > "$G/status"
printf 'qcom,adreno-43050a01\000qcom,adreno\000' > "$G/compatible"
printf 'qcom/sm8550/Samsung/dm1q/a740_zap.mdt\000' > "$G/zap-shader/firmware-name"
printf '\000\000\000\132' > "$G/zap-shader/memory-region"
printf '\000\000\000\000\233\011\240\000\000\000\000\000\000\000\040\000' > "$F/proc/device-tree/reserved-memory/gpu-micro-code-region@9b09a000/reg"
printf '9b09a000-9b09bfff : gpu-micro-code-region@9b09a000\n9c900000-9e8fffff : cdsp_region@9c900000\n' > "$F/proc/iomem"
printf ' 300:  0  GICv3 300 Level  adreno\n 301:  5  GICv3 301 Level  unrelated-irq\n' > "$F/proc/interrupts"
# DRM: the render node is a FIFO tripwire (an open() would block forever)
touch "$F/dri/card1"; mkfifo "$F/dri/renderD128"
mkdir -p "$F/sys/class/drm/card1/device" "$F/sys/class/drm/renderD128/device" "$F/sys/class/drm/card1-DSI-1"
ln -s "$F/sys/drivers-real/msm_dpu" "$F/sys/class/drm/card1/device/driver"
ln -s "$F/sys/drivers-real/msm_dpu" "$F/sys/class/drm/renderD128/device/driver"
mkdir -p "$F/sys/class/devfreq/3d00000.gpu"
echo simple_ondemand > "$F/sys/class/devfreq/3d00000.gpu/governor"; echo 220000000 > "$F/sys/class/devfreq/3d00000.gpu/cur_freq"
echo 220000000 > "$F/sys/class/devfreq/3d00000.gpu/min_freq"; echo 680000000 > "$F/sys/class/devfreq/3d00000.gpu/max_freq"
echo "220000000 295000000 680000000" > "$F/sys/class/devfreq/3d00000.gpu/available_frequencies"
# firmware: root tree and a staging tree
printf 'abcdefg' > "$F/fw/qcom/a740_sqe.fw"; printf 'hijklmnop' > "$F/fw/qcom/gmu_gen70200.bin"; printf 'unrelated' > "$F/fw/qcom/other.bin"
printf 'mdt' > "$F/stage/qcom/sm8550/Samsung/dm1q/a740_zap.mdt"; printf 'b00' > "$F/stage/qcom/sm8550/Samsung/dm1q/a740_zap.b00"
# packages and userspace
printf 'mesa-dri-gallium-26.2.4-r0 - Mesa DRI drivers\nlinux-firmware-ath11k-20260810-r0 - firmware\nbash-5.3-r0 - unrelated shell\n' > "$F/apk-info.txt"
touch "$F/usr/lib/dri/msm_dri.so" "$F/usr/share/icd/freedreno_icd.aarch64.json"
printf '#!/bin/sh\n' > "$F/bin/kmscube"; chmod +x "$F/bin/kmscube"
# initramfs-extra baseline
printf 'cpio-bytes' > "$F/boot/initramfs-extra"
# debugfs
echo " gpu_cc_gmu_clk    1  1  0  200000000" > "$F/dbg/clk/clk_summary"
echo " unrelated_clk     1  1  0  1" >> "$F/dbg/clk/clk_summary"
printf 'gpu_cc_cx_gdsc  on  0\nmmcx  on  0\nunrelated_pd  off  0\n' > "$F/dbg/pm_genpd/pm_genpd_summary"
echo "3d6a000.gmu  waiting for supplier" > "$F/dbg/devices_deferred"
printf '[1.0] unrelated line\n[2.0] adreno 3d00000.gpu: failed to load a740_sqe.fw\n[2.1] msm_dpu ae01000.display-controller: no GPU device was found\n[0.3] arm-smmu 3da0000.iommu: Unhandled context fault: fsr=0x402\n[3.0] [drm] Initialized msm 1.13.0 for ae01000.display-controller on minor 1\n' > "$F/dmesg.txt"

run_full() { # shell
	timeout 20 env PATH="$F/bin:$PATH" SYSFS="$F/sys" DEBUGFS="$F/dbg" PROC="$F/proc" DMESG="$F/bin/dmesg" LSMOD="$F/bin/lsmod" \
		MODROOT="$F/mod" UNAME_R=7.3.0-rc3-dm1q ZCAT=zcat FWROOT="$F/fw" FWSTAGE="$F/stage $F/nonexistent" BOOTDIR="$F/boot" \
		PLASMA_SAVED="$F/root/plasma/initramfs-extra.pre-plasma" APK="$F/bin/apk" DEVDRI="$F/dri" USRLIB="$F/usr/lib" ICD="$F/usr/share/icd" \
		"$1" "$HERE/phone-gpu-probe.sh" > "$W/out-full" 2>&1
}

# ---------------------------------------------------------------- scenario bare
B="$W/bare"; mkdir -p "$B/proc"; mk_bin "$B"
echo "console=ttyMSM0" > "$B/proc/cmdline"
: > "$B/lsmod.txt"; : > "$B/dmesg.txt"; : > "$B/apk-info.txt"
run_bare() {
	timeout 20 env PATH="$B/bin:$PATH" SYSFS="$B/sys" DEBUGFS="$B/nodbg" PROC="$B/proc" DMESG="$B/bin/dmesg" LSMOD="$B/bin/lsmod" \
		MODROOT="$B/nomod" UNAME_R=7.3.0-rc3-dm1q ZCAT=zcat FWROOT="$B/nofw" FWSTAGE="$B/stage1 $B/stage2" BOOTDIR="$B/noboot" \
		PLASMA_SAVED="$B/none" APK="$B/bin/apk" DEVDRI="$B/nodri" USRLIB="$B/nousr" ICD="$B/noicd" \
		"$1" "$HERE/phone-gpu-probe.sh" > "$W/out-bare" 2>&1
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
	( cd "$F" && find . | sort && find . -type f -exec cksum {} + | sort ) > "$W/tree-before" 2>/dev/null
	rm -f "$F/CALLED"
	run_full "$sh"; rc=$?
	[ "$rc" = 0 ] && ok "exits 0" || bad "exit status $rc (124 = timeout: the probe tried to open a DRM node?)"
	( cd "$F" && find . | sort && find . -type f -exec cksum {} + | sort ) > "$W/tree-after" 2>/dev/null
	cmp -s "$W/tree-before" "$W/tree-after" && ok "scratch tree unchanged (nothing written)" || bad "the probe changed the scratch tree"
	[ ! -e "$F/CALLED" ] && ok "no modprobe/insmod/rmmod/mount/umount/reboot/rm/mv/cp/dd call" || bad "forbidden command called: $(cat "$F/CALLED")"
	O="$W/out-full"
	expect "$O" "cmdline flag present" "cmdline has regulator_ignore_unused"
	expect "$O" "cmdline flag absent" "cmdline lacks clk_ignore_unused"
	expect "$O" "msm. param seen in cmdline" "cmdline has msm\\."
	expect "$O" "no module blacklist" "cmdline lacks modprobe\\.blacklist"
	expect "$O" "firmware_class.path shown (empty)" "firmware_class\\.path \\(custom search dir\\): ''"
	expect "$O" "config line kept" "CONFIG_SM_GPUCC_8550=m"
	expect "$O" "PAS config kept" "CONFIG_QCOM_PAS=y"
	expect "$O" "'not set' kept" "# CONFIG_ARM_SMMU_QCOM_DEBUG is not set"
	reject "$O" "unrelated config dropped" "CONFIG_UNRELATED"
	expect "$O" "msm.ko on disk" "msm\\.ko"
	expect "$O" "gpucc module on disk" "gpucc-sm8550\\.ko"
	expect "$O" "loaded msm" "^msm 1 0"
	expect "$O" "loaded gpu_sched" "^gpu_sched 1 1 msm"
	reject "$O" "unrelated module dropped" "^snd "
	expect "$O" "msm parameter" "separate_gpu_kms=N"
	expect "$O" "gpu driver" "3d00000\\.gpu: driver=adreno dt-status=okay"
	expect "$O" "gpucc driver" "3d90000\\.clock-controller: driver=gpu_cc-sm8550"
	expect "$O" "smmu driver" "3da0000\\.iommu: driver=arm-smmu"
	expect "$O" "gmu unbound and waiting" "3d6a000\\.gmu: driver=no driver .*waiting_for_supplier=1"
	expect "$O" "DT gpu node" "DT gpu node: status='okay' compatible='qcom,adreno-43050a01 qcom,adreno'"
	expect "$O" "DT zap child firmware-name" "firmware-name='qcom/sm8550/Samsung/dm1q/a740_zap\\.mdt'"
	expect "$O" "DT zap memory-region" "memory-region\\(phandle\\)=[[:space:]]*00 00 00 5a"
	expect "$O" "DT reserved region reg" "gpu-micro-code-region@9b09a000: reg=[[:space:]]*00 00 00 00 9b 09 a0 00 00 00 00 00 00 00 20 00"
	expect "$O" "iomem line" "9b09a000-9b09bfff : gpu-micro-code-region"
	reject "$O" "iomem unrelated dropped" "cdsp_region"
	expect "$O" "dri listing has render node" "renderD128"
	expect "$O" "drm card driver" "card1: driver=msm_dpu"
	expect "$O" "drm render driver" "renderD128: driver=msm_dpu"
	expect "$O" "devfreq" "devfreq 3d00000\\.gpu: governor=simple_ondemand cur=220000000 min=220000000 max=680000000 available=220000000 295000000 680000000"
	expect "$O" "root firmware sqe" "fw/qcom/a740_sqe\\.fw 7 bytes sha256=[0-9a-f]{64}"
	expect "$O" "root firmware gmu" "fw/qcom/gmu_gen70200\\.bin 9 bytes sha256=[0-9a-f]{64}"
	reject "$O" "unrelated firmware dropped" "other\\.bin"
	expect "$O" "staging zap mdt" "stage/qcom/sm8550/Samsung/dm1q/a740_zap\\.mdt 3 bytes sha256=[0-9a-f]{64}"
	expect "$O" "staging zap b00" "a740_zap\\.b00 3 bytes"
	expect "$O" "missing staging dir reported" "nonexistent: no such directory"
	expect "$O" "package kept" "^mesa-dri-gallium-26\\.2\\.4-r0"
	expect "$O" "firmware package kept" "^linux-firmware-ath11k"
	reject "$O" "unrelated package dropped" "^bash-"
	expect "$O" "mesa msm file" "usr/lib/dri/msm_dri\\.so"
	expect "$O" "vulkan icd file" "freedreno_icd\\.aarch64\\.json"
	expect "$O" "tool found" "kmscube: .*/bin/kmscube"
	expect "$O" "initramfs-extra fingerprint" "initramfs-extra.* sha256=[0-9a-f]{64}"
	expect "$O" "saved initramfs-extra absent" "initramfs-extra\\.pre-plasma: absent"
	expect "$O" "interrupt line" "adreno"
	reject "$O" "interrupt unrelated dropped" "unrelated-irq"
	expect "$O" "gpu clock" "gpu_cc_gmu_clk"
	reject "$O" "unrelated clock dropped" "unrelated_clk"
	expect "$O" "genpd gpu" "gpu_cc_cx_gdsc"
	expect "$O" "deferred" "3d6a000\\.gmu"
	expect "$O" "smmu fault count" "smmu context faults in dmesg: 1"
	expect "$O" "no-GPU line count" "'no GPU device was found' lines: 1"
	expect "$O" "dmesg adreno line" "failed to load a740_sqe\\.fw"
	expect "$O" "dmesg drm line" "Initialized msm 1\\.13\\.0"
	reject "$O" "dmesg unrelated dropped" "unrelated line"
	expect "$O" "summary gpu driver" "^gpu_driver=adreno$"
	expect "$O" "summary gpucc" "^gpucc_driver=gpu_cc-sm8550$"
	expect "$O" "summary smmu" "^adreno_smmu_driver=arm-smmu$"
	expect "$O" "summary render node" "^render_node_present=yes$"
	expect "$O" "summary sqe" "^firmware_a740_sqe\\.fw=yes$"
	expect "$O" "summary gmu" "^firmware_gmu_gen70200\\.bin=yes$"
	expect "$O" "summary zap" "^firmware_zap_files=yes$"
	expect "$O" "summary error count" "^dmesg_gpu_errors=1$"
	expect "$O" "ends with done" "^done$"

	echo "== $sh, scenario bare"
	( cd "$B" && find . | sort ) > "$W/tree-before-b" 2>/dev/null
	rm -f "$B/CALLED"
	run_bare "$sh"; rc=$?
	[ "$rc" = 0 ] && ok "exits 0 (bare)" || bad "exit status $rc (bare)"
	( cd "$B" && find . | sort ) > "$W/tree-after-b" 2>/dev/null
	cmp -s "$W/tree-before-b" "$W/tree-after-b" && ok "bare tree unchanged" || bad "the probe changed the bare tree"
	[ ! -e "$B/CALLED" ] && ok "no forbidden command (bare)" || bad "forbidden command called (bare)"
	O="$W/out-bare"
	expect "$O" "no config.gz message" "NO .*config\\.gz"
	expect "$O" "no module dir message" "no .*7\\.3\\.0-rc3-dm1q"
	expect "$O" "firmware_class.path unreadable" "firmware_class\\.path: unreadable"
	expect "$O" "gpu device absent" "3d00000\\.gpu: absent"
	expect "$O" "DT gpu node not found" "DT gpu node: not found"
	expect "$O" "DT reserved region absent" "DT reserved gpu-micro-code region: absent"
	expect "$O" "no dri dir" "no .*nodri"
	expect "$O" "no drm devices" "\\(no DRM devices\\)"
	expect "$O" "no devfreq" "\\(no devfreq devices\\)"
	expect "$O" "firmware root missing" "nofw: no such directory"
	expect "$O" "staging dirs missing" "stage1: no such directory"
	expect "$O" "no mesa files" "^  \\(none\\)$"
	expect "$O" "no clk_summary" "\\(no clk_summary\\)"
	expect "$O" "no genpd" "\\(no pm_genpd_summary\\)"
	expect "$O" "no devices_deferred" "\\(no devices_deferred\\)"
	expect "$O" "bare: zero smmu faults" "smmu context faults in dmesg: 0"
	expect "$O" "summary gpu absent" "^gpu_driver=absent$"
	expect "$O" "summary render node no" "^render_node_present=no$"
	expect "$O" "summary sqe no" "^firmware_a740_sqe\\.fw=no$"
	expect "$O" "summary zap no" "^firmware_zap_files=no$"
	expect "$O" "summary errors 0" "^dmesg_gpu_errors=0$"
	expect "$O" "ends with done (bare)" "^done$"
done

echo "== static checks"
bash --posix -n "$HERE/phone-gpu-probe.sh" && ok "bash --posix -n" || bad "bash --posix -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$HERE/phone-gpu-probe.sh" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
