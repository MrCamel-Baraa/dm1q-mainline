#!/usr/bin/env bash
# Put the kernel-module tree of a kernel APK into the phone's rootfs over the phone's USB network
# (scripts/phone-swap-modules.sh does the swap on the phone). Run it yourself, in a terminal, while the PC is on the
# phone's USB network (never both USB network and internet); when it says "done", reconnect to the internet.
#
# Why: after a kernel rebuild whose CODE changed (any patch, not only DTS/config), every module of the old tree is
# refused with "failed to validate module [x] BTF: -22" -- no PCIe PHY, no pcie0, no wlan0 (docs/07 section 15.12).
# The rootfs' /usr/lib/modules/<release> must come from the same APK as the flashed boot.img's kernel.
#
# Usage:  scripts/refresh-phone-modules.sh [--apk FILE] [--reboot] [--dry-run]
#   --apk FILE   the kernel APK (default: the newest linux-samsung-dm1q-mainline-*.apk in pmbootstrap's
#                packages/edge/aarch64 -- it must be the one whose vmlinuz is inside the boot.img you flashed)
#   --reboot     reboot the phone at the end (the phone script schedules it 2 s after it finishes)
#   --dry-run    only unpack the APK and build the tarball (shows release + module count), do not touch the phone
#   --tar-out F  also keep a copy of the tarball as F (for tests / manual use)
# Env:  PHONE=172.16.42.1  PHONE_USER=user  WAIT_PING=240
# Asks twice for passwords: the ssh login, then sudo on the phone. Nothing else on the phone is changed
# (no apk, so /boot/initramfs-extra is untouched); the old tree is kept in /var/lib/dm1q-modules-backup/.
set -u
APK=""; REBOOT=0; DRY=0; TAR_OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
	--apk) shift; APK="${1:-}" ;;
	--reboot) REBOOT=1 ;;
	--dry-run) DRY=1 ;;
	--tar-out) shift; TAR_OUT="${1:-}" ;;
	-h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
PHONE="${PHONE:-172.16.42.1}"
PUSER="${PHONE_USER:-user}"
WAIT_PING="${WAIT_PING:-240}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$APK" ]; then
	APK="$(find "$HOME/.local/var/pmbootstrap/packages/edge/aarch64" -maxdepth 1 -name "linux-samsung-dm1q-mainline-*.apk" 2>/dev/null | sort -V | tail -n 1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || { echo "no kernel APK found (use --apk FILE)"; exit 1; }
MIN_MODULES="${MIN_MODULES:-1500}"

WORK="$(mktemp -d /tmp/dm1q-modules.XXXXXX)"
CP="/tmp/dm1q-ssh-$$"
SSH_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR
          -o ControlPath="$CP" -o ConnectTimeout=10)
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() { ssh "${SSH_OPTS[@]}" -O exit "$PUSER@$PHONE" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

echo "== unpacking the module tree from $(basename "$APK")"
tar -xzf "$APK" -C "$WORK" --wildcards 'usr/lib/modules/*' 2>/dev/null
[ -d "$WORK/usr/lib/modules" ] || { echo "no usr/lib/modules in $APK"; exit 1; }
RELS="$(ls -1 "$WORK/usr/lib/modules")"
[ "$(printf '%s\n' "$RELS" | wc -l)" = 1 ] || { echo "expected exactly one release dir, found: $RELS"; exit 1; }
REL="$RELS"
N="$(find "$WORK/usr/lib/modules/$REL" -type f -name '*.ko*' | wc -l)"
[ "$N" -ge "$MIN_MODULES" ] || { echo "only $N modules in the APK (need >= $MIN_MODULES)"; exit 1; }
[ -f "$WORK/usr/lib/modules/$REL/modules.dep" ] || { echo "the APK has no modules.dep"; exit 1; }
tar -C "$WORK" --owner=0 --group=0 --numeric-owner -cf "$WORK/dm1q-modules.tar" "usr/lib/modules/$REL" || { echo "tar failed"; exit 1; }
echo "release $REL, $N modules, tarball $(du -h "$WORK/dm1q-modules.tar" | cut -f1)"
[ -n "$TAR_OUT" ] && { cp "$WORK/dm1q-modules.tar" "$TAR_OUT" && echo "tarball copied to $TAR_OUT"; }
[ "$DRY" = 1 ] && { echo "dry run: the phone was not touched"; exit 0; }

t=0
echo "== waiting up to ${WAIT_PING}s for the phone at $PHONE (connect the PC to the phone's USB network if it does not switch by itself)"
until ping -c1 -W1 "$PHONE" >/dev/null 2>&1; do
	sleep 2; t=$((t + 3)); [ $((t % 30)) -lt 3 ] && echo "  ... ${t}s"
	[ "$t" -ge "$WAIT_PING" ] && { echo "no answer from $PHONE after ${WAIT_PING}s"; exit 1; }
done
t=0; until timeout 3 bash -c "exec 3<>/dev/tcp/$PHONE/22" 2>/dev/null; do
	sleep 2; t=$((t + 3)); [ "$t" -ge 90 ] && { echo "ssh port 22 never opened"; exit 1; }
done
echo "== log in (password prompt; the connection is reused afterwards)"
ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -o ControlPersist=900 -fN "$PUSER@$PHONE" || { echo "ssh login failed"; exit 1; }
echo "== copying the tarball (~$(du -m "$WORK/dm1q-modules.tar" | cut -f1) MB) and the swap script"
scp "${SSH_OPTS[@]}" -q "$WORK/dm1q-modules.tar" "$REPO/scripts/phone-swap-modules.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp failed"; exit 1; }
RB=""; [ "$REBOOT" = 1 ] && RB=" --reboot"
echo "== swapping the module tree on the phone (sudo asks for the password)"
ssh "${SSH_OPTS[@]}" -t "$PUSER@$PHONE" "sudo sh /tmp/phone-swap-modules.sh /tmp/dm1q-modules.tar$RB; rc=\$?; rm -f /tmp/dm1q-modules.tar /tmp/phone-swap-modules.sh; exit \$rc"
rc=$?
if [ "$rc" -ne 0 ]; then echo "the swap FAILED (rc=$rc): see the messages above; the phone's module tree was not changed unless it says 'old tree ... kept'"; exit "$rc"; fi
echo "done."
[ "$REBOOT" = 1 ] && echo "The phone reboots now. Give it ~1 minute, then check wlan0 (reconnect to the internet first if you like) and tell Claude."
[ "$REBOOT" = 1 ] || echo "Reboot the phone (sudo reboot) to start a clean boot with the new modules."
exit 0
