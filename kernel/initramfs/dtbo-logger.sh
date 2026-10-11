# dtbo-logger.sh -- sourced by the pmOS stage-1 /init right after
# mount_proc_sys_dev (injected by scripts/make-boot-images.sh).
#
# Flushes the kernel log (plus pmOS's own /pmOS_init.log, which records what
# the initramfs itself did) into the dtbo partition at a 1 MiB offset every
# 3 s. dtbo is deliberately an invalid image on dm1q, so it is free space.
# Read it from recovery with:
#   adb exec-out "dd if=/dev/block/by-name/dtbo bs=1M skip=1 count=4" | strings
# Runs in the background and never writes to the console, so it survives a
# console hang. NOTE: it lives in the initramfs, so once the real rootfs is
# switched to it stops updating.
(
  D=""
  while true; do
    if [ -z "$D" ]; then
      for u in /sys/class/block/*/uevent; do
        grep -q '^PARTNAME=dtbo$' "$u" 2>/dev/null || continue
        NAME=$(grep '^DEVNAME=' "$u" | cut -d= -f2)
        [ -n "$NAME" ] && D="/dev/$NAME"
      done
    fi
    { dmesg; echo; echo "=== /pmOS_init.log ==="; cat /pmOS_init.log 2>/dev/null; } > /tmp/klog.txt 2>&1
    SZ=$(wc -c < /tmp/klog.txt)
    if [ -n "$D" ] && [ "$SZ" -gt 0 ] && [ "$SZ" -lt 4194304 ]; then
      dd if=/tmp/klog.txt of="$D" bs=1M seek=1 conv=notrunc 2>/dev/null
    fi
    # plain "sleep" is not guaranteed to be installed as a standalone
    # applet in the pmOS initramfs (found 2026-09-28: "sleep not found" on
    # the real device, even though dmesg/cat/dd/grep/wc all resolved fine)
    # -- busybox itself is always present since it's what's running this
    # script, so call the applet through it explicitly.
    busybox sleep 3
  done
) &
