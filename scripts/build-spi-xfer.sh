#!/usr/bin/env bash
# Build the freestanding SPI transfer tool (scripts/spi-xfer.c):
#   scripts/bin/spi-xfer-aarch64   the binary the phone runs (copied there by collect-phone-state.sh --touch)
#   $HOST_OUT                      optional host build of the SAME source, used only by scripts/test-spi-xfer.sh
# Needs clang + lld (both present on the PC; no sysroot, no libc: raw syscalls only).
# Usage: bash scripts/build-spi-xfer.sh        (prints the sha256 of the aarch64 binary)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/bin"
FLAGS=(-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie
       -fno-asynchronous-unwind-tables -nostdlib -static -fuse-ld=lld
       -Wl,--build-id=none -Wl,-z,norelro -Wl,-z,noseparate-code -Wl,--gc-sections -Wl,-s)
clang --target=aarch64-linux-gnu "${FLAGS[@]}" -o "$HERE/bin/spi-xfer-aarch64" "$HERE/spi-xfer.c"
echo "built $HERE/bin/spi-xfer-aarch64 ($(stat -c %s "$HERE/bin/spi-xfer-aarch64") bytes)"
file "$HERE/bin/spi-xfer-aarch64" | cut -c1-200
sha256sum "$HERE/bin/spi-xfer-aarch64"
if [ -n "${HOST_OUT:-}" ]; then
	clang --target=x86_64-linux-gnu "${FLAGS[@]}" -o "$HOST_OUT" "$HERE/spi-xfer.c"
	echo "built host test binary $HOST_OUT"
fi
