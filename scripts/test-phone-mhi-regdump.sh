#!/usr/bin/env bash
# Functional test of scripts/phone-mhi-regdump.sh on the PC: the real script runs (under `bash --posix`, which is the
# closest shell available here to the phone's busybox ash) against a FAKE sysfs / proc / physical-memory file, with
# the real mmio-read source built for the host. The fake chip changes state half-way through a "load" run (a fake
# `modprobe` flips PBL/RESET into SBL/SUCCESS and bumps the root port's interrupt counter), so the change detection,
# the decodes, the MSI/PCIe capability walk, the BDF-to-SID table dump and the refuse-to-run guards are all exercised.
# What this does NOT cover: busybox ash itself, and the real chip. Usage: bash scripts/test-phone-mhi-regdump.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
HOST_OUT="$W/mmio-read-x86_64" bash "$HERE/build-mmio-read.sh" >/dev/null || { echo "build failed"; exit 1; }
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
has() { if grep -q -F -- "$2" "$3"; then ok "$1"; else bad "$1   (missing: $2)"; fi; }
hasnt() { if grep -q -F -- "$2" "$3"; then bad "$1   (unexpected: $2)"; else ok "$1"; fi; }

wr32() { # file byte-offset value-hex : little-endian 32-bit write into a (sparse) file
	local v=$((0x$3))
	printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((v & 255)) $(((v >> 8) & 255)) $(((v >> 16) & 255)) $(((v >> 24) & 255)))" |
		dd of="$1" bs=1 seek=$(($2)) conv=notrunc status=none
}

mkenv() { # dir command-register-hex(4 digits, e.g. 0006) enable-file-content
	local d="$1" cmd="$2" en="$3"
	local rp="$d/sys/devices/platform/soc@0/1c00000.pcie/pci0000:00/0000:00:00.0"
	local ep="$rp/0000:01:00.0"
	mkdir -p "$ep" "$d/sys/bus/pci/devices" "$d/sys/bus/platform/devices/1c00000.pcie/power" "$d/proc" "$d/bin"
	ln -sfn "$rp" "$d/sys/bus/pci/devices/0000:00:00.0"
	ln -sfn "$ep" "$d/sys/bus/pci/devices/0000:01:00.0"
	echo active > "$d/sys/bus/platform/devices/1c00000.pcie/power/runtime_status"
	echo "$en" > "$ep/enable"
	echo "0x0000000060400000 0x00000000605fffff 0x000000000014220c" > "$ep/resource"
	python3 - "$rp/config" "$ep/config" "$cmd" <<'PYEOF'
import struct, sys
rp, ep, cmd = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
b = bytearray(4096)
struct.pack_into("<HHHH", b, 0, 0x17cb, 0x0113, 0x0507, 0x0010)
open(rp, "wb").write(b)
b = bytearray(4096)
struct.pack_into("<HHHH", b, 0, 0x17cb, 0x1103, cmd, 0x0010)
struct.pack_into("<I", b, 0x10, 0x60400004)
struct.pack_into("<B", b, 0x34, 0x40)
struct.pack_into("<BBHH", b, 0x40, 0x01, 0x50, 0xc803, 0x0008)                  # PM cap
struct.pack_into("<BBHIIHHII", b, 0x50, 0x05, 0x70, 0x01db, 0xffa00000, 0, 0x0000, 0, 0, 0)   # MSI cap, 64-bit + masking
struct.pack_into("<BBHIHHIHH", b, 0x70, 0x10, 0x00, 0x0002, 0x8fe0, 0x2810, 0x0010, 0x00423c43, 0x0142, 0x1003)  # PCIe cap
open(ep, "wb").write(b)
PYEOF
	local mem="$d/mem"; truncate -s 2G "$mem"
	local bar=0x60400000 b=0x$(printf '%x' $((0x60400000)))
	wr32 "$mem" $((bar + 0x00)) 00000100; wr32 "$mem" $((bar + 0x08)) 01000000; wr32 "$mem" $((bar + 0x10)) 01000302
	wr32 "$mem" $((bar + 0x28)) 00000200; wr32 "$mem" $((bar + 0x2c)) 00000324          # BHIOFF, BHIEOFF
	wr32 "$mem" $((bar + 0x200 + 0x04)) 00000001; wr32 "$mem" $((bar + 0x200 + 0x40)) 12345678   # BHI version, serial
	# the PARF BDF-to-SID table the 7.3-rc3 driver programs for our DTB: one garbage slot, none for RID 0x0100
	wr32 "$mem" $((0x1c02000 + 7 * 4)) ffed3b00
	{
		echo '172:          0          0          0          0          0          0          0          0  ITS-PCI-MSI-0000:00:00.0    0 Edge      PCIe PME, aerdrv, PCIe bwctrl'
		echo '174:          0          0          0          0          0          0          0          0  ITS-PCI-MSI-0000:01:00.0    0 Edge      bhi'
		echo '175:          0          0          0          0          0          0          0          0  ITS-PCI-MSI-0000:01:00.0    1 Edge      mhi'
		echo '177:          0          0          0          0          0          0          0          0  ITS-PCI-MSI-0000:01:00.0    3 Edge      ce0'
	} > "$d/proc/interrupts"
	ln -sfn /proc/uptime "$d/proc/uptime"; : > "$d/proc/modules"
	cat > "$d/bin/modprobe" <<'MPEOF'
#!/bin/sh
# fake modprobe: ath11k_pci "loads", then half a second later the fake chip boots PBL -> SBL (status success,
# MHI ready) and two interrupts show up on the ROOT PORT's vector, none on the endpoint's (what v8 showed)
[ "$1" = ath11k_pci ] || exit 0
sleep 1
w() { v=$(( 0x$3 )); printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((v & 255)) $(((v >> 8) & 255)) $(((v >> 16) & 255)) $(((v >> 24) & 255)))" | dd of="$1" bs=1 seek=$(( $2 )) conv=notrunc status=none; }
w "$FAKE_MEM" $((0x60400000 + 0x200 + 0x08)) 12340000; w "$FAKE_MEM" $((0x60400000 + 0x200 + 0x10)) 00080000
w "$FAKE_MEM" $((0x60400000 + 0x200 + 0x18)) 00000001; w "$FAKE_MEM" $((0x60400000 + 0x200 + 0x28)) 00000001
w "$FAKE_MEM" $((0x60400000 + 0x200 + 0x2c)) 80000000; w "$FAKE_MEM" $((0x60400000 + 0x48)) 00000201
sed -i 's/^172:          0 /172:          2 /' "$FAKE_INTR"
exit 0
MPEOF
	chmod +x "$d/bin/modprobe"
}

run() { # env-dir mode  -> output file path in $W/out.<n>; env knobs via the caller
	local d="$1" mode="$2" out="$W/out.$3"
	NOROOT=1 MMIO="${MMIO:-$W/mmio-read-x86_64}" SYS="$d/sys/bus/pci/devices" PLAT="$d/sys/bus/platform/devices" PROC="$d/proc" \
	MEMDEV="$d/mem" KMSG=/dev/null TMPDIR="$W" NSEC="${NSEC:-4}" FAKE_MEM="$d/mem" FAKE_INTR="$d/proc/interrupts" \
	PATH="$d/bin:$PATH" bash --posix "$HERE/phone-mhi-regdump.sh" "$mode" > "$out" 2>&1
	echo $? > "$out.rc"
}

echo "== static checks"
shellcheck -s sh "$HERE/phone-mhi-regdump.sh" && ok "shellcheck -s sh clean" || bad "shellcheck"
bash --posix -n "$HERE/phone-mhi-regdump.sh" && ok "bash --posix -n" || bad "syntax"

echo "== load run: fake chip boots PBL -> SBL while the script samples"
mkenv "$W/e1" 0006 1
NSEC=4 run "$W/e1" load 1
O="$W/out.1"
has   "helper self-test passed"                       "mmio-read self-test: ok"                         "$O"
has   "BAR0 base read from the resource file"          "BAR0 physical base 0x60400000"                   "$O"
has   "MSI capability found and decoded"               "msi cap@0x50: ctrl=0x01db enable=1 vectors_enabled=32/32 64bit=1 addr=0x00000000ffa00000" "$O"
has   "PCIe capability decoded"                        "pcie cap@0x70: DevSta:DevCtl=0x00102810  LnkSta:LnkCtl=0x10030142" "$O"
has   "first sample: PBL, BHI idle, nothing handed over" "EXECENV=00000000(PBL) STATUS=00000000(RESET)"   "$O"
has   "serial number read through the BHI window"      "SERIAL=12345678"                                 "$O"
has   "BHIOFF/BHIEOFF read"                            "BHIOFF=00000200 BHIEOFF=00000324"                "$O"
has   "after the fake boot: SBL"                       "EXECENV=00000001(SBL) STATUS=80000000(SUCCESS)"  "$O"
has   "after the fake boot: image address/size/doorbell" "IMG=00000000:12340000 SIZE=00080000 TXDB=00000001" "$O"
has   "MHI status decoded (ready=1, state M0)"          "ready=1 syserr=0 state=M0"                       "$O"
has   "interrupt sums: endpoint 0, root port 0 then 2"  "irq[ep=0 rp=0]"                                  "$O"
has   "interrupt sums: root port got 2"                 "irq[ep=0 rp=2]"                                  "$O"
has   "per-vector listing"                              "vec 0  count=0      bhi"                         "$O"
has   "BHIE block read"                                 "BHIE[TXADDR=00000000:00000000"                   "$O"
has   "BDF2SID table markers"                           "BDF2SID-TABLE-BEGIN"                             "$O"
has   "BDF_TO_SID_CFG line"                             "PARF_BDF_TO_SID_CFG (0x1c02c00, bit0 = BDF_TO_SID_BYPASS): 00000000" "$O"
hasnt "no failed reads"                                 "READ FAILED"                                     "$O"
[ "$(cat "$O.rc")" = 0 ] && ok "exit status 0" || bad "exit status $(cat "$O.rc")"
# change detection: the SBL transition must be on its own line, and quiet seconds must not spam (4 s run)
n="$(grep -c '^t=' "$O")"; [ "$n" -ge 3 ] && [ "$n" -le 40 ] && ok "sample lines: $n (change-driven, not one per loop)" || bad "sample lines: $n"
python3 "$HERE/predict-qcom-bdf-sid-table.py" --decode "$O" > "$W/decode.txt" 2>&1
has   "table dump decodes through predict-qcom-bdf-sid-table.py" "slot 0x07 = 0xffed3b00" "$W/decode.txt"
has   "...and shows the endpoint has no entry"           "lookup endpoint 01:00.0 (RID 0x0100)" "$W/decode.txt"
grep -F -q "NO ENTRY" "$W/decode.txt" && ok "...NO ENTRY for RID 0x0100" || bad "decode did not report NO ENTRY"

echo "== memory space off (a driverless endpoint): the script must not read BAR0"
mkenv "$W/e2" 0000 1
NSEC=2 run "$W/e2" idle 2
has   "refuses to read a BAR that is not decoded"       "memory space off, BAR0 not decoded, not reading" "$W/out.2"
hasnt "and issues no BAR read"                          "MHI[LEN"                                         "$W/out.2"

echo "== idle mode switches memory space on through sysfs enable and back off"
mkenv "$W/e3" 0000 0
NSEC=2 run "$W/e3" idle 3
has   "announces the enable"                            "switched the endpoint's memory space on through sysfs enable" "$W/out.3"
[ "$(cat "$W/e3/sys/devices/platform/soc@0/1c00000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/enable")" = 0 ] && ok "enable restored to 0" || bad "enable not restored"

echo "== guards"
mkenv "$W/e4" 0006 1
MMIO="$W/does-not-exist" NSEC=1 run "$W/e4" idle 4
has   "missing helper stops the run"                    "no executable"                                   "$W/out.4"
[ "$(cat "$W/out.4.rc")" = 1 ] && ok "exit status 1" || bad "exit status $(cat "$W/out.4.rc")"
printf '#!/bin/sh\necho nope\n' > "$W/liar"; chmod +x "$W/liar"
MMIO="$W/liar" NSEC=1 run "$W/e4" idle 5
has   "a helper that cannot read stops the run"         "SELF-TEST FAILED"                                "$W/out.5"
[ "$(cat "$W/out.5.rc")" = 1 ] && ok "exit status 1" || bad "exit status $(cat "$W/out.5.rc")"
echo "suspended" > "$W/e4/sys/bus/platform/devices/1c00000.pcie/power/runtime_status"
NSEC=1 run "$W/e4" idle 6
has   "a suspended PCIe controller is not touched"      "runtime status is 'suspended': not touching its registers" "$W/out.6"
hasnt "...and no table is dumped"                       "BDF2SID-TABLE-BEGIN"                             "$W/out.6"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES (outputs kept in $W until exit; see out.*)"; cp -r "$W" /tmp/dm1q-regdump-test-failed 2>/dev/null; exit 1; }
