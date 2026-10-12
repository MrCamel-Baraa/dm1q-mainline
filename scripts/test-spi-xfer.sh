#!/usr/bin/env bash
# Test scripts/spi-xfer.c on the PC (host build of the same source).
# Covers: hex/zero-pad frame parsing (--dry-run), the usage and error paths and exit codes, the open/ioctl
# error paths against real files (/dev/null is not a spidev node -> ENOTTY on the first ioctl), that the
# struct size and ioctl numbers match the REAL kernel header (compiled with the host's own C compiler), and that
# the aarch64 binary is a static AArch64 ELF.
# NOT covered (needs the phone): the actual SPI transfer. The ioctl request numbers and struct layout it
# uses are exactly what the header check pins down.
# Usage: bash scripts/test-spi-xfer.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
HOST_OUT="$W/spi-xfer-x86_64" bash "$HERE/build-spi-xfer.sh" >/dev/null || { echo "build failed"; exit 1; }
X="$W/spi-xfer-x86_64"
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }
t() { # name expected-stdout expected-exit cmd...
	local name="$1" want="$2" rc="$3"; shift 3
	local got; got="$("$@" 2>&1)"; local grc=$?
	if [ "$got" = "$want" ] && [ "$grc" = "$rc" ]; then ok "$name"; else bad "$name" "rc=$grc out=[$got]"; fi
}
USAGE="$("$X" 2>&1)"   # the full 3-line usage text; every usage-error path must print exactly this

t "dry-run: literal bytes"            "TX fa 20 00 00 24 81"                          0 "$X" --dry-run FA2000002481
t "dry-run: lower/upper case"         "TX ab cd ef"                                   0 "$X" --dry-run abCDeF
t "dry-run: zero padding"             "TX 87 00 00 00"                                0 "$X" --dry-run 87+3
t "dry-run: 18-byte event read"       "TX 87 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" 0 "$X" --dry-run 87+17
t "dry-run: sleep + two items"        "$(printf 'TX 87 00\nSLEEP 30\nTX fa 01')"     0 "$X" --dry-run 87+1 sleep:30 FA01
t "dry-run: pad only is fine"         "TX 00 00"                                      0 "$X" --dry-run 00+1
t "no args -> usage, exit 1"          "$USAGE"                                        1 "$X"
t "odd hex digits -> usage"           "$USAGE"                                        1 "$X" --dry-run FA2
t "non-hex -> usage"                  "$USAGE"                                        1 "$X" --dry-run ZZ
t "empty frame (+0 only) -> usage"    "$USAGE"                                        1 "$X" --dry-run +0
t "bad pad count -> usage"            "$USAGE"                                        1 "$X" --dry-run 87+x
t "frame over 512 bytes -> usage"     "$USAGE"                                        1 "$X" --dry-run 87+512
t "frame of exactly 512 is fine"      "ok"                                            0 bash -c "\"$X\" --dry-run 87+511 | awk 'NR==1{print (NF==513)?\"ok\":\"bad NF=\"NF}'"
t "bad sleep -> usage"                "$USAGE"                                        1 "$X" --dry-run sleep:abc
t "dry-run without items -> usage"    "$USAGE"                                        1 "$X" --dry-run
t "missing HZ -> usage"               "$USAGE"                                        1 "$X" /dev/null
t "zero HZ -> usage"                  "$USAGE"                                        1 "$X" /dev/null 0 87
t "missing device -> exit 2"          "ERR open errno=2"                              2 "$X" "$W/nope" 1000000 87
t "not a spidev -> ENOTTY on mode"    "ERR ioctl mode errno=25"                       3 "$X" /dev/null 1000000 87+1
t "bad item is rejected BEFORE open"  "$USAGE"                                        1 "$X" "$W/nope" 1000000 87 ZZ

# struct size + ioctl numbers against the real kernel header
cat > "$W/hdr.c" <<'EOF'
#include <stdio.h>
#include <linux/spi/spidev.h>
int main(void)
{
	printf("sizeof_xfer=%zu msg1=%08lx mode=%08lx bits=%08lx speed=%08lx\n", sizeof(struct spi_ioc_transfer),
	       (unsigned long)SPI_IOC_MESSAGE(1), (unsigned long)SPI_IOC_WR_MODE,
	       (unsigned long)SPI_IOC_WR_BITS_PER_WORD, (unsigned long)SPI_IOC_WR_MAX_SPEED_HZ);
	return 0;
}
EOF
if clang -o "$W/hdr" "$W/hdr.c" 2>"$W/hdr.err"; then
	t "ioctl numbers + struct size == kernel header" "$("$W/hdr")" 0 "$X" --selftest
else
	bad "could not compile the header check (needs linux/spi/spidev.h)" "$(head -3 "$W/hdr.err")"
fi

# the aarch64 binary: static AArch64 ELF whose syscalls are the aarch64 numbers
A="$HERE/bin/spi-xfer-aarch64"
if [ -f "$A" ]; then
	f="$(file "$A")"
	case "$f" in *"ELF 64-bit"*"ARM aarch64"*"statically linked"*) ok "aarch64 binary is a static AArch64 ELF" ;; *) bad "aarch64 binary type" "$f" ;; esac
else
	bad "no $A" "run: bash scripts/build-spi-xfer.sh"
fi
# the x86-64 / aarch64 numbers differ only where they must: both ioctl request words are asm-generic
# (checked above by the selftest on the host); here we pin the aarch64 syscall table entries used.
for pair in "SYS_openat 56" "SYS_ioctl 29" "SYS_write 64" "SYS_exit_group 94" "SYS_nanosleep 101"; do
	set -- $pair
	if awk -v n="$1" -v v="$2" '/^#if defined\(__aarch64__\)/{a=1} /^#elif defined\(__x86_64__\)/{a=0} a && $1=="#define" && $2==n && $3==v {f=1} END{exit f?0:1}' "$HERE/spi-xfer.c"; then
		ok "aarch64 $1 = $2"
	else
		bad "aarch64 $1" "expected $2"
	fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
