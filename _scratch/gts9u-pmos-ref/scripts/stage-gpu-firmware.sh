#!/bin/bash
# Stage the Adreno 740 GPU firmware from the extracted Samsung vendor image.
# The zap shader must be signed for this device's TrustZone, so the Samsung
# a740_zap MDT set is mandatory; SQE and GMU microcode are the same bytes as
# linux-firmware but taken from the same source for consistency.  Proprietary
# blobs are never versioned (see the firmware package .gitignore); this script
# regenerates them with pinned checksums.
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
project="${PROJECT_MNT:-/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS}"
vendor="${STOCK_VENDOR_EXTRACTED:-$base/stock-vendor-extracted}"
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"
src="$vendor/firmware"

test -f "$src/a740_zap.mdt"

for f in a740_zap.mdt a740_zap.b00 a740_zap.b01 a740_zap.b02 a740_sqe.fw gmu_gen70200.bin; do
	install -m 0644 "$src/$f" "$target/$f"
done

cd "$target"
sha256sum -c <<'EOF'
2b9182eb29e7879b8d55250e8f787a45872a9f7bd2dc52c2b467ba8c0c571dc3  a740_zap.mdt
2fb7b6afa4387a8ba81e1faf0c35ac1c6fd6294118426d5b45946d75f4e3e339  a740_zap.b00
21c0afb7418fe901d688327bbc7423898cc3d6ca93d77adff8294c6fca30fbcd  a740_zap.b01
3931bf248b84722f3ebcbe92377e7aeda9afbea7a45d8d21857d142f9abce201  a740_zap.b02
96fee336424b139100fc60b5b45a907360e4b3936d7e1d00406b9bd80ca48473  a740_sqe.fw
1a2a419c39046d3141fc5fed5aa7f971de2db40cc7a1d89693c3e26fad64dd98  gmu_gen70200.bin
EOF
