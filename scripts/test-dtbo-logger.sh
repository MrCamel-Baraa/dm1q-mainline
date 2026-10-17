#!/usr/bin/env bash
# PC-side test of kernel/initramfs/dtbo-logger.sh (docs/06 rule 3, docs/09 section 16).
# It runs the logger exactly as stage 1 does (sourced by /bin/sh inside a root, background loop) in an
# unprivileged user-namespace chroot, lets it flush a fake kernel log into a fake dtbo "partition", then
# DELETES the whole initramfs under the running loop -- what switch_root does -- and checks that
#   - the loop exits by itself within a few seconds, and
#   - nothing from the loop ever reached the console (the flood seen on the phone's screen, 2026-10-16).
# A control run with the version committed before the fix (git e367de2, the only earlier version, or
# --old <file>) must reproduce the flood, so the test proves it can see the bug.
# The host's bash stands in for the initramfs' busybox ash; dmesg and `busybox sleep` are tiny shims.
# Usage: bash scripts/test-dtbo-logger.sh [--old <old dtbo-logger.sh>]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
NEW="$REPO/kernel/initramfs/dtbo-logger.sh"
OLD=""
while [ $# -gt 0 ]; do case "$1" in --old) OLD="$2"; shift 2 ;; *) echo "unknown arg $1" >&2; exit 2 ;; esac; done
for t in unshare chroot ldd dd grep wc cut cat sleep bash timeout; do command -v "$t" >/dev/null || { echo "need $t" >&2; exit 2; }; done
unshare -r true 2>/dev/null || { echo "unprivileged user namespaces not available" >&2; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
if [ -z "$OLD" ]; then
	OLD="$W/old-logger.sh"
	git -C "$REPO" show 'e367de2:kernel/initramfs/dtbo-logger.sh' > "$OLD" 2>/dev/null || { echo "cannot read the old script from git" >&2; exit 2; }
fi
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

mk_root() { # $1 = root dir, $2 = logger script
	local R="$1" b p l
	mkdir -p "$R/bin" "$R/dev" "$R/tmp" "$R/sys/class/block/sdx37"
	for b in bash dd grep wc cut cat sleep; do
		p="$(command -v "$b")"; cp -L "$p" "$R/bin/$b"
		ldd "$p" 2>/dev/null | grep -o '/[^ ]*' | while read -r l; do [ -e "$l" ] && cp -L --parents "$l" "$R" 2>/dev/null; done
	done
	cp "$R/bin/bash" "$R/bin/sh"
	printf '#!/bin/sh\necho "[    1.000000] fake kernel line"\n' > "$R/bin/dmesg"
	printf '#!/bin/sh\n[ "$1" = sleep ] && shift\nexec /bin/sleep 0.3\n' > "$R/bin/busybox"
	chmod +x "$R/bin/dmesg" "$R/bin/busybox"
	cp "$2" "$R/dtbo-logger.sh"
	printf 'PARTNAME=dtbo\nDEVNAME=fakedtbo\n' > "$R/sys/class/block/sdx37/uevent"
	: > "$R/dev/null"; : > "$R/dev/fakedtbo"
	echo "pmOS init log line" > "$R/pmOS_init.log"
}

run_case() { # $1 = name, $2 = script, $3 = timeout seconds for the whole run. Sets CONSOLE, FLUSHED, RC
	local R="$W/$1/root"; mkdir -p "$W/$1"; mk_root "$R" "$2"
	CONSOLE="$W/$1/console.txt"
	( timeout "$3" unshare -rm bash -c '
		mount --bind /dev/null "$0/dev/null" || exit 97
		exec chroot "$0" /bin/sh -c ". /dtbo-logger.sh; echo \"[init] loop started\"; wait; echo \"[init] loop gone\""
	' "$R" > "$CONSOLE" 2>&1; echo $? > "$W/$1/rc" ) &
	local CASEPID=$!
	sleep 1.5
	# what the log flush produced before the "switch_root"
	FLUSHED="$(dd if="$R/dev/fakedtbo" bs=1M skip=1 count=1 2>/dev/null | tr -d '\0' | grep -c 'fake kernel line')"
	# switch_root: delete the initramfs contents (the running shell keeps the empty root)
	rm -rf "$R/dtbo-logger.sh" "$R/tmp" "$R/bin" "$R/lib" "$R/lib64" "$R/usr" "$R/sys" "$R/pmOS_init.log"
	wait "$CASEPID"
	RC="$(cat "$W/$1/rc")"
}

echo "== control: the version before the fix must reproduce the flood"
run_case old "$OLD" 6
[ "$FLUSHED" -ge 1 ] && ok "old: log reached the fake dtbo before the deletion" || bad "old: nothing flushed (test harness problem)"
nold="$(grep -c -E "not found|No such file|nonexist|can.t" "$CONSOLE" || true)"
[ "$nold" -ge 6 ] && ok "old: flood reproduced ($nold error lines in <5 s)" || bad "old: no flood reproduced ($nold lines) -- the test cannot see the bug"
[ "$RC" = 124 ] && ok "old: loop never exits (killed by the timeout)" || bad "old: loop ended on its own (rc=$RC)"

echo "== fixed version"
run_case new "$NEW" 12
[ "$FLUSHED" -ge 1 ] && ok "new: log reached the fake dtbo before the deletion" || bad "new: nothing flushed"
grep -q '^\[init\] loop started$' "$CONSOLE" && ok "new: loop started" || bad "new: loop did not start"
grep -q '^\[init\] loop gone$' "$CONSOLE" && ok "new: loop exited by itself after the initramfs was deleted" || bad "new: loop still running"
[ "$RC" = 0 ] && ok "new: whole run finished before the timeout (rc=0)" || bad "new: rc=$RC"
extra="$(grep -v -E '^\[init\] loop (started|gone)$' "$CONSOLE" | wc -l)"
[ "$extra" = 0 ] && ok "new: nothing else on the console" || { bad "new: $extra unexpected console lines"; grep -v -E '^\[init\] loop (started|gone)$' "$CONSOLE" | head -5; }

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
