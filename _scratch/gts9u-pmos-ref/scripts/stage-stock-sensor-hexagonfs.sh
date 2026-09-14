#!/bin/sh
set -eu

project=${PROJECT_ROOT:-"/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS"}
vendor=${STOCK_VENDOR_MOUNT:-"/root/pmos-gts9u/stock-extract/vendor"}
dsp=${STOCK_DSP_MOUNT:-"/root/pmos-gts9u/stock-extract/dsp"}
registrygen=${SSCREGISTRYGEN:-}
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi/sensor-hexagonfs.tar.gz"
expected_sha512="b8a29aa8638126e2c5b57a376b6412914e0c778ebb7b30c912413eb47d43f861b616a27f002009ffbc4c88250021c808e4c5c7c5ebd9042dbf6d11ff54cfddd5"

[ -d "$vendor/etc/sensors/config" ] || {
	echo "Stock X910 vendor image is not mounted at $vendor" >&2
	echo "Set STOCK_VENDOR_MOUNT to its read-only mount point." >&2
	exit 1
}
[ -f "$vendor/etc/sensors/sns_reg_config" ] || {
	echo "Missing stock sns_reg_config under $vendor" >&2
	exit 1
}
[ -d "$dsp/adsp" ] || {
	echo "Stock X910 DSP partition is not extracted at $dsp/adsp" >&2
	echo "Set STOCK_DSP_MOUNT to its read-only extracted root." >&2
	exit 1
}

if [ -z "$registrygen" ]; then
	registrygen=$(command -v sscregistrygen 2>/dev/null || true)
fi
if [ -z "$registrygen" ] &&
   [ -x /root/pmos-gts9u/stock-extract/sscregistrygen ]; then
	registrygen=/root/pmos-gts9u/stock-extract/sscregistrygen
fi
[ -x "$registrygen" ] || {
	echo "sscregistrygen is required (Alpine package: sscregistrygen)." >&2
	exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/sensor-hexagonfs"
mkdir -p "$root/dsp/adsp" "$root/sensors/config" "$root/sensors/registry" "$root/socinfo"

cp -a "$vendor/etc/sensors/config/." "$root/sensors/config/"
"$registrygen" -p MTP -s 519 \
	"$root/sensors/config" "$root/sensors/registry"
cp "$vendor/etc/sensors/sns_reg_config" "$root/sensors/sns_reg.conf"

# Samsung's registry service uses this zero-length file as the completion
# marker and the companion JSON as a per-input timestamp cache.  Omitting
# either makes the DSP rebuild the registry through a temp.json + rename
# sequence.  hexagonrpcd 0.4 intentionally exposes HexagonFS read-only, so
# provide the completed cache generated from the same immutable stock JSONs.
: >"$root/sensors/registry/sensors_registry"
python3 - "$root/sensors/config" "$root/sensors/registry/sns_reg_config" <<'PY'
import json
import pathlib
import sys

config = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
entries = {
    f"/vendor/etc/sensors/config/{path.name}": {
        "type": "int",
        "ver": "0",
        # The deterministic tar below normalizes every input mtime to zero.
        # The DSP compares this cache against stat() and rebuilds the whole
        # registry if they differ, so cache the normalized value as well.
        "data": "0",
    }
    for path in sorted(config.glob("*.json"))
}
payload = {"sns_reg_config": {"owner": "NA", **entries}}
output.write_text(json.dumps(payload, separators=(",", ":")))
PY
printf 'version=6\0' >"$root/sensors/sns_reg_version"

# HexagonFS maps this directory to /sys/devices/soc0 inside the ADSP.  Mainline
# qcom-socinfo does not expose these Android-era selector files, so provide the
# board identity used by Samsung's own kailua sensor JSONs explicitly.
printf '%s\n' MTP >"$root/socinfo/hw_platform"
printf '%s\n' 519 >"$root/socinfo/soc_id"
printf '%s\n' 0 >"$root/socinfo/platform_subtype"
printf '%s\n' 0 >"$root/socinfo/platform_subtype_id"
printf '%s\n' 0 >"$root/socinfo/platform_version"

# The Samsung sensors PD asks FastRPC/HexagonFS for these DSP-side skels under
# /usr/lib/qcom/adsp.  They live on the device's dedicated dsp partition, not
# in vendor or in the authenticated adsp.mdt image.  Refuse any other revision:
# the hashes below were measured from the X910 dsp partition mounted ro,noload.
check_and_copy_dsp() {
	file=$1
	expected=$2
	actual=$(sha512sum "$dsp/adsp/$file" | awk '{print $1}')
	[ "$actual" = "$expected" ] || {
		echo "$file SHA-512 mismatch: $actual" >&2
		exit 1
	}
	cp "$dsp/adsp/$file" "$root/dsp/adsp/$file"
}

check_and_copy_dsp libsns_device_mode_skel.so \
	0c59c536a8876298891eb538a3b38ec5e084a00e7cf01c9dd7c2e1f43de8c55afb40357171b5fe368c42c3017bd113c5de235c46bb1d507e2a9b7b80fa586fbb
check_and_copy_dsp libsns_direct_channel_skel.so \
	0759679684d5d7c73f0be8cd224f124c3b30fe1fd75bef61788dc571ed11de4363f5248e3fb5520579a025492bdb77501ee0d36ecbc7854c5c991a49330e218e
check_and_copy_dsp libsns_dynamic_loader_skel.so \
	ec9dc1e092d40fac4ce2adfa1c12e62b6c4898906f6a427f26fe396b8f79290df06643ba5ce7e882eee9299cfe5c14818327919415328870294ead08a723edf2
check_and_copy_dsp libsns_remote_proc_state_skel.so \
	37f88350356eb10b1b943166bfc09f003baca8615aa2a40d555f6991bea032a31f5fd0f4cda6b1cd68ff191c05ad3ddc20315510daae5aa3c404bc8ed8879a9e
check_and_copy_dsp sns_tppe.so \
	f68e3f8f6db015b172b28c542b01a091826fae961689372da4847e48e64aa3db83f921887117441ddc71342267424b4a694e931ab323fe7bd9c77d7ca8d97b04

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
	-C "$tmp" -czf "$target.tmp" sensor-hexagonfs
mv "$target.tmp" "$target"

actual=$(sha512sum "$target" | awk '{print $1}')
if [ "${ALLOW_UNPINNED_SENSOR_HEXAGONFS:-0}" != 1 ] &&
   [ "$actual" != "$expected_sha512" ]; then
	echo "sensor-hexagonfs.tar.gz SHA-512 mismatch: $actual" >&2
	exit 1
fi

echo "Staged deterministic X910 HexagonFS sensor tree: $actual"
