#!/usr/bin/env bash
# PC-side compile check of the touch driver (docs/06 rule 3): compiles ONE source file of drivers/input/touchscreen with the exact command kbuild
# used for the earlier out-of-tree build (../_scratch/fts-build, source tree ../_scratch/linux-build/full, 7.3-rc3, clang, arm64, -Wall -Wextra).
# It does not link and does not need sudo. Usage: bash scripts/compile-check-fts2ba61y.sh <path to fts2ba61y.c> [object output]
# Or build the driver as the package would: bash scripts/compile-check-fts2ba61y.sh --patched   (applies kernel/patches/0002, 0004, 0005... to a scratch copy)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
BUILD="${FTS_BUILD:-$REPO/../_scratch/fts-build}"
CMDFILE="$BUILD/drivers/input/touchscreen/.fts2ba61y.o.cmd"
CLEAN="${KERNEL_CLEAN_SRC:-$HOME/.cache/dm1q-kernel-src/full/linux-7.3-rc3}"
[ -f "$CMDFILE" ] || { echo "missing $CMDFILE (the earlier out-of-tree build of the driver)"; exit 2; }

SRC="${1:-}"
OBJ="${2:-}"
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

if [ "$SRC" = "--patched" ]; then
	[ -d "$CLEAN/drivers/input/touchscreen" ] || { echo "missing clean kernel source $CLEAN"; exit 2; }
	TMP="$(mktemp -d)"
	mkdir -p "$TMP/drivers/input/touchscreen" "$TMP/Documentation/devicetree/bindings/input/touchscreen"
	cp "$CLEAN/drivers/input/touchscreen/Kconfig" "$CLEAN/drivers/input/touchscreen/Makefile" "$TMP/drivers/input/touchscreen/"
	for p in "$REPO"/kernel/patches/0002-*.patch "$REPO"/kernel/patches/0004-*.patch "$REPO"/kernel/patches/0005-*.patch; do
		[ -f "$p" ] || continue
		( cd "$TMP" && patch -p1 -s < "$p" ) || { echo "patch failed: $p"; exit 1; }
		echo "applied $(basename "$p")"
	done
	SRC="$TMP/drivers/input/touchscreen/fts2ba61y.c"
	OBJ="${2:-}"
fi
[ -f "$SRC" ] || { echo "usage: $0 <fts2ba61y.c>|--patched [object]"; exit 2; }
[ -n "$OBJ" ] || { [ -z "$TMP" ] && TMP="$(mktemp -d)"; OBJ="$TMP/fts2ba61y.o"; }

CMD="$(python3 - "$CMDFILE" "$SRC" "$OBJ" <<'PY'
import sys, re
cmdfile, src, obj = sys.argv[1:4]
line = ""
for l in open(cmdfile):
    if l.startswith("savedcmd_"):
        line = l.split(":=", 1)[1].strip()
        break
assert line, "no savedcmd line"
line = re.sub(r"-Wp,-MMD,\S+", "", line)
line = re.sub(r"-c -o \S+ \S+$", "-c -o %s %s" % (obj, src), line)
print(line)
PY
)"
cd "$BUILD" || exit 2
echo "compiling $SRC"
if eval "$CMD"; then
	echo "COMPILE OK: $OBJ"
else
	echo "COMPILE FAILED"
	exit 1
fi
