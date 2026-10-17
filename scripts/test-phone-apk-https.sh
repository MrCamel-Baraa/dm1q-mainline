#!/usr/bin/env bash
# PC-side test of scripts/phone-apk-https.sh (docs/06 rule 3). The phone's /etc/apk is a scratch tree (ROOT=) and apk
# is a stub that fails `update` while any http:// repository is configured (like the real phone behind the ISP
# middlebox) and succeeds once all are https://. Runs with dash (closest to busybox ash) and bash.
# Scenarios: http (rewritten, backup made, update OK, simulation printed), rerun (idempotent, backup untouched),
# failing (update keeps failing -> simulation skipped), noapk, norepos.
# Also checks that every `apk add` call is a --simulate.
# Usage: bash scripts/test-phone-apk-https.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

mkstub() { # $1 dir, $2 mode ok|stuck
	mkdir -p "$1/bin"
	cat > "$1/bin/apk" <<EOF
#!/bin/sh
echo "\$*" >> "$1/apk-calls.log"
case "\$1" in
update)
	if [ "$2" = stuck ] || grep -q '^http://' "$1/root/etc/apk/repositories"; then
		echo "WARNING: updating http://x/APKINDEX.tar.gz: HTTP: unrecognized server error"
		echo "0 unavailable, 5 stale; 37545 distinct packages available"
	else
		echo "OK: 41000 distinct packages available"
	fi ;;
add)
	[ "\$2" = --simulate ] || { echo "REAL ADD ATTEMPTED"; exit 9; }
	echo "(1/4) Installing postmarketos-base-ui (62-r0)"; echo "(2/4) Installing kwin (6.8.0-r0)"
	echo "(3/4) Upgrading mesa (26.2.3-r1 -> 26.2.4-r1)"; echo "(4/4) Installing postmarketos-usb-moded (11-r0)"
	echo "OK: 2700 MiB in 1160 packages" ;;
esac
EOF
	chmod +x "$1/bin/apk"
}

# ---- scenario http, then rerun on the same tree
H="$W/http"; mkdir -p "$H/root/etc/apk"; mkstub "$H" ok
printf 'http://mirror.postmarketos.org/postmarketos/main\nhttp://dl-cdn.alpinelinux.org/alpine/edge/main\nhttps://already.example/x\n' > "$H/root/etc/apk/repositories"
cp "$H/root/etc/apk/repositories" "$W/orig"
run_h() { env ROOT="$H/root" APK="$H/bin/apk" "$1" "$HERE/phone-apk-https.sh" > "$H/out" 2>&1; }

# ---- scenario failing
S="$W/stuck"; mkdir -p "$S/root/etc/apk"; mkstub "$S" stuck
printf 'https://a.example/x\n' > "$S/root/etc/apk/repositories"
run_s() { env ROOT="$S/root" APK="$S/bin/apk" "$1" "$HERE/phone-apk-https.sh" > "$S/out" 2>&1; }

# ---- scenario noapk, norepos
N="$W/noapk"; mkdir -p "$N/root/etc/apk"; printf 'https://a.example/x\n' > "$N/root/etc/apk/repositories"
run_n() { env ROOT="$N/root" APK="$N/none" "$1" "$HERE/phone-apk-https.sh" > "$N/out" 2>&1; }
E="$W/norepos"; mkdir -p "$E/root"
run_e() { env ROOT="$E/root" APK="$E/none" "$1" "$HERE/phone-apk-https.sh" > "$E/out" 2>&1; }

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	# reset the http tree for each shell
	cp "$W/orig" "$H/root/etc/apk/repositories"; rm -f "$H/root/etc/apk/repositories.dm1q-orig" "$H/apk-calls.log"
	echo "== $sh, scenario http (+ rerun)"
	run_h "$sh" || bad "$sh exits non-zero"
	expect "$H/out" "switched message" "switched http:// -> https://"
	reject "$H/root/etc/apk/repositories" "no http:// line left" "^http://"
	expect "$H/root/etc/apk/repositories" "https lines present" "^https://mirror\\.postmarketos\\.org/postmarketos/main$"
	expect "$H/root/etc/apk/repositories" "already-https line kept" "^https://already\\.example/x$"
	if cmp -s "$W/orig" "$H/root/etc/apk/repositories.dm1q-orig"; then ok "backup equals the original"; else bad "backup differs from the original"; fi
	expect "$H/out" "update ok" "UPDATE-STATUS: OK"
	expect "$H/out" "simulation printed" "Installing kwin"
	expect "$H/out" "summary counts" "installs: 3  upgrades: 1  purges: 0"
	expect "$H/out" "pulseaudio count line" "pulseaudio lines: 0"
	expect "$H/out" "selected packages" "Installing postmarketos-usb-moded"
	expect "$H/out" "pipewire pinned in the call" "."; grep -q "add --simulate postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile" "$H/apk-calls.log" && ok "simulate call pins pipewire" || bad "simulate call does not pin pipewire"
	expect "$H/out" "ends with done" "^done$"
	cp "$H/root/etc/apk/repositories" "$W/after1"
	run_h "$sh" || bad "$sh exits non-zero (rerun)"
	expect "$H/out" "rerun: nothing to switch" "nothing to switch"
	cmp -s "$W/after1" "$H/root/etc/apk/repositories" && ok "rerun: file unchanged" || bad "rerun: file changed"
	cmp -s "$W/orig" "$H/root/etc/apk/repositories.dm1q-orig" && ok "rerun: backup still the original" || bad "rerun: backup overwritten"
	reject "$H/out" "no real apk add" "REAL ADD ATTEMPTED"

	echo "== $sh, scenario failing update"
	run_s "$sh" || bad "$sh exits non-zero (failing)"
	expect "$S/out" "failure reported" "UPDATE-STATUS: FAILED"
	expect "$S/out" "simulation skipped" "skipped: the index update did not succeed"
	reject "$S/out" "no simulation output" "Installing kwin"

	echo "== $sh, scenario no apk"
	run_n "$sh" || bad "$sh exits non-zero (noapk)"
	expect "$N/out" "no apk message" "\\(no apk\\)"
	expect "$N/out" "ends with done" "^done$"

	echo "== $sh, scenario no repositories file"
	run_e "$sh"; rc=$?
	[ "$rc" = 1 ] && ok "exit 1 without a repositories file" || bad "exit code $rc, wanted 1"
	expect "$E/out" "no repos message" "no .*repositories"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
