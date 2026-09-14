#!/bin/bash
set -euo pipefail

out=PostmarketOS/work
dtb="$out/live-device-tree.dtb"
dts="$out/live-device-tree.dts"

: "${GTS9U_PW:?set GTS9U_PW to the sudo password on the device}"

bash port/scripts/ssh.sh \
    "printf '%s\\n' '$GTS9U_PW' | sudo -S -p '' cat /sys/firmware/fdt" > "$dtb"

test "$(stat -c %s "$dtb")" -gt 100000
sha256sum "$dtb"

if command -v dtc >/dev/null 2>&1; then
    dtc -I dtb -O dts -o "$dts" "$dtb"
    echo "generated $dts"
else
    echo 'dtc is not installed; DTB captured but not decompiled'
fi
