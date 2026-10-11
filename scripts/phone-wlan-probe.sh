#!/bin/sh
# Read-only WLAN / PCIe / power-sequencing state probe -- run ON THE PHONE (pmOS).
#
# Normally via scripts/collect-phone-state.sh (which also saves full dmesg / journalctl -k / debugfs dumps).
# By hand, from the PC on the phone's USB network:
#   scp scripts/phone-wlan-probe.sh user@172.16.42.1:/tmp/
#   ssh -t user@172.16.42.1 'sudo sh /tmp/phone-wlan-probe.sh' | tr -d '\r' | tee notes/<dir>/phone-probe.txt
#
# Changes nothing except mounting debugfs when it is not mounted. Every section is
# guarded, so a missing tool or file just prints a note. Needs root for the debugfs bits.
#
# What it answers (docs/07-wlan-bringup.md, sections 8-13):
#   - did the modules load, is lockdown off, is the kernel tainted only by the unsigned-module flag
#   - did pwrseq-qcom-wcn / pci-pwrctrl-pwrseq bind, did the endpoint (17cb:1103) show up
#   - which voltage is each PMU input rail actually set to (section 13: they sit at their DT *minimum*)
#   - are the WLAN/BT enable, XO-clock and PERST/WAKE/CLKREQ pins where the sequence says they should be
#   - is the PCIe link still alive (live config-space reads of root port and endpoint)
#   - is the ath11k firmware installed, did ath11k probe, what did it say about firmware / board data
sec() { printf '\n##### %s\n' "$*"; }
run() { printf '$ %s\n' "$1"; sh -c "$1" 2>&1 | head -n "${2:-60}"; }
hexdump_n() { # file nbytes -> one line of hex (live read, so all-ff means the link/device is gone)
	if command -v od >/dev/null 2>&1; then od -An -v -tx1 -N "$2" "$1" 2>&1 | tr -d ' \n'; echo
	elif command -v xxd >/dev/null 2>&1; then xxd -p -l "$2" "$1" 2>&1 | tr -d '\n'; echo
	else echo "(no od/xxd)"; fi
}

[ "$(id -u)" = 0 ] || echo "NOTE: not root -- debugfs sections will be empty (rerun with sudo)"
mount | grep -q ' /sys/kernel/debug ' || mount -t debugfs none /sys/kernel/debug 2>/dev/null

sec "identity"
run "date -u; uname -a"
run "cat /sys/kernel/security/lockdown"                 # expect: [none] integrity confidentiality
run "cat /proc/sys/kernel/tainted"                      # 8708 = unsigned module (E, 8192) + WARN (512) + CPU out of spec (4): expected
run "tr ' ' '\n' < /proc/cmdline | grep -E 'lockdown|module|loop|iommu|pci|aspm|dyndbg'"

sec "modules"
run "lsmod | grep -E 'pwrseq|pwrctrl|ath11k|cfg80211|mac80211|qrtr|mhi|rfkill|qmp_pcie'" 40

sec "packages and firmware on the phone"
run "apk info -v 2>/dev/null | grep -E 'firmware|ath11k|wpa_supplicant|iwd|networkmanager-wifi|wireless-regdb|^iw-|pciutils'" 40
run "ls -la /usr/lib/firmware/ath11k/WCN6855/hw2.1 /usr/lib/firmware/ath11k/WCN6855/hw2.0" 40

sec "power sequencing / pwrctrl devices and drivers"
run "ls /sys/bus/platform/devices | grep -i -E 'wifi|pwrctrl|pmu|wcn'"
run "ls -l /sys/bus/platform/drivers/pci-pwrctrl-pwrseq/ /sys/bus/platform/drivers/pwrseq-qcom_wcn/ | grep -v '^total'" 40

sec "PCI devices (the QCA6490 should be 0000:01:00.0, 17cb:1103)"
run "for d in /sys/bus/pci/devices/*; do [ -e \"\$d\" ] || continue; printf '%s vendor=%s device=%s subsys=%s:%s class=%s driver=%s\n' \"\$(basename \$d)\" \"\$(cat \$d/vendor)\" \"\$(cat \$d/device)\" \"\$(cat \$d/subsystem_vendor 2>/dev/null)\" \"\$(cat \$d/subsystem_device 2>/dev/null)\" \"\$(cat \$d/class)\" \"\$(basename \"\$(readlink \$d/driver 2>/dev/null)\" 2>/dev/null)\"; done"

sec "PCIe link: LIVE config-space reads (all-ff = link or device gone) and sysfs link attributes"
for d in 0000:00:00.0 0000:01:00.0; do
	printf '%s first 64 bytes: ' "$d"; hexdump_n "/sys/bus/pci/devices/$d/config" 64
	for a in current_link_speed current_link_width max_link_speed max_link_width enable power/runtime_status; do
		printf '  %s/%s: %s\n' "$d" "$a" "$(cat /sys/bus/pci/devices/$d/$a 2>&1)"
	done
done
printf 'root port bytes 0x70-0x9f (PCIe capability: LnkCap/LnkCtl/LnkSta live): '
od -An -v -tx1 -j 112 -N 48 /sys/bus/pci/devices/0000:00:00.0/config 2>&1 | tr -d ' \n'; echo

sec "deferred probes (debugfs)"
run "cat /sys/kernel/debug/devices_deferred" 40

sec "IOMMU / DMA path of the endpoint (the BHI image transfer is the chip DMA-reading host memory)"
run "ls -l /sys/bus/pci/devices/0000:01:00.0/iommu_group; cat /sys/bus/pci/devices/0000:01:00.0/iommu_group/type; ls /sys/bus/pci/devices/0000:01:00.0/iommu_group/devices" 12
run "dmesg | grep -i -E 'iommu: Default domain|Adding to iommu group 5|arm-smmu 15000000|apps_smmu'" 12
run "cat /proc/sys/kernel/dmesg_restrict; grep -E 'MemTotal|CmaTotal' /proc/meminfo" 6
printf 'live DT of the PCIe controller, one 8-digit group per cell (docs/07 section 14: 4 cells per iommu-map entry = legacy form, 5 = the form 7.3-rc3 mis-parses):\n'
for p in iommu-map msi-map; do
	f=/proc/device-tree/soc@0/pcie@1c00000/$p
	printf '  %s: ' "$p"
	if [ -e "$f" ]; then od -An -v -tx1 "$f" | tr -d ' \n' | sed 's/\(........\)/\1 /g'; echo; else echo "(missing)"; fi
done

sec "GPIO consumers (every line with a consumer label) and the WLAN/BT pin ownership"
run "grep -E '^gpiochip|\\|[A-Za-z0-9_@:.-]' /sys/kernel/debug/gpio" 80
run "grep -h -E 'pin (80|81|82|94|95|96|204) ' /sys/kernel/debug/pinctrl/*/pinmux-pins" 20

sec "regulators the PMU asked for (debugfs regulator_summary excerpt; columns: use open bypass mode voltage current min max)"
run "grep -i -E 'wcn|pmu|wifi|wlan|pwrseq|s2g|s4e|s4g|s6g|l15b' /sys/kernel/debug/regulator/regulator_summary" 60
run "dmesg | grep -E 'vreg_(s2g|s4e|s4g|s6g|l15b).*(Setting|supply)'" 20

sec "kernel log, WLAN-relevant lines only (full logs: scripts/collect-phone-state.sh saves them)"
run "dmesg | grep -i -E 'pwrseq|pwrctrl|wcn6855|wifi|ath11k|qca6490|17cb|0000:01|qcom-pcie|link (up|not|down)|Device not found|mhi|qrtr|firmware|board|qmi|cfg80211|regdb|nl80211' | grep -v -E 'calling  |initcall '" 160
run "dmesg | grep -i -E 'smmu|iommu.*fault|context fault|iommu-map|1-cell entries|Malformed|AER|pcieport|SError|Unhandled fault|rpmh|synchronous external abort'" 40

sec "network side"
run "ip -br link"
run "rfkill list 2>&1" 20
run "nmcli -t device 2>&1" 20
run "iw dev 2>&1; iw phy 2>&1 | head -n 12" 30

sec "wifi: capabilities, regulatory domain, scan (read-only: nothing is connected, configured or changed)"
run "iw phy phy0 info 2>&1 | grep -E 'Band [0-9]|MHz|Supported interface modes|[*] (managed|AP|P2P-client|P2P-GO|P2P-device|monitor)|HE Iftypes|VHT Capabilities|HT Capability'" 80
run "iw reg get 2>&1" 20
run "nmcli -t -f IN-USE,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY device wifi list --rescan yes 2>&1" 60
run "iw dev wlan0 get power_save 2>&1; iw dev wlan0 link 2>&1" 20
run "iw dev wlan0 station dump 2>&1" 40
run "ip -s link show wlan0 2>&1; ip route 2>&1; ip neigh 2>&1" 40
run "cat /etc/resolv.conf 2>&1; nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show wlan0 2>&1" 30
run "gw=\$(ip route | awk '/^default/ {print \$3; exit}'); echo gateway=\$gw; [ -n \"\$gw\" ] && ping -c 20 -i 0.3 -W 1 \"\$gw\" 2>&1 | tail -n 4" 40
run "dmesg | grep -E 'ath11k|wlan0|cfg80211|ieee80211' | grep -v -E 'calling  |initcall ' | tail -n 30" 40
