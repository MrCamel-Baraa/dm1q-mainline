#!/usr/bin/env bash
# PC-side test of scripts/touch-trace-stalls.py (docs/06 rule 3) on a crafted recorder dump: a normal touch, a stall kicked by a poll worker
# (queue of 9, after 283 ms of silence), a coincidence (a touch-down right after a poll read, left = 0), a stall kicked by dd with a full
# queue, a non-event transfer that must not count as a kick, a task name with dashes, and the refusals.
# Usage: bash scripts/test-touch-trace-stalls.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/touch-trace-stalls.py"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }

TX87="87$(printf -- '-00%.0s' $(seq 17))"
TXD1="d1-00-00$(printf -- '-00%.0s' $(seq 15))"
rxev() { printf '00-87-%s-d8-b9-a8-09-07-09-%s-03-53-00-01-00-00-00-00' "$1" "$2"; }
EMPTY="00-87$(printf -- '-00%.0s' $(seq 16))"
line() { printf '%s [%03d] ..... %s: spi_transfer_stop: spi0.0 0000000000000000 len=18 tx=[%s] rx=[%s]\n' "$1" "$2" "$3" "$4" "$5"; }
IRQ="irq/178-fts2ba6-1544"
F="$W/trace.txt"
{
	echo "# tracer: nop"
	line "$IRQ" 0 10.000000 "$TX87" "$(rxev 40 20)"       # touch-down, left 0 (0x20 is the flag bit)
	line "$IRQ" 0 10.008300 "$TX87" "$(rxev 80 00)"
	line "$IRQ" 0 10.016600 "$TX87" "$(rxev c0 00)"       # release
	line "kworker/5:0-4411" 5 10.300000 "$TX87" "$EMPTY"    # poll read, 284 ms after the release
	line "$IRQ" 0 10.300200 "$TX87" "$(rxev 40 28)"       # touch-down with 8 more queued: a stall
	line "$IRQ" 0 10.300500 "$TX87" "$(rxev 80 07)"
	line "$IRQ" 0 10.500000 "$TX87" "$(rxev c0 00)"
	line "kworker/3:2-77" 3 10.800000 "$TX87" "$EMPTY"      # poll read; a touch-down 500 us later with nothing queued
	line "$IRQ" 0 10.800500 "$TX87" "$(rxev 40 20)"       # coincidence
	line "$IRQ" 0 10.808800 "$TX87" "$(rxev c0 00)"
	line "sh-9001" 2 11.100000 "$TXD1" "00-d1-00-00-00-00-10-00-0f-ff-0f-00-00-00-00-00-00-00"   # not an event read
	line "dd-9002" 2 12.000000 "$TX87" "$EMPTY"             # poke
	line "$IRQ" 0 12.000150 "$TX87" "$(rxev 80 1f)"       # full queue after a long silence: a stall
	line "$IRQ" 0 12.000400 "$TX87" "$(rxev 80 1e)"
} > "$F"

python3 "$PY" "$F" > "$W/out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "exit 0" || bad "exit $rc"
expect "$W/out" "touch-downs counted" "touch-downs: 3 "
expect "$W/out" "kicks counted (two polls and the poke, not the D1 read)" "kick reads \(poll or poke\): 3 "
expect "$W/out" "two stalls" "STALLS .*: 2$"
expect "$W/out" "one coincidence" "coincidences .*: 1$"
expect "$W/out" "the poll stall: 9 queued, kicked by the kworker, queue starts with a press, after a release" "stall at 10\.300200 s: kicked by kworker/5:0 200 us before the IRQ read; silence 283 ms; 9 events queued .*queue starts with a press, last read before it: release"
expect "$W/out" "idle gap of the stalled touch-down: 283 ms minus 8 frames is about 217 ms" "idle gap before that touch-down: 21[0-9] ms"
expect "$W/out" "the dd stall: 31 queued after a long silence" "stall at 12\.000150 s: kicked by dd 150 us before the IRQ read; silence 1[0-9]{3} ms; 32 events queued"
expect "$W/out" "queue starts with a move" "32 events queued .*queue starts with a move, last read before it: release"
expect "$W/out" "per 1000" "stalls per 1000 touch-downs: 666\.67"

python3 "$PY" "$F" --json > "$W/json" 2>&1
python3 -c "import json,sys; d=json.load(open('$W/json')); assert len(d['stalls'])==2 and d['coincidences']==1 and d['touch_downs']==3" && ok "--json agrees" || bad "--json"

: > "$W/empty"
python3 "$PY" "$W/empty" > "$W/o2" 2>&1; rc=$?
[ "$rc" = 3 ] && ok "no records: exit 3" || bad "no records: exit $rc"
python3 "$PY" > "$W/o3" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no argument: exit 2" || bad "no argument: exit $rc"

python3 -m py_compile "$PY" && ok "py_compile" || bad "py_compile"

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
