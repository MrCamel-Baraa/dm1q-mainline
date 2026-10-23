#!/usr/bin/env bash
# PC-side test of the argument handling of scripts/make-dtb-image-set.sh (docs/06 rule 3). The script itself needs a kernel tree, dtc and
# a kernel apk, so only the early exits are tested here, with dummy files: no arguments, a missing --ref-set, a missing --apk, an unknown
# argument, and that nothing is created in the output directory when it refuses. The real path was tested on 2026-10-23 (RESULT: image set OK).
# Usage: bash scripts/test-make-dtb-image-set-args.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/make-dtb-image-set.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }

: > "$W/x.dts"
mkdir -p "$W/ref"

echo "== refusals"
bash "$SCRIPT" > "$W/none.out" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no arguments: exit 2" || bad "no arguments: exit $rc"
expect "$W/none.out" "no arguments: prints the usage" "Usage: scripts/make-dtb-image-set.sh"

bash "$SCRIPT" --dts "$W/x.dts" --out "$W/out" --apk "$W/a.apk" > "$W/noref.out" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no --ref-set: exit 2" || bad "no --ref-set: exit $rc"
expect "$W/noref.out" "no --ref-set: says to pass it explicitly" "pass --ref-set .* and --apk .* explicitly"

bash "$SCRIPT" --dts "$W/x.dts" --out "$W/out" --ref-set "$W/ref" > "$W/noapk.out" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no --apk: exit 2" || bad "no --apk: exit $rc"
expect "$W/noapk.out" "no --apk: says to pass it explicitly" "pass --ref-set .* and --apk .* explicitly"

bash "$SCRIPT" --dts "$W/x.dts" --out "$W/out" --ref-set "$W/ref" --apk "$W/a.apk" --bogus > "$W/bogus.out" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "unknown argument: exit 2" || bad "unknown argument: exit $rc"
expect "$W/bogus.out" "unknown argument is named" "unknown arg: --bogus"

bash "$SCRIPT" --dts "$W/x.dts" --out "$W/out" --ref-set "$W/ref" --apk "$W/a.apk" > "$W/missing.out" 2>&1; rc=$?
[ "$rc" = 1 ] && ok "missing apk file: exit 1" || bad "missing apk file: exit $rc"
expect "$W/missing.out" "the missing file is named" "missing $W/a.apk"

[ ! -e "$W/out" ] && ok "a refused run created no output directory" || bad "a refused run created $W/out"

echo "== static checks"
bash -n "$SCRIPT" && ok "bash -n" || bad "bash -n"
if command -v shellcheck >/dev/null; then
	shellcheck -S warning "$SCRIPT" && ok "shellcheck -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
