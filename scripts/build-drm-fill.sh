#!/usr/bin/env bash
# Build the freestanding DRM test-pattern tool (scripts/drm-fill.c):
#   scripts/bin/drm-fill-aarch64   the binary the phone runs (copied there by collect-phone-state.sh --display-fill)
#   $HOST_OUT                      optional host build of the SAME source, used only by scripts/test-drm-fill.sh
# Needs clang + lld (both present on the PC; no sysroot, no libc: raw syscalls only).
# Usage: bash scripts/build-drm-fill.sh        (prints the sha256 of the aarch64 binary)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/bin"
FLAGS=(-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie
       -fno-asynchronous-unwind-tables -nostdlib -static -fuse-ld=lld
       -Wl,--build-id=none -Wl,-z,norelro -Wl,-z,noseparate-code -Wl,--gc-sections -Wl,-s)
clang --target=aarch64-linux-gnu "${FLAGS[@]}" -o "$HERE/bin/drm-fill-aarch64" "$HERE/drm-fill.c"
echo "built $HERE/bin/drm-fill-aarch64 ($(stat -c %s "$HERE/bin/drm-fill-aarch64") bytes)"
file "$HERE/bin/drm-fill-aarch64" | cut -c1-200
sha256sum "$HERE/bin/drm-fill-aarch64"
if [ -n "${HOST_OUT:-}" ]; then
	clang --target=x86_64-linux-gnu "${FLAGS[@]}" -o "$HOST_OUT" "$HERE/drm-fill.c"
	echo "built host test binary $HOST_OUT"
fi
