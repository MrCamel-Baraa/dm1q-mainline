#!/usr/bin/env bash
# PC-side test of scripts/phone-apknet-diag.sh (docs/06 rule 3). The phone's files are a scratch tree (ROOT=) and
# apk / ip / ping / wget / getent / date are stubs; the script runs with dash (closest to busybox ash) and bash.
#   full   everything present: every section must print its data and the script ends with "done"
#   bare   an empty root and no commands: every section must still print and the script ends with "done"
# Usage: bash scripts/test-phone-apknet-diag.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

F="$W/full"; R="$F/root"; mkdir -p "$F/bin" "$R/etc/apk" "$R/var/cache/apk" "$R/sys/class/net/wlan0" "$R/sys/class/net/usb0" "$R/proc/net"
printf 'nameserver 192.168.1.1\n' > "$R/etc/resolv.conf"
echo 1500 > "$R/sys/class/net/wlan0/mtu"; echo 1500 > "$R/sys/class/net/usb0/mtu"
printf 'Inter-| sta-|   Quality\n wlan0: 0000   70.  -40.  -256\n' > "$R/proc/net/wireless"
touch "$R/var/cache/apk/APKINDEX.deadbeef.tar.gz"
printf '#!/bin/sh\ncase "$1" in --version) echo "apk-tools 3.0.0-stub";; update) echo "WARNING: updating http://x: HTTP: unrecognized server error";; esac\n' > "$F/bin/apk"
printf '#!/bin/sh\necho "default via 192.168.1.1 dev wlan0"\necho "172.16.0.0/16 dev usb0"\n' > "$F/bin/ip"
printf '#!/bin/sh\necho "PING $*"\necho "2 packets transmitted, 2 received"\n' > "$F/bin/ping"
printf '#!/bin/sh\necho "  HTTP/1.1 301 Moved Permanently" >&2\necho "  Location: https://x/" >&2\n' > "$F/bin/wget"
printf '#!/bin/sh\necho "104.16.0.1 $2"\n' > "$F/bin/getent"
printf '#!/bin/sh\nif [ "$1" = "+%%s" ]; then echo 1792240000; else echo "Sat Oct 17 14:27:23 UTC 2026"; fi\n' > "$F/bin/date"
printf '#!/bin/sh\nshift\nexec "$@"\n' > "$F/bin/timeout"
chmod +x "$F"/bin/*
run_full() { env ROOT="$R" APK="$F/bin/apk" IP="$F/bin/ip" PING="$F/bin/ping" WGET="$F/bin/wget" GETENT="$F/bin/getent" \
	DATE="$F/bin/date" TIMEOUT="$F/bin/timeout" "$1" "$HERE/phone-apknet-diag.sh" > "$F/out" 2>&1; }

B="$W/bare"; mkdir -p "$B/root"
run_bare() { env ROOT="$B/root" APK="$B/n1" IP="$B/n2" PING="$B/n3" WGET="$B/n4" GETENT="$B/n5" DATE="$B/n6" TIMEOUT="$B/n7" \
	"$1" "$HERE/phone-apknet-diag.sh" > "$B/out" 2>&1; }

expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	echo "== $sh, scenario full"
	run_full "$sh" || bad "$sh exits non-zero"
	expect "$F/out" "clock" "Sat Oct 17 14:27:23 UTC 2026"
	expect "$F/out" "epoch" "^1792240000$"
	expect "$F/out" "route" "default via 192\\.168\\.1\\.1"
	expect "$F/out" "resolv.conf" "nameserver 192\\.168\\.1\\.1"
	expect "$F/out" "mtu" "wlan0 mtu: 1500"
	expect "$F/out" "wireless" "wlan0: 0000"
	expect "$F/out" "apk version" "apk-tools 3\\.0\\.0-stub"
	expect "$F/out" "gateway found" "default gateway: 192\\.168\\.1\\.1"
	expect "$F/out" "ping gateway" "PING -c 2 -W 2 192\\.168\\.1\\.1"
	expect "$F/out" "big ping" "PING -c 2 -W 2 -s 1400 1\\.1\\.1\\.1"
	expect "$F/out" "dns" "104\\.16\\.0\\.1 mirror\\.postmarketos\\.org"
	expect "$F/out" "http headers" "HTTP/1\\.1 301 Moved Permanently"
	expect "$F/out" "https url tried" "--- https://mirror\\.postmarketos\\.org"
	expect "$F/out" "apk -vv output" "HTTP: unrecognized server error"
	expect "$F/out" "ends with done" "^done$"
	echo "== $sh, scenario bare"
	run_bare "$sh" || bad "$sh exits non-zero (bare)"
	expect "$B/out" "bare: no date" "\\(no date\\)"
	expect "$B/out" "bare: no ping" "\\(no ping\\)"
	expect "$B/out" "bare: no wget" "\\(no wget\\)"
	expect "$B/out" "bare: no apk" "\\(no apk\\)"
	expect "$B/out" "bare: last section printed" "=== 6 what apk itself says"
	expect "$B/out" "bare: ends with done" "^done$"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
