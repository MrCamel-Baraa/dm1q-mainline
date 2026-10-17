#!/bin/sh
# Read-only diagnosis of "apk update" failing on the phone (docs/10 section 5: all five repositories answered
# "HTTP: unrecognized server error" in the 2026-10-17 preflight). Runs on the phone as root (sudo sh
# phone-apknet-diag.sh), POSIX sh / busybox ash. It changes nothing except that `apk update -vv` may refresh the
# index cache if the network turns out fine. It prints no SSIDs and no MACs.
#
# It answers, in order: is the clock sane, what are the route / DNS / MTU / signal, do ICMP, DNS, plain HTTP
# and HTTPS reach the mirrors (with the response headers), and what does apk itself say with -vv.
#
# Test overrides (scripts/test-phone-apknet-diag.sh): ROOT, APK, IP, PING, WGET, GETENT, DATE, TIMEOUT.
ROOT="${ROOT:-}"
APK="${APK:-apk}"; IP="${IP:-ip}"; PING="${PING:-ping}"; WGET="${WGET:-wget}"
GETENT="${GETENT:-getent}"; DATE="${DATE:-date}"; TIMEOUT="${TIMEOUT:-timeout}"

sec() { echo; echo "=== $1"; }
have() { command -v "$1" >/dev/null 2>&1; }
tmo() { # tmo SECONDS cmd args... : run with a time limit when timeout exists
	s="$1"; shift
	if have "$TIMEOUT"; then "$TIMEOUT" "$s" "$@" 2>&1; else "$@" 2>&1; fi
}
show() { if [ -r "$1" ]; then cat "$1"; else echo "  (absent: ${1#"$ROOT"})"; fi; }

sec "1 clock"
if have "$DATE"; then "$DATE" -u; "$DATE" +%s; else echo "  (no date)"; fi

sec "2 route, DNS, MTU, signal"
if have "$IP"; then "$IP" route 2>&1; else echo "  (no ip)"; fi
echo "--- /etc/resolv.conf"; show "$ROOT/etc/resolv.conf"
echo "wlan0 mtu: $(cat "$ROOT/sys/class/net/wlan0/mtu" 2>/dev/null || echo '?')"
echo "usb0 mtu: $(cat "$ROOT/sys/class/net/usb0/mtu" 2>/dev/null || echo '?')"
echo "--- /proc/net/wireless"; show "$ROOT/proc/net/wireless"
echo "--- proxy environment:"; env | grep -i proxy || echo "  (none)"
echo "--- apk"
if have "$APK"; then "$APK" --version 2>&1; else echo "  (no apk)"; fi
ls -ld "$ROOT/etc/apk/cache" "$ROOT/var/cache/apk" 2>&1
ls -l "$ROOT/var/cache/apk" 2>&1 | head -12

sec "3 ICMP"
GW=""
if have "$IP"; then GW="$("$IP" route 2>/dev/null | awk '/^default/ { print $3; exit }')"; fi
echo "default gateway: ${GW:-none}"
if have "$PING"; then
	[ -n "$GW" ] && { echo "--- ping gateway"; tmo 10 "$PING" -c 2 -W 2 "$GW"; }
	echo "--- ping 1.1.1.1"; tmo 10 "$PING" -c 2 -W 2 1.1.1.1
	echo "--- ping 1.1.1.1, 1400-byte payload (path MTU hint)"; tmo 10 "$PING" -c 2 -W 2 -s 1400 1.1.1.1
else
	echo "  (no ping)"
fi

sec "4 DNS"
for h in dl-cdn.alpinelinux.org mirror.postmarketos.org; do
	if have "$GETENT"; then echo "--- $h"; tmo 10 "$GETENT" hosts "$h" || echo "  (no answer)"; else echo "  (no getent)"; fi
done

sec "5 HTTP and HTTPS fetch of the aarch64 indexes (headers only; body goes to /dev/null)"
if have "$WGET"; then
	for u in \
		http://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/APKINDEX.tar.gz \
		http://mirror.postmarketos.org/postmarketos/main/aarch64/APKINDEX.tar.gz \
		https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/APKINDEX.tar.gz \
		https://mirror.postmarketos.org/postmarketos/main/aarch64/APKINDEX.tar.gz; do
		echo "--- $u"
		tmo 40 "$WGET" -S -T 20 -O /dev/null "$u" 2>&1 | head -25
	done
else
	echo "  (no wget)"
fi

sec "6 what apk itself says"
if have "$APK"; then
	tmo 90 "$APK" update -vv 2>&1 | head -60
else
	echo "  (no apk)"
fi

echo
echo "done"
