#!/usr/bin/env bash
# PC-side test of scripts/phone-touch-poke.sh (docs/06 rule 3). A fake sysfs / procfs / debugfs tree with a plain file as the raw knob
# (RAW_READ points at a second file that plays the kernel's "tx .. rx .." read-back). Checks: the bytes sent for each STEP, that exactly
# the intended bytes reach the knob, REVIVED / CHIP-RESPONDED / NO-CHANGE (a background writer raises the interrupt count in the right
# phase), that NOT-DEAD sends nothing, the rx classification, a write() error (write=ERR, the run goes on), the aborts and refusals, and the POSIX / shellcheck static checks.
# Usage: bash scripts/test-phone-touch-poke.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/phone-touch-poke.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
check()  { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

IRQ_LINE() { printf ' 181:  %9s          0          0          0          0          0          0          0  msmgpio                    25 Level     fts2ba61y\n' "$1"; }
DATA_RB='tx 8700000000000000000000000000000000 rx 0087800a1b2c3d4e5f60708090a0b0c0d0'

make_tree() {
	local D="$1"
	mkdir -p "$D/sys/kernel/debug/spi0.0" "$D/proc"
	: > "$D/sys/kernel/debug/spi0.0/raw"
	echo "$DATA_RB" > "$D/readback"
	IRQ_LINE 500 > "$D/proc/interrupts"
	echo "gpio25 (fts2ba61y) in hi" > "$D/sys/kernel/debug/gpio"
}

run() {
	local D="$1"; shift
	env ID_U=0 SYSFS="$D/sys" PROC="$D/proc" DEBUGFS="$D/sys/kernel/debug" RAW_READ="$D/readback" PRE=1 SETTLE=1 WAIT=2 "$@" sh "$SCRIPT" > "$D.out" 2>&1
}
raw_is() { [ "$(cat "$1/sys/kernel/debug/spi0.0/raw" 2>/dev/null)" = "$2" ]; }

echo "== flat interrupts, step read"
make_tree "$W/flat"
run "$W/flat" STEP=read; rc=$?
[ "$rc" = 0 ] && ok "flat run: exit 0" || bad "flat run: exit $rc"
check "read sends 87+17" "raw_is '$W/flat' '87+17'"
expect "$W/flat.out" "NO-CHANGE with a flat count" "RESULT poke step=read irq_pre=500 irq_settle=500 irq_end=500 settle_delta=0 watch_delta=0 verdict=NO-CHANGE rx=DATA write=ok"
expect "$W/flat.out" "the read-back is shown" "readback: tx 8700"

echo "== the bytes of each step"
for pair in "senseon:C010" "scanmode:A00001" "reset:FA2000002481" "hex:c022:c022" "hex:87+17:87+17"; do
	step="${pair%:*}"; want="${pair##*:}"
	make_tree "$W/s"
	run "$W/s" STEP="$step"; rc=$?
	[ "$rc" = 0 ] && ok "$step: exit 0" || bad "$step: exit $rc"
	check "$step sends $want" "raw_is '$W/s' '$want'"
done

echo "== interrupts rise while the finger drags: REVIVED"
make_tree "$W/rev"
( sleep 3; IRQ_LINE 560 > "$W/rev/proc/interrupts" ) &
run "$W/rev" STEP=senseon; rc=$?
wait
[ "$rc" = 0 ] && ok "revived run: exit 0" || bad "revived run: exit $rc"
expect "$W/rev.out" "REVIVED when the count rises in the watch phase" "irq_pre=500 irq_settle=500 irq_end=560 settle_delta=0 watch_delta=60 verdict=REVIVED"

echo "== interrupts rise only while settling: CHIP-RESPONDED"
make_tree "$W/resp"
( sleep 1.5; IRQ_LINE 503 > "$W/resp/proc/interrupts" ) &
run "$W/resp" STEP=reset; rc=$?
wait
[ "$rc" = 0 ] && ok "responded run: exit 0" || bad "responded run: exit $rc"
expect "$W/resp.out" "CHIP-RESPONDED when only the settle phase moves" "settle_delta=3 watch_delta=0 verdict=CHIP-RESPONDED"

echo "== touch is not dead: nothing is sent"
make_tree "$W/alive"
( sleep 0.4; IRQ_LINE 520 > "$W/alive/proc/interrupts" ) &
run "$W/alive" STEP=reset; rc=$?
wait
[ "$rc" = 5 ] && ok "NOT-DEAD: exit 5" || bad "NOT-DEAD: exit $rc"
expect "$W/alive.out" "NOT-DEAD verdict" "verdict=NOT-DEAD"
check "the knob received nothing" "raw_is '$W/alive' ''"

echo "== rx classification"
make_tree "$W/z"
echo 'tx 8700 rx 000000' > "$W/z/readback"
run "$W/z" STEP=read
expect "$W/z.out" "all zero rx" "rx=ALL-00"
make_tree "$W/f"
echo 'tx 8700 rx ffFFff' > "$W/f/readback"
run "$W/f" STEP=read
expect "$W/f.out" "all ff rx" "rx=ALL-FF"
make_tree "$W/n"
echo 'nothing useful' > "$W/n/readback"
run "$W/n" STEP=read
expect "$W/n.out" "no tx/rx read-back" "rx=NO-READBACK"

echo "== no touch interrupt line"
make_tree "$W/noirq"
: > "$W/noirq/proc/interrupts"
run "$W/noirq" STEP=read
expect "$W/noirq.out" "NO-IRQ-LINE when the line is absent" "verdict=NO-IRQ-LINE"
check "nothing was sent" "raw_is '$W/noirq' ''"

echo "== the knob is missing or fails"
make_tree "$W/noknob"
rm -f "$W/noknob/sys/kernel/debug/spi0.0/raw"
run "$W/noknob" STEP=read; rc=$?
[ "$rc" = 3 ] && ok "missing knob: exit 3" || bad "missing knob: exit $rc"
expect "$W/noknob.out" "the abort names the knob" "ABORT: .*raw is not writable"
make_tree "$W/dirknob"
rm -f "$W/dirknob/sys/kernel/debug/spi0.0/raw"
mkdir "$W/dirknob/sys/kernel/debug/spi0.0/raw"
run "$W/dirknob" STEP=read; rc=$?
[ "$rc" = 3 ] && ok "knob is a directory: exit 3" || bad "knob is a directory: exit $rc"
echo "== a write() error: the run goes on and says so"
make_tree "$W/werr"
printf '#!/bin/sh\ncat >/dev/null\necho "dd: error writing \x27/x/raw\x27: Input/output error" >&2\nexit 1\n' > "$W/werr/ddfail"
chmod +x "$W/werr/ddfail"
( sleep 3; IRQ_LINE 540 > "$W/werr/proc/interrupts" ) &
run "$W/werr" STEP=read DD="$W/werr/ddfail"; rc=$?
wait
[ "$rc" = 0 ] && ok "write error: exit 0 (it goes on)" || bad "write error: exit $rc"
expect "$W/werr.out" "the error text is shown" "returned an error .*Input/output error"
expect "$W/werr.out" "the verdict is still computed and marked" "watch_delta=40 verdict=REVIVED rx=DATA write=ERR"

echo "== refusals"
make_tree "$W/refuse"
env ID_U=1 SYSFS="$W/refuse/sys" PROC="$W/refuse/proc" DEBUGFS="$W/refuse/sys/kernel/debug" sh "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "not root: exit 2" || bad "not root: exit $rc"
for bad_env in "STEP=bogus" "STEP=hex:" "STEP=hex:zz" "STEP=hex:87+1x" "PRE=x" "WAIT=0" "SETTLE=-1"; do
	run "$W/refuse" "$bad_env"; rc=$?
	[ "$rc" = 2 ] && ok "$bad_env: exit 2" || bad "$bad_env: exit $rc"
done
check "refused runs sent nothing" "raw_is '$W/refuse' ''"

echo "== static checks"
sh -n "$SCRIPT" && ok "sh -n" || bad "sh -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$SCRIPT" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
