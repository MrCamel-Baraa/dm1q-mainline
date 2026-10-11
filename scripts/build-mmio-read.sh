#!/usr/bin/env bash
# Build the freestanding MMIO reader (scripts/mmio-read.c):
#   scripts/bin/mmio-read-aarch64   the binary the phone runs (copied there by collect-phone-state.sh)
#   $TMPDIR/mmio-read-x86_64        host build of the SAME source, used only by scripts/test-mmio-read.sh
# Needs clang + lld (both present on the PC; no sysroot, no libc: raw syscalls only).
# Usage: bash scripts/build-mmio-read.sh        (prints the sha256 of the aarch64 binary)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/bin"
FLAGS=(-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie
       -fno-asynchronous-unwind-tables -nostdlib -static -fuse-ld=lld
       -Wl,--build-id=none -Wl,-z,norelro -Wl,-z,noseparate-code -Wl,--gc-sections -Wl,-s)
clang --target=aarch64-linux-gnu "${FLAGS[@]}" -o "$HERE/bin/mmio-read-aarch64" "$HERE/mmio-read.c"
echo "built $HERE/bin/mmio-read-aarch64 ($(stat -c %s "$HERE/bin/mmio-read-aarch64") bytes)"
file "$HERE/bin/mmio-read-aarch64" | cut -c1-200
sha256sum "$HERE/bin/mmio-read-aarch64"
if [ "${1:-}" = "--host" ] || [ -n "${HOST_OUT:-}" ]; then
	clang --target=x86_64-linux-gnu "${FLAGS[@]}" -o "${HOST_OUT:-${TMPDIR:-/tmp}/mmio-read-x86_64}" "$HERE/mmio-read.c"
	echo "built host test binary ${HOST_OUT:-${TMPDIR:-/tmp}/mmio-read-x86_64}"
fi
