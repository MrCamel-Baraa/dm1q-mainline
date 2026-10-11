#!/usr/bin/env bash
# Test scripts/mmio-read.c on the PC (host build of the same source, mmap of regular files stands in for BAR0).
# Covers: values + byte order, base offset, 8-per-line output, the error paths and exit codes, and that the
# aarch64 binary is a static AArch64 ELF whose syscall numbers are the aarch64 ones.
# Usage: bash scripts/test-mmio-read.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
HOST_OUT="$W/mmio-read-x86_64" bash "$HERE/build-mmio-read.sh" >/dev/null || { echo "build failed"; exit 1; }
M="$W/mmio-read-x86_64"
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }
t() { # name expected-stdout expected-exit cmd...
	local name="$1" want="$2" rc="$3"; shift 3
	local got; got="$("$@" 2>&1)"; local grc=$?
	if [ "$got" = "$want" ] && [ "$grc" = "$rc" ]; then ok "$name"; else bad "$name" "rc=$grc out=[$got]"; fi
}

# 8 KiB test file: bytes ef be ad de 78 56 34 12 at 0, and 00 01 02 03 .. at 0x1000 (second page)
printf '\357\276\255\336\170\126\064\022' > "$W/f"
head -c $((0x1000 - 8)) /dev/zero >> "$W/f"
printf '\000\001\002\003\004\005\006\007\010\011\012\013' >> "$W/f"
head -c 4096 /dev/zero >> "$W/f"

t "two words, little-endian"           "deadbeef 12345678"                 0 "$M" "$W/f" 0 0 4
t "argument order is output order"     "12345678 deadbeef"                 0 "$M" "$W/f" 0 4 0
t "0x prefix accepted"                 "deadbeef"                          0 "$M" "$W/f" 0x0 0x0
t "page-aligned base, second page"     "03020100 07060504 0b0a0908"        0 "$M" "$W/f" 1000 0 4 8
t "same offset twice"                  "deadbeef deadbeef"                 0 "$M" "$W/f" 0 0 0
# 10 offsets -> a newline after the 8th value
want="$(printf 'deadbeef deadbeef deadbeef deadbeef deadbeef deadbeef deadbeef deadbeef\ndeadbeef deadbeef')"
t "8 values per line"                  "$want"                             0 "$M" "$W/f" 0 0 0 0 0 0 0 0 0 0 0
t "missing file -> exit 2"             "ERR open errno=2"                  2 "$M" "$W/nope" 0 0
t "unaligned offset -> usage, exit 1"  "usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)" 1 "$M" "$W/f" 0 2
t "unaligned base -> usage, exit 1"    "usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)" 1 "$M" "$W/f" 10 0
t "no offsets -> usage, exit 1"        "usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)" 1 "$M" "$W/f" 0
t "non-hex offset -> usage, exit 1"    "usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)" 1 "$M" "$W/f" 0 zz
t "offset >= 1 MiB -> usage, exit 1"   "usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)" 1 "$M" "$W/f" 0 100000
t "directory -> mmap fails, exit 3"    "ERR mmap errno=19"                 3 "$M" "$W" 0 0
# 256 offsets (the BDF-to-SID table dump) -> 32 lines of 8
offs=""; for i in $(seq 0 255); do offs="$offs $(printf '%x' $((i * 4)))"; done
n="$("$M" "$W/f" 0 $offs | wc -l)"; [ "$n" = 32 ] && ok "256-word dump = 32 lines" || bad "256-word dump" "$n lines"

A="$HERE/bin/mmio-read-aarch64"
if file "$A" | grep -q 'ELF 64-bit LSB executable, ARM aarch64.*statically linked'; then ok "aarch64 binary is a static ELF"; else bad "aarch64 binary type" "$(file "$A")"; fi
# the aarch64 syscall numbers must appear as immediates loaded into w8/x8: openat 56, write 64, exit_group 94, mmap 222
dis="$(llvm-objdump -d --no-show-raw-insn "$A" 2>/dev/null)"
for nr in 56 64 94 222; do
	if echo "$dis" | grep -E 'mov[[:space:]]+[wx]8, #' | grep -q -E "// =$nr\$"; then ok "aarch64 binary loads syscall nr $nr into w8"; else bad "syscall nr $nr not found in the disassembly" ""; fi
done
echo "$dis" | grep -q 'svc[[:space:]]*#0' && ok "aarch64 binary uses svc #0" || bad "svc #0 not found" ""
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
