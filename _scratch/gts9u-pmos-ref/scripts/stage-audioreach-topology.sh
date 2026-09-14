#!/bin/sh
set -eu

project=${PROJECT_ROOT:-"/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS"}
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"
output="$target/Samsung-Galaxy-Tab-S9-Ultra-tplg.bin"
repo=https://gitlab.com/kernel-firmware/linux-firmware.git
commit=18cf97993f06c0a28d88cee30b7b646807642acd
# SHA-512 of the pinned upstream SM8550-HDK topology, before the X910 fix below.
upstream_expected=d41185a9c905571f7c234ff8caf6e6d24870161a5e6ef0316bb997bfd26cee871a483287308a0af177d39a81b256def4cfa99b0f2594b364ba7ef1104dd9caca
# SHA-512 after retargeting the I2S sink to SD1 (a single byte differs).
expected=0c36213640a9c8d8ddbe76ad9b948ff2eb0b063803c6d5906cef2407628ec92e23adc279eb3fe150dc0fd75d8b01a22bca21fc16466d9b8a69775fdb31bdf410

verify()
{
	[ -f "$output" ] || return 1
	actual=$(sha512sum "$output" | awk '{print $1}')
	[ "$actual" = "$expected" ]
}

if verify; then
	echo "Pinned SM8550 AudioReach topology already verified."
	exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fetch only the pinned linux-firmware tree and materialize the SM8550
# directory. The binary is the BSD-3-Clause linux-msm/audioreach-topology
# v1.0.4 output; pinning both commit and hash makes the staging reproducible.
git -C "$tmp" init -q
git -C "$tmp" remote add origin "$repo"
git -C "$tmp" -c protocol.version=2 fetch -q --depth=1 --filter=blob:none origin "$commit"
git -C "$tmp" sparse-checkout init --cone
git -C "$tmp" sparse-checkout set qcom/sm8550
git -C "$tmp" checkout -q --detach FETCH_HEAD

install -m 0644 "$tmp/qcom/sm8550/SM8550-HDK-tplg.bin" "$tmp/staged.bin"
upstream=$(sha512sum "$tmp/staged.bin" | awk '{print $1}')
[ "$upstream" = "$upstream_expected" ] || {
	echo "Upstream AudioReach topology SHA-512 mismatch" >&2
	exit 1
}

# Retarget the I2S sink module's serial-data line for the X910.
#
# The HDK/QRD/MTP boards never actually use MI2S (they are codec-DMA only), so
# their I2S module is left on I2S_SD0 (token value 1).  On this tablet the four
# CS35L45 amplifiers hang off PRIMARY MI2S, and Samsung's own pinctrl names
# gpio127/i2s0_data0 as tdm0_din (the amplifiers' feedback into the SoC) and
# gpio128/i2s0_data1 as tdm0_dout, so playback has to leave the SoC on
# I2S_SD1 (token value 2).  Sending it on SD0 reaches nothing and the amplifier
# PLLs never lock.  TALOS-EVK, the one upstream board that really drives MI2S
# through this same machine driver, likewise ships sd_line = 2, and its I2S
# module is otherwise token-for-token identical to this one.
#
# Patching the single token keeps the rest of the pinned binary untouched and
# verifiable: exactly one byte changes.
python3 - "$tmp/staged.bin" "$output" <<'PY'
import struct, sys

src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())

MODULE_ID_I2S_SINK = 0x0700100A
AR_TKN_U32_MODULE_SD_LINE_IDX = 256
I2S_SD1 = 2

needle = struct.pack('<I', MODULE_ID_I2S_SINK)
module = data.find(needle)
if module < 0:
    raise SystemExit('no I2S sink module in the topology')
if data.find(needle, module + 1) >= 0:
    raise SystemExit('more than one I2S sink module; refusing to guess')

patched = 0
for off in range(module, min(module + 200, len(data) - 8), 4):
    token, value = struct.unpack_from('<II', data, off)
    if token == AR_TKN_U32_MODULE_SD_LINE_IDX and value == 1:
        struct.pack_into('<I', data, off + 4, I2S_SD1)
        patched += 1

if patched != 1:
    raise SystemExit(f'expected one sd_line token, patched {patched}')

open(dst, 'wb').write(bytes(data))
PY

verify || {
	echo "Patched AudioReach topology SHA-512 mismatch" >&2
	exit 1
}

echo "Staged the pinned SM8550 AudioReach topology with the X910 SD1 fix."
