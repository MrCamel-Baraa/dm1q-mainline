#!/usr/bin/env bash
# PC-side test of scripts/phone-plasma-install.sh (docs/06 rule 3). The phone's root is a scratch tree (ROOT=); apk,
# systemctl, df and sha256sum are stubs. The apk stub's `add` takes a few seconds, writes progress lines and
# CHANGES the fake /boot/initramfs-extra (like the real mkinitfs trigger). Runs with dash (closest to busybox ash)
# and bash. Scenarios:
#   good      http-free repos, free space: pre-install snapshot, mask, detached install, change detection, units, banner
#   resume    the same tree again: no second install, no second backup, post-checks only
#   http      repositories still http:// -> abort before touching anything
#   nospace   df reports too little -> abort
#   enabled   the install leaves plasma-mobile.service enabled -> the script disables it
#   killed    the follow loop is cut short (MAXWAIT) while the install runs: it keeps running and a second run finishes
# Also asserts: exactly one real `apk add` per tree, with the pipewire backend pinned; nothing is ever started or rebooted.
# Usage: bash scripts/test-phone-plasma-install.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

mktree() { # $1 dir, $2 repo scheme, $3 free kb on /, $4 enable-units-after-install (0/1)
	local D="$1" R="$1/root"
	mkdir -p "$D/bin" "$R/etc/apk" "$R/boot" "$R/lib/apk/db" "$R/etc/systemd/system" "$R/sys/kernel/config/usb_gadget/g1/functions/ncm.usb0"
	printf '%s://mirror.postmarketos.org/postmarketos/main\n%s://dl-cdn.alpinelinux.org/alpine/edge/main\n' "$2" "$2" > "$R/etc/apk/repositories"
	( cd "$D" && mkdir -p cpio-src/usr/lib && ln -s usr/lib cpio-src/lib && touch cpio-src/usr/lib/x && cd cpio-src && printf 'lib\nusr\nusr/lib\nusr/lib/x\n' | cpio -o -H newc 2>/dev/null | gzip > /dev/null )
	echo "original working initramfs-extra" | gzip > "$R/boot/initramfs-extra"
	echo "mkinitfs /usr/lib/udev" > "$R/lib/apk/db/triggers"
	echo "a7f4e2" > "$R/sys/kernel/config/usb_gadget/g1/UDC"
	echo "user" > "$R/etc/default_user"
	cat > "$D/bin/apk" <<EOF
#!/bin/sh
echo "\$*" >> "$D/apk-calls.log"
case "\$1" in
info)
	if [ "\$2" = -v ]; then echo "busybox-1.37-r0"; echo "mesa-26.2.3-r1"; exit 0; fi
	if [ "\$2" = -L ]; then echo "plasma-mobile-systemd-6.8.0-r0 contains:"; echo "usr/lib/systemd/system/plasma-mobile.service"; exit 0; fi
	echo busybox; echo mesa ;;
add)
	[ "\$2" = --simulate ] && exit 0
	sleep 3
	echo "(1/3) Installing plasma-mobile (6.8.0-r0)"
	sleep 1
	echo "(2/3) Installing kwin (99996.8.0-r0)"
	# the mkinitfs trigger regenerates the file
	echo "regenerated initramfs-extra with usr-merge symlinks" | gzip > "$R/boot/initramfs-extra"
	echo "(3/3) Installing postmarketos-usb-moded (11-r0)"
	if [ "$4" = 1 ]; then echo enabled > "$D/plasma-enabled"; fi
	echo "OK: 2761.0 MiB in 1155 packages" ;;
esac
EOF
	cat > "$D/bin/systemctl" <<EOF
#!/bin/sh
echo "\$*" >> "$D/systemctl-calls.log"
case "\$1" in
is-enabled)
	case "\$2" in
	plasma-mobile.service|display-manager.service)
		if [ -e "$D/plasma-enabled" ] && [ ! -e "$D/plasma-disabled" ]; then echo enabled; else echo disabled; fi ;;
	usb-moded.service) if [ -e "$D/masked" ]; then echo masked; else echo disabled; fi ;;
	*) echo enabled ;;
	esac ;;
is-active) echo inactive ;;
mask) touch "$D/masked"; echo "Created symlink /etc/systemd/system/\$2 -> /dev/null" ;;
disable) touch "$D/plasma-disabled"; echo "Removed \$2" ;;
cat) echo "# /usr/lib/systemd/system/plasma-mobile.service"; echo "[Service]"; echo "ExecStart=/usr/bin/startplasma-wayland" ;;
list-unit-files) echo "usb-moded.service disabled"; echo "NetworkManager.service enabled" ;;
esac
EOF
	printf '#!/bin/sh\necho "Filesystem 1K-blocks Used Available Use%% Mounted on"\necho "/dev/x 100 1 %s 1%% /"\n' "$3" > "$D/bin/df"
	cat > "$D/bin/sha256sum" <<'EOF'
#!/bin/sh
for f in "$@"; do printf '%s  %s\n' "$(cksum < "$f" | cut -d' ' -f1)" "$f"; done
EOF
	chmod +x "$D"/bin/*
}
runit() { # $1 shell, $2 dir, $3 outfile, extra env...
	local sh="$1" D="$2" out="$3"; shift 3
	env ROOT="$D/root" APK="$D/bin/apk" SYSTEMCTL="$D/bin/systemctl" DF="$D/bin/df" SHA="$D/bin/sha256sum" POLL=1 MAXWAIT=60 "$@" \
		"$sh" "$HERE/phone-plasma-install.sh" > "$out" 2>&1
}
real_adds() { grep -c '^add ' "$1/apk-calls.log" 2>/dev/null || echo 0; }

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }

	echo "== $sh, scenario good"
	G="$W/good-$sh"; mktree "$G" https 90000000 0
	runit "$sh" "$G" "$G/out" || bad "$sh exits non-zero"
	expect "$G/out" "https guard passed" "repositories: https only"
	expect "$G/out" "free space shown" "free on /: 90000000 kB"
	expect "$G/out" "snapshot saved" "saved initramfs-extra\\.pre-plasma"
	if [ "$(gzip -dc "$G/root/root/dm1q-plasma/initramfs-extra.pre-plasma")" = "original working initramfs-extra" ]; then ok "backup holds the original"; else bad "backup differs from the original"; fi
	expect "$G/out" "usb-moded masked" "Created symlink .*usb-moded\\.service"
	expect "$G/out" "install progress followed" "Installing kwin"
	expect "$G/out" "finish marker seen" "install finished, rc=0"
	expect "$G/out" "change detected" "INITRAMFS-EXTRA: CHANGED"
	expect "$G/out" "units listed" "plasma-mobile\\.service: "
	expect "$G/out" "unit file printed" "ExecStart=/usr/bin/startplasma-wayland"
	expect "$G/out" "default_user shown" "^user$"
	expect "$G/out" "apk -L listing" "plasma-mobile-systemd-6\\.8\\.0-r0 contains"
	expect "$G/out" "gadget still listed" "gadget g1: UDC=a7f4e2 functions=ncm\\.usb0"
	expect "$G/out" "reboot warning" "DO NOT REBOOT INTO THE SYSTEM"
	expect "$G/out" "ends with done" "^done$"
	[ "$(real_adds "$G")" = 1 ] && ok "exactly one real apk add" || bad "real apk add count is $(real_adds "$G")"
	grep -q "^add postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile$" "$G/apk-calls.log" && ok "pipewire backend pinned in the real call" || bad "real call is not the pinned one"
	reject "$G/systemctl-calls.log" "never started or rebooted anything" "^(start|restart|reboot|poweroff|enable) "
	[ ! -e "$G/plasma-disabled" ] && ok "nothing disabled when nothing was enabled" || bad "disable called although units were not enabled"

	echo "== $sh, scenario resume (same tree)"
	runit "$sh" "$G" "$G/out2" || bad "$sh exits non-zero (resume)"
	expect "$G/out2" "no second install" "install log already exists"
	expect "$G/out2" "post-checks still run" "INITRAMFS-EXTRA: "
	[ "$(real_adds "$G")" = 1 ] && ok "still exactly one real apk add" || bad "second apk add happened ($(real_adds "$G"))"
	if [ "$(gzip -dc "$G/root/root/dm1q-plasma/initramfs-extra.pre-plasma")" = "original working initramfs-extra" ]; then ok "backup NOT overwritten by the rerun"; else bad "backup overwritten by the rerun"; fi

	echo "== $sh, scenario http"
	H="$W/http-$sh"; mktree "$H" http 90000000 0
	runit "$sh" "$H" "$H/out"; rc=$?
	[ "$rc" = 1 ] && ok "exit 1" || bad "exit code $rc, wanted 1"
	expect "$H/out" "abort message" "still has http:// lines"
	[ ! -e "$H/apk-calls.log" ] || ! grep -q '^add ' "$H/apk-calls.log" && ok "no apk add" || bad "apk add ran"
	[ ! -e "$H/root/root/dm1q-plasma/install.log" ] && ok "no install log" || bad "install log created"

	echo "== $sh, scenario nospace"
	N="$W/nospace-$sh"; mktree "$N" https 1000 0
	runit "$sh" "$N" "$N/out"; rc=$?
	[ "$rc" = 1 ] && ok "exit 1" || bad "exit code $rc, wanted 1"
	expect "$N/out" "abort message" "not enough free space"
	[ ! -e "$N/apk-calls.log" ] || ! grep -q '^add ' "$N/apk-calls.log" && ok "no apk add" || bad "apk add ran"

	echo "== $sh, scenario enabled"
	E="$W/enabled-$sh"; mktree "$E" https 90000000 1
	runit "$sh" "$E" "$E/out" || bad "$sh exits non-zero (enabled)"
	expect "$E/out" "enabled unit disabled" "plasma-mobile\\.service is enabled: disabling it"
	[ -e "$E/plasma-disabled" ] && ok "disable was called" || bad "disable not called"
	expect "$E/out" "final state reported" "now: plasma-mobile=disabled"

	echo "== $sh, scenario killed follow-up"
	K="$W/killed-$sh"; mktree "$K" https 90000000 0
	runit "$sh" "$K" "$K/out" MAXWAIT=1 ; rc=$?
	[ "$rc" = 2 ] && ok "exit 2 when the follow loop gives up" || bad "exit code $rc, wanted 2"
	expect "$K/out" "gave up message" "the install continues in the background"
	sleep 6
	grep -q '^INSTALL-FINISHED rc=0' "$K/root/root/dm1q-plasma/install.log" && ok "detached install finished on its own" || bad "detached install did not finish"
	runit "$sh" "$K" "$K/out2" || bad "$sh exits non-zero (second run)"
	expect "$K/out2" "second run finishes the job" "INITRAMFS-EXTRA: CHANGED"
	[ "$(real_adds "$K")" = 1 ] && ok "still exactly one real apk add" || bad "apk add count $(real_adds "$K")"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
