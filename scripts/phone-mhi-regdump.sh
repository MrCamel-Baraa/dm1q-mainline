#!/bin/sh
# Sample the WLAN chip's MHI/BHI registers, the endpoint's MSI state, the interrupt counters and the PCIe
# controller's BDF-to-SID table -- run ON THE PHONE as root (normally via scripts/collect-phone-state.sh --fresh).
#
# VERSION 2 (docs/07 section 14). Version 1 read BAR0 with `dd if=/dev/mem` and every read came out as
# "????????": on arm64 read()/write() on /dev/mem only work inside mapped system RAM (valid_phys_addr_range() in
# arch/arm64/mm/mmap.c), MMIO has to be mmap()ed; and in idle mode nothing had enabled the endpoint's memory space,
# so BAR0 was not decoded at all. This version
#   - reads through $MMIO (/tmp/mmio-read = scripts/mmio-read.c, static aarch64, mmap) and REFUSES TO RUN when a
#     self-test of that helper fails, so a broken instrument can no longer waste an experiment;
#   - switches the endpoint's memory space on itself in idle mode (sysfs "enable", switched off again at the end);
#   - prints a line whenever any sampled register or interrupt counter changes (sampled as fast as the shell can,
#     for the first 6 s) and at least once a second, so every transition is caught;
#   - dumps the endpoint's MSI capability and PCIe capability, the per-vector interrupt counts and the PARF
#     BDF-to-SID table (decode it with scripts/predict-qcom-bdf-sid-table.py --decode).
#
# How to read a sample line (all values hex, straight from the registers):
#   cmd         PCI command register: mem = memory space on, bm = bus master on (the chip needs both for DMA)
#   MHI[...]    LEN VER CFG  BHIOFF BHIEOFF  CTRL (RESET bit1, MHISTATE 15:8)  STATUS (READY bit0, SYSERR bit2, MHISTATE 15:8)
#   BHI[...]    VER  IMG=<hi>:<lo> SIZE TXDB (what the host handed over: proves the doorbell landed)  INTVEC
#               EXECENV  STATUS  ERR DBG1 DBG2 DBG3 (the boot ROM's own error report)  SERIAL ROLLVER NUMSEG
#   BHIE[...]   TXADDR(hi:lo) TXSIZE TXDB TXSTATUS  (the AMSS download that follows once SBL runs)
#   irq[...]    sum of the interrupt counts of the endpoint's MSI vectors / of the root port's vector
# Decodes (checked against the 7.3-rc3 source: include/linux/mhi.h, drivers/bus/mhi/common.h):
#   EXECENV is enum mhi_ee_type: 0 PBL, 1 SBL, 2 AMSS, 3 RDDM, 4 WFW, 5 PTHRU, 6 EDL, 7 FP
#   BHI STATUS is bits 31:30 only: 0 RESET (nothing done yet), 2 SUCCESS (raw 0x80000000), 3 ERROR (raw 0xc0000000)
#   MHISTATE is enum mhi_state: 0 RESET, 1 READY, 2 M0, 3 M1, 4 M2, 5 M3, 6 M3_FAST, 7 BHI, 0xff SYS_ERR
#   all-ff reads = the chip's MMIO is not answering; EXECENV=PBL with STATUS=RESET and nothing else = boot ROM
#   alive but idle; STATUS=SUCCESS with EXECENV=SBL while the interrupt counters stay 0 = the chip is fine and its
#   interrupts do not reach the host (docs/07 section 14).
#
# Modes:
#   idle    ~10 s of sampling only (use with ath11k_pci blacklisted: the chip sits powered and untouched in PBL)
#   load    modprobe ath11k + ath11k_pci in the background and sample ~36 s: a FRESH attempt -- the representative one
#   reload  modprobe -r ath11k_pci/ath11k first, then as load (the chip is left in whatever state the previous failed
#           attempt left it in; behaves differently from a fresh one, see docs/07 section 13)
#
# Needs: root, $MMIO, /dev/mem (CONFIG_DEVMEM=y, STRICT_DEVMEM allows non-RAM; lockdown none), od, cut, awk, readlink.
# The paths below can be overridden (SYS, PLAT, PROC, MEMDEV, KMSG, MMIO, NSEC = sampling seconds, NOROOT=1):
# scripts/test-phone-mhi-regdump.sh runs this very file against a fake environment on the PC.
# shellcheck disable=SC2046,SC2086,SC2034
MODE="${1:-load}"
MMIO="${MMIO:-/tmp/mmio-read}"
EP="${EP:-0000:01:00.0}"
RP="${RP:-0000:00:00.0}"
SYS="${SYS:-/sys/bus/pci/devices}"
PLAT="${PLAT:-/sys/bus/platform/devices}"
PROC="${PROC:-/proc}"
MEMDEV="${MEMDEV:-/dev/mem}"
KMSG="${KMSG:-/dev/kmsg}"
TMP="${TMPDIR:-/tmp}"

[ "${NOROOT:-0}" = 1 ] || [ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
[ -x "$MMIO" ] || { echo "no executable $MMIO (collect-phone-state.sh copies scripts/bin/mmio-read-aarch64 there; build it with scripts/build-mmio-read.sh)"; exit 1; }
printf '\357\276\255\336\170\126\064\022' > "$TMP/mmio-selftest.bin"
st="$("$MMIO" "$TMP/mmio-selftest.bin" 0 0 4 2>&1)"
rm -f "$TMP/mmio-selftest.bin"
[ "$st" = "deadbeef 12345678" ] || { echo "mmio-read SELF-TEST FAILED (got: $st) -- registers cannot be read, stopping"; exit 1; }
echo "mmio-read self-test: ok"
[ -e "$MEMDEV" ] || { echo "no $MEMDEV"; exit 1; }
BAR="$(sed -n 1p "$SYS/$EP/resource" 2>/dev/null | cut -d' ' -f1)"
[ -n "$BAR" ] || { echo "cannot read BAR0 from $SYS/$EP/resource (is the endpoint enumerated?)"; exit 1; }
BAR=$((BAR))
BARHEX="$(printf '%x' "$BAR")"
echo "mode=$MODE  endpoint $EP  BAR0 physical base 0x$BARHEX  (ath11k_pci loaded: $(grep -c '^ath11k_pci' "$PROC/modules" 2>/dev/null))"

mmio() { "$MMIO" "$MEMDEV" "$@"; }
centis() { # uptime in hundredths of a second (two decimals in /proc/uptime; strip a leading 0 so it is not read as octal)
	u="$(cut -d' ' -f1 "$PROC/uptime")"; cf="${u#*.}"
	case "$cf" in 0?) cf="${cf#0}" ;; esac
	echo $(( ${u%.*} * 100 + cf ))
}
cmdreg() { od -An -v -tx1 -j 4 -N 2 "$SYS/$EP/config" 2>/dev/null | tr -d ' \n'; }
cfgwords() { # offset count -> little-endian dwords of the endpoint's config space, hex, space separated
	od -An -v -tx4 -j "$1" -N "$(( $2 * 4 ))" "$SYS/$EP/config" 2>/dev/null | tr -s ' \n' '  '
}
findcap() { # capability id (2 hex digits) -> its offset in the endpoint's config space (decimal), or nothing
	fc_p="$(od -An -v -tu1 -j 52 -N 1 "$SYS/$EP/config" 2>/dev/null | tr -d ' ')"
	fc_n=0
	while [ -n "$fc_p" ] && [ "$fc_p" -ge 64 ] && [ "$fc_n" -lt 48 ]; do
		set -- $(od -An -v -tx1 -j "$fc_p" -N 2 "$SYS/$EP/config" 2>/dev/null)
		[ "$1" = "$CAPWANT" ] && { echo "$fc_p"; return 0; }
		[ -n "$2" ] || return 1
		fc_p=$((0x$2)); fc_n=$((fc_n + 1))
	done
	return 1
}
irqsum() { # "ep=<sum of the endpoint's MSI vector counts> rp=<root port's>"
	awk '/ITS-PCI-MSI-0000:0[01]:00.0/ {
		s = 0; i = 2
		while ($i ~ /^[0-9]+$/) { s += $i; i++ }
		if ($i ~ /01:00.0/) ep += s; else rp += s
	}
	END { printf "ep=%d rp=%d", ep, rp }' "$PROC/interrupts" 2>/dev/null
}
irqvec() { # per-vector lines
	grep -E 'ITS-PCI-MSI-0000:0[01]:00.0' "$PROC/interrupts" 2>/dev/null | awk '{
		s = 0; i = 2
		while ($i ~ /^[0-9]+$/) { s += $i; i++ }
		name = ""; for (k = i + 3; k <= NF; k++) name = name (name == "" ? "" : " ") $k
		printf "      %s vec %-2s count=%-6d %s\n", $i, $(i + 1), s, name
	}'
}
msistate() {
	CAPWANT=05; m="$(findcap)"
	[ -n "$m" ] || { echo "   msi: no MSI capability in the endpoint's config space"; return 0; }
	set -- $(cfgwords "$m" 6)
	[ -n "$6" ] || { echo "   msi: config space not readable"; return 0; }
	ctl=$(( (0x$1 >> 16) & 0xffff ))
	echo "   msi cap@0x$(printf '%x' "$m"): ctrl=0x$(printf '%04x' "$ctl") enable=$((ctl & 1)) vectors_enabled=$((1 << ((ctl >> 4) & 7)))/$((1 << ((ctl >> 1) & 7))) 64bit=$(( (ctl >> 7) & 1 )) addr=0x$3$2 data=0x$(printf '%04x' $((0x$4 & 0xffff))) mask=0x$5 pending=0x$6"
	CAPWANT=10; e="$(findcap)"
	if [ -n "$e" ]; then
		set -- $(cfgwords "$((e + 8))" 1) $(cfgwords "$((e + 16))" 1)
		echo "   pcie cap@0x$(printf '%x' "$e"): DevSta:DevCtl=0x$1  LnkSta:LnkCtl=0x$2"
	fi
}
aer() {
	for d in $RP $EP; do
		for f in aer_dev_correctable aer_dev_nonfatal aer_dev_fatal; do
			[ -e "$SYS/$d/$f" ] && printf '   %s %s: %s\n' "$d" "$f" "$(tr '\n' ' ' < "$SYS/$d/$f" | cut -c1-160)"
		done
	done
}
cfgdump() { # full 4 KiB config space of both ends, one hex line each, for offline decoding
	for d in $RP $EP; do printf '   cfg %s: ' "$d"; od -An -v -tx1 -N 4096 "$SYS/$d/config" 2>&1 | tr -d ' \n'; echo; done
}
parfdump() { # the PCIe controller's BDF-to-SID table (PARF + 0x2000, 256 words) and BDF_TO_SID_CFG (PARF + 0x2c00)
	ctrl="$(readlink -f "$SYS/$RP" 2>/dev/null | sed -n 's|.*/\([0-9a-f]*\)\.pcie/pci.*|\1|p')"
	[ -n "$ctrl" ] || { echo "   (cannot work out the PCIe controller's address from $SYS/$RP)"; return 0; }
	rs="$(cat "$PLAT/$ctrl.pcie/power/runtime_status" 2>/dev/null)"
	case "$rs" in
	active|unsupported|"") ;;
	*) echo "   PCIe controller $ctrl.pcie runtime status is '$rs': not touching its registers"; return 0 ;;
	esac
	pb=$((0x$ctrl + 0x2000))
	offs=""; i=0
	while [ $i -lt 256 ]; do offs="$offs $(printf '%x' $((i * 4)))"; i=$((i + 1)); done
	r="$(mmio "$(printf '%x' "$pb")" $offs 2>&1)"
	case "$r" in
	ERR*|usage*|"") echo "   PARF table read failed: $r"; return 0 ;;
	esac
	echo "BDF2SID-TABLE-BEGIN  (controller $ctrl.pcie, runtime_status=${rs:-n/a}, 256 words from physical 0x$(printf '%x' "$pb"))"
	echo "$r"
	echo "BDF2SID-TABLE-END"
	echo "   PARF_BDF_TO_SID_CFG (0x$(printf '%x' $((pb + 0xc00))), bit0 = BDF_TO_SID_BYPASS): $(mmio "$(printf '%x' "$pb")" c00 2>&1)"
}

LASTSIG=""; LASTPRINT=0
sample() { # label
	lbl="$1"; tc="$(centis)"; tt="$(cut -d' ' -f1 "$PROC/uptime")"
	[ -e "$SYS/$EP/config" ] || { echo "t=$tt $lbl: endpoint not present"; return 0; }
	c="$(cmdreg)"
	case "$c" in ffff|"") echo "t=$tt $lbl: command register reads '$c' (link or device gone)"; return 0 ;; esac
	lo="${c%"${c#??}"}"; hi="${c#??}"; cmdv=$(( (0x$hi << 8) | 0x$lo ))
	cmds="cmd=0x$(printf '%04x' "$cmdv") mem=$(( (cmdv >> 1) & 1 )) bm=$(( (cmdv >> 2) & 1 ))"
	irq="irq[$(irqsum)]"
	if [ $(( cmdv & 2 )) -eq 0 ]; then
		sig="$cmdv $irq"
		if [ "$sig" != "$LASTSIG" ] || [ $((tc - LASTPRINT)) -ge 100 ]; then
			echo "t=$tt $lbl: $cmds  memory space off, BAR0 not decoded, not reading  $irq"; LASTSIG="$sig"; LASTPRINT=$tc
		fi
		return 0
	fi
	r="$(mmio "$BARHEX" 0 8 10 28 2c 38 48 2>&1)"
	case "$r" in ERR*|usage*|"") echo "t=$tt $lbl: $cmds  MMIO READ FAILED: $r  $irq"; return 0 ;; esac
	set -- $r
	mlen=$1; mver=$2; mcfg=$3; bhioff=$4; bhieoff=$5; mctrl=$6; mstat=$7
	mc=$((0x$mctrl)); ms=$((0x$mstat))
	mhi="MHI[LEN=$mlen VER=$mver CFG=$mcfg BHIOFF=$bhioff BHIEOFF=$bhieoff CTRL=$mctrl(reset=$(( (mc >> 1) & 1 )) state=$(mhistate $(( (mc >> 8) & 255 )))) STATUS=$mstat(ready=$((ms & 1)) syserr=$(( (ms >> 2) & 1 )) state=$(mhistate $(( (ms >> 8) & 255 ))))]"
	bhi=""; bhie=""; bsig=""
	if ! offok "$bhioff"; then
		bhi=" (BHIOFF unusable, BHI not read)"
	else
		b=$((0x$bhioff)); offs=""
		for o in 0 4 8 c 10 18 20 28 2c 30 34 38 3c 40 44 48; do offs="$offs $(printf '%x' $((b + 0x$o)))"; done
		r="$(mmio "$BARHEX" $offs 2>&1)"
		case "$r" in ERR*|usage*|"") bhi=" BHI READ FAILED: $r" ;; *)
			set -- $r; bsig="$r"
			eenum=$((0x$8)); bsn=$(( (0x$9 >> 30) & 3 ))
			bhi=" BHI[VER=$2.$1 IMG=$4:$3 SIZE=$5 TXDB=$6 INTVEC=$7 EXECENV=$8($(eename "$eenum")) STATUS=$9($(bhistatus "$bsn")) ERR=${10} DBG1=${11} DBG2=${12} DBG3=${13} SERIAL=${14} ROLLVER=${15} NUMSEG=${16}]" ;;
		esac
	fi
	if offok "$bhieoff"; then
		be=$((0x$bhieoff)); offs=""
		for o in 2c 30 34 3c 44; do offs="$offs $(printf '%x' $((be + 0x$o)))"; done
		r="$(mmio "$BARHEX" $offs 2>&1)"
		case "$r" in ERR*|usage*|"") ;; *) set -- $r; bsig="$bsig $r"; bhie=" BHIE[TXADDR=$2:$1 TXSIZE=$3 TXDB=$4 TXSTATUS=$5]" ;; esac
	fi
	sig="$cmdv $mlen $mver $mcfg $bhioff $bhieoff $mctrl $mstat $bsig $irq"
	if [ "$sig" != "$LASTSIG" ] || [ $((tc - LASTPRINT)) -ge 100 ]; then
		echo "t=$tt $lbl: $cmds $mhi$bhi$bhie $irq"
		LASTSIG="$sig"; LASTPRINT=$tc
	fi
}
offok() { # hex register-block offset: usable = not all-ones/zero, 4-aligned, below the helper's 1 MiB window
	case "$1" in ffffffff|00000000|"") return 1 ;; esac
	ok_v=$((0x$1)); [ "$ok_v" -lt 1048576 ] && [ $((ok_v & 3)) -eq 0 ]
}
eename() { case "$1" in 0) echo PBL ;; 1) echo SBL ;; 2) echo AMSS ;; 3) echo RDDM ;; 4) echo WFW ;; 5) echo PTHRU ;; 6) echo EDL ;; 7) echo FP ;; *) echo "?" ;; esac; }
bhistatus() { case "$1" in 0) echo RESET ;; 2) echo SUCCESS ;; 3) echo ERROR ;; *) echo "?" ;; esac; }
mhistate() { case "$1" in 0) echo RESET ;; 1) echo READY ;; 2) echo M0 ;; 3) echo M1 ;; 4) echo M2 ;; 5) echo M3 ;; 6) echo M3_FAST ;; 7) echo BHI ;; 255) echo SYS_ERR ;; *) echo "?" ;; esac; }

echo "REGDUMP-MARK start ($MODE)" > "$KMSG" 2>/dev/null
echo "##### AER counters before"; aer
echo "##### interrupts before (per vector)"; irqvec
echo "##### config space before"; cfgdump
echo "##### MSI / PCIe capability before"; msistate
echo "##### PCIe controller BDF-to-SID table"; parfdump

ENABLED_BY_ME=0
N="${NSEC:-36}"
[ "$MODE" = idle ] && N="${NSEC:-10}"
if [ "$MODE" = idle ] && [ "$(cat "$SYS/$EP/enable" 2>/dev/null)" = 0 ]; then
	echo 1 > "$SYS/$EP/enable" 2>/dev/null && ENABLED_BY_ME=1
	echo "idle: switched the endpoint's memory space on through sysfs enable (no driver is bound), will switch it off again"
fi

echo "##### samples (a line whenever anything changes, and at least once a second)"
sample "before"
case "$MODE" in
idle) ;;
reload)
	modprobe -r ath11k_pci 2>&1; modprobe -r ath11k 2>&1
	echo "REGDUMP-MARK modprobe" > "$KMSG" 2>/dev/null
	modprobe ath11k 2>&1
	modprobe ath11k_pci 2>&1 &
	;;
*)
	echo "REGDUMP-MARK modprobe" > "$KMSG" 2>/dev/null
	modprobe ath11k 2>&1
	modprobe ath11k_pci 2>&1 &
	;;
esac
start="$(centis)"; d1=0; d2=0; d3=0
while :; do
	el=$(( $(centis) - start ))
	[ "$el" -ge $((N * 100)) ] && break
	sample "+$((el / 100)).$(printf '%02d' $((el % 100)))s"
	if [ "$d1" = 0 ] && [ "$el" -ge 200 ]; then d1=1; echo "   --- at +${el}cs"; msistate; irqvec; fi
	if [ "$d2" = 0 ] && [ "$el" -ge 800 ]; then d2=1; echo "   --- at +${el}cs"; msistate; irqvec; fi
	if [ "$d3" = 0 ] && [ "$el" -ge 1800 ]; then d3=1; echo "   --- at +${el}cs"; msistate; irqvec; fi
	[ "$el" -lt 600 ] || sleep 1
done
[ "$ENABLED_BY_ME" = 1 ] && echo 0 > "$SYS/$EP/enable" 2>/dev/null
wait
echo "##### interrupts after (per vector)"; irqvec
echo "##### MSI / PCIe capability after"; msistate
echo "##### AER counters after"; aer
echo "##### config space after"; cfgdump
echo
echo "##### kernel messages since the mark"
dmesg 2>/dev/null | sed -n '/REGDUMP-MARK start/,$p' | grep -v -E 'calling  |initcall ' | head -n 200
