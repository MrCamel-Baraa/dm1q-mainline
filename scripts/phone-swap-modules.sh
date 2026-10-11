#!/bin/sh
# phone-swap-modules.sh -- ON THE PHONE (busybox sh), as root. Replace the rootfs' kernel-module tree
# /usr/lib/modules/<release> with the one from a tarball made by scripts/refresh-phone-modules.sh (from the
# kernel APK that the flashed boot.img was taken from), keep the old tree as a backup, run depmod.
#
#   sudo sh phone-swap-modules.sh /tmp/dm1q-modules.tar [--reboot]
#
# Why this exists: the rootfs is hand-assembled and built once, the boot images are rebuilt often, and this kernel has
# no MODVERSIONS -- but CONFIG_DEBUG_INFO_BTF_MODULES=y validates every module's BTF against the running vmlinux, and
# without CONFIG_MODULE_ALLOW_BTF_MISMATCH a kernel whose *code* changed (not just its devicetree) refuses EVERY module
# of the old tree with "failed to validate module [x] BTF: -22" (docs/07 section 15.12). No PCIe PHY module -> no pcie0
# -> no wlan0. It touches nothing else: no apk, so /boot/initramfs-extra is not regenerated (docs/06, 2026-10-03 rule).
#
# Safety: the tarball must hold only usr/lib/modules/<release>/..., with at least $MIN_MODULES (1500) modules, a
# modules.dep and the modules the WLAN chain hangs on; otherwise nothing is changed. The old tree is moved (not
# copied) to /var/lib/dm1q-modules-backup/<release>.<date>.<pid>, so a swap is undone with one `mv`.
# Env (tests only): ROOT=<fake root>, MIN_MODULES=<n>, REBOOT_CMD=<cmd>.
set -eu

TAR=""; REBOOT=0
for a in "$@"; do
	case "$a" in
	--reboot) REBOOT=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) TAR="$a" ;;
	esac
done
[ -n "$TAR" ] || { echo "usage: sh phone-swap-modules.sh <modules.tar> [--reboot]" >&2; exit 2; }
ROOT="${ROOT:-}"
MIN="${MIN_MODULES:-1500}"
die() { echo "phone-swap-modules: $*" >&2; exit 1; }
[ -f "$TAR" ] || die "no such file: $TAR"
[ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || die "run it as root (sudo)"
[ -d "$ROOT/usr/lib/modules" ] || die "$ROOT/usr/lib/modules does not exist (not a usr-merged pmOS root?)"

REL=$(tar -tf "$TAR" | sed -n 's#^usr/lib/modules/\([^/][^/]*\)/modules\.dep$#\1#p' | head -n 1)
[ -n "$REL" ] || die "no usr/lib/modules/<release>/modules.dep in $TAR"
BAD=$(tar -tf "$TAR" | grep -v "^usr/lib/modules/$REL/" | head -n 3 || true)
[ -z "$BAD" ] || die "unexpected paths in $TAR (first ones: $BAD)"
if tar -tf "$TAR" | grep -q '/\.\./'; then die "'..' in a path of $TAR"; fi

STAGE="$ROOT/var/lib/dm1q-modules-new.$$"
BAK="$ROOT/var/lib/dm1q-modules-backup"
DST="$ROOT/usr/lib/modules/$REL"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$BAK"
trap 'rm -rf "$STAGE"' EXIT
tar -xf "$TAR" -C "$STAGE"
NEW="$STAGE/usr/lib/modules/$REL"

N=$(find "$NEW" -type f -name '*.ko*' | wc -l)
[ "$N" -ge "$MIN" ] || die "only $N modules in the tarball (need >= $MIN): refusing, nothing changed"
[ -f "$NEW/modules.dep" ] || die "no modules.dep after extraction: nothing changed"
for m in gpucc-sm8550 phy-qcom-qmp-pcie ath11k_pci; do
	[ -n "$(find "$NEW" -name "$m.ko*" | head -n 1)" ] || die "module $m is not in the tarball: refusing, nothing changed"
done

if [ -e "$DST" ]; then
	OLDN=$(find "$DST" -type f -name '*.ko*' | wc -l)
	B="$BAK/$REL.$(date +%Y%m%d-%H%M%S).$$"
	mv "$DST" "$B"
	echo "old tree ($OLDN modules) kept in ${B#"$ROOT"}"
fi
mv "$NEW" "$DST"

RC=0
if command -v depmod >/dev/null 2>&1; then
	if [ -n "$ROOT" ]; then depmod -b "$ROOT" "$REL" || RC=$?; else depmod "$REL" || RC=$?; fi
else
	RC=127
fi
[ "$RC" -eq 0 ] || echo "warning: depmod failed (rc=$RC); the tarball's own modules.* files stay in use"

sync
echo "installed $N modules for kernel release $REL"
echo "running kernel: $(uname -rv)"
if [ "$REBOOT" = 1 ]; then
	echo "rebooting in 2 s"
	nohup sh -c "sleep 2; ${REBOOT_CMD:-reboot}" >/dev/null 2>&1 &
fi
