#!/usr/bin/env bash
# Test scripts/drm-fill.c on the PC (host build of the same source), docs/06 rule 3.
# Covers: usage and error paths with their exit codes, the open/ioctl error paths against real files
# (/dev/null is not a DRM node -> ENOTTY on the first ioctl), that every struct size and ioctl number the tool
# uses matches the REAL kernel headers (a program compiled with the host C compiler and /usr/include/drm), that
# `info` runs read-only against a real host DRM card when one is readable, and that the aarch64 binary is a
# static AArch64 ELF. `fill` is NEVER run against a host card here (it would modeset the PC's display).
# NOT covered (needs the phone): the modeset itself; the ioctl numbers and struct layouts it uses are exactly
# what the header check pins down.
# Usage: bash scripts/test-drm-fill.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
HOST_OUT="$W/drm-fill-x86_64" bash "$HERE/build-drm-fill.sh" >/dev/null || { echo "build failed"; exit 1; }
X="$W/drm-fill-x86_64"
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1  (got: $2)"; fail=1; }
t() { # name expected-output expected-exit cmd...
	local name="$1" want="$2" rc="$3"; shift 3
	local got; got="$("$@" 2>&1)"; local grc=$?
	if [ "$got" = "$want" ] && [ "$grc" = "$rc" ]; then ok "$name"; else bad "$name" "rc=$grc out=[$got]"; fi
}
USAGE="$("$X" 2>&1)"

t "no args prints usage"            "$USAGE" 1 "$X"
t "unknown verb prints usage"       "$USAGE" 1 "$X" bogus
t "info without CARD"               "$USAGE" 1 "$X" info
t "fill with too few args"          "$USAGE" 1 "$X" fill /dev/null bars
t "fill: bad seconds (letters)"     "$USAGE" 1 "$X" fill /dev/null bars 5x
t "fill: bad seconds (empty)"       "$USAGE" 1 "$X" fill /dev/null bars ""
t "fill: seconds above 3600"        "$USAGE" 1 "$X" fill /dev/null bars 3601
t "fill: unknown pattern"           "$USAGE" 1 "$X" fill /dev/null stripes 1
t "info: missing device"            "ERR open errno=2"          2 "$X" info /nonexistent/card9
t "fill: missing device"            "ERR open errno=2"          2 "$X" fill /nonexistent/card9 bars 1
t "info: /dev/null is no DRM node"  "ERR ioctl GETRESOURCES errno=25" 3 "$X" info /dev/null
t "fill: /dev/null is no DRM node"  "ERR ioctl GETRESOURCES errno=25" 3 "$X" fill /dev/null red 1

# struct sizes and ioctl numbers against the real headers
cat > "$W/hdr.c" <<'EOF'
#include <stdio.h>
#include <sys/ioctl.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
int main(void)
{
	printf("sizeof mode_info %zu\n", sizeof(struct drm_mode_modeinfo));
	printf("sizeof card_res %zu\n", sizeof(struct drm_mode_card_res));
	printf("sizeof get_connector %zu\n", sizeof(struct drm_mode_get_connector));
	printf("sizeof get_encoder %zu\n", sizeof(struct drm_mode_get_encoder));
	printf("sizeof crtc %zu\n", sizeof(struct drm_mode_crtc));
	printf("sizeof create_dumb %zu\n", sizeof(struct drm_mode_create_dumb));
	printf("sizeof map_dumb %zu\n", sizeof(struct drm_mode_map_dumb));
	printf("sizeof fb_cmd2 %zu\n", sizeof(struct drm_mode_fb_cmd2));
	printf("GETRESOURCES %#lx\n", (unsigned long)DRM_IOCTL_MODE_GETRESOURCES);
	printf("SETCRTC %#lx\n", (unsigned long)DRM_IOCTL_MODE_SETCRTC);
	printf("GETENCODER %#lx\n", (unsigned long)DRM_IOCTL_MODE_GETENCODER);
	printf("GETCONNECTOR %#lx\n", (unsigned long)DRM_IOCTL_MODE_GETCONNECTOR);
	printf("CREATE_DUMB %#lx\n", (unsigned long)DRM_IOCTL_MODE_CREATE_DUMB);
	printf("MAP_DUMB %#lx\n", (unsigned long)DRM_IOCTL_MODE_MAP_DUMB);
	printf("ADDFB2 %#lx\n", (unsigned long)DRM_IOCTL_MODE_ADDFB2);
	return 0;
}
EOF
if ${CC:-cc} -I/usr/include -I/usr/include/libdrm -o "$W/hdr" "$W/hdr.c" 2>"$W/hdr.err"; then
	if [ "$("$W/hdr")" = "$("$X" --selftest)" ]; then ok "struct sizes + ioctl numbers match the real kernel headers"
	else bad "header check" "$(diff <("$W/hdr") <("$X" --selftest) | head -6)"; fi
else
	bad "header check could not compile" "$(head -3 "$W/hdr.err")"
fi
# FOURCC XR24 (drm_fourcc.h) and DSI connector type (drm_mode.h)
cat > "$W/fcc.c" <<'EOF'
#include <stdio.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
int main(void) { printf("%#x %d\n", DRM_FORMAT_XRGB8888, DRM_MODE_CONNECTOR_DSI); return 0; }
EOF
${CC:-cc} -I/usr/include -I/usr/include/libdrm -o "$W/fcc" "$W/fcc.c" 2>/dev/null && \
	{ [ "$("$W/fcc")" = "0x34325258 16" ] && ok "XR24 fourcc and DSI connector type" || bad "fourcc/connector constants" "$("$W/fcc")"; }

# read-only info on a real host card, if one is readable
for c in /dev/dri/card*; do
	[ -r "$c" ] && [ -w "$c" ] || continue
	got="$("$X" info "$c" 2>&1)"; rc=$?
	if [ "$rc" = 0 ] && echo "$got" | grep -q '^crtcs ' && echo "$got" | grep -q '^connector '; then ok "info on host card $c (read-only)"; else bad "info on host card $c" "rc=$rc $(echo "$got" | head -3)"; fi
	break
done

file "$HERE/bin/drm-fill-aarch64" | grep -q "ELF 64-bit LSB executable, ARM aarch64.*statically linked" && ok "aarch64 binary is a static AArch64 ELF" || bad "aarch64 binary" "$(file "$HERE/bin/drm-fill-aarch64")"

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
