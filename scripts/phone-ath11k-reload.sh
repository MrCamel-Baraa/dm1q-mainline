#!/bin/sh
# Reload ath11k_pci with MHI / ath11k debug output on and sample the PCIe link every 2 s while
# it fails -- run ON THE PHONE as root (normally via scripts/collect-phone-state.sh --reload).
#
# Purpose (docs/07 section 13): the boot-time failure is "mhi mhi0: Device link is not accessible /
# MHI did not enter READY state" 22 s after MHI power-on, with nothing in between. This re-runs the
# probe with the MHI core's dev_dbg messages enabled (needs CONFIG_DYNAMIC_DEBUG) and records whether
# the endpoint still answers config reads (all-ff = link gone) at each step, so we can tell
# "link dropped" from "chip alive but boot ROM stuck" (the latter is what an under-volted core does).
#
# Safe: it only unloads/reloads ath11k_pci, which currently has no device bound (probe failed).
sampler() { # label
	t="$(cut -d' ' -f1 /proc/uptime)"
	printf '== %s (uptime %s)\n' "$1" "$t"
	for d in 0000:00:00.0 0000:01:00.0; do
		printf '   %s cfg[0:16]: ' "$d"; od -An -v -tx1 -N 16 "/sys/bus/pci/devices/$d/config" 2>&1 | tr -d ' \n'; echo
	done
	printf '   root port PCIe cap [0x70:0x9f]: '; od -An -v -tx1 -j 112 -N 48 /sys/bus/pci/devices/0000:00:00.0/config 2>&1 | tr -d ' \n'; echo
	printf '   ep link: %s x%s | runtime_status: %s\n' "$(cat /sys/bus/pci/devices/0000:01:00.0/current_link_speed 2>&1)" "$(cat /sys/bus/pci/devices/0000:01:00.0/current_link_width 2>&1)" "$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>&1)"
}

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
mount | grep -q ' /sys/kernel/debug ' || mount -t debugfs none /sys/kernel/debug 2>/dev/null
DD=/sys/kernel/debug/dynamic_debug/control
if [ -e "$DD" ]; then
	for m in mhi ath11k_pci ath11k qrtr; do echo "module $m +pflmt" > "$DD" 2>&1 && echo "dynamic debug on for $m"; done
else
	echo "no $DD (CONFIG_DYNAMIC_DEBUG off): only the messages that are printed unconditionally will show"
fi

echo "RELOAD-MARK before unload" > /dev/kmsg
sampler "before unload"
modprobe -r ath11k_pci 2>&1; modprobe -r ath11k 2>&1
lsmod | grep -E 'ath11k|mhi' | head -5

echo "RELOAD-MARK loading ath11k (debug_mask=0xffffffff if supported)" > /dev/kmsg
modprobe ath11k debug_mask=0xffffffff 2>&1 || modprobe ath11k 2>&1
modprobe ath11k_pci 2>&1 &
i=0
while [ $i -lt 15 ]; do
	sampler "t+$((i * 2)) s after modprobe"
	sleep 2; i=$((i + 1))
done
wait

echo
echo "##### kernel messages since the mark"
dmesg | sed -n '/RELOAD-MARK before unload/,$p' | grep -v -E 'calling  |initcall ' | head -n 300
