#!/bin/sh
set -eu

project=${PROJECT_ROOT:-"/mnt/c/Users/agcar/Desktop/Aplicaciones/Custom Roms/GALAXY TAB S9 ULTRA/Ubuntu Touch/PostmarketOS"}
opensource=${SAMSUNG_OPENSOURCE_ZIP:-"$project/SM-X910_EUR_16_Opensource.zip"}
target="$project/pmaports/device/testing/firmware-samsung-gts9uwifi"
prefix="./vendor/qcom/opensource/audio-hal/primary-hal/configs/kalama/audconf/gts9uwifi"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ -f "$opensource" ] || {
	echo "Samsung open-source archive not found: $opensource" >&2
	exit 1
}

check_sha512()
{
	expected=$1
	file=$2
	actual=$(sha512sum "$target/$file" 2>/dev/null | awk '{print $1}')
	[ "$actual" = "$expected" ]
}

# Avoid re-reading Samsung's 640 MB nested Kernel.tar.gz on every build.
if check_sha512 445b111839461d5028cd3e66756f868a5af1cc08e230304a536534ea58d5983ba62d83b1fe82b2c222b5a95fbd46e6d0fe917a352243ff31abeb307a4357a1f1 cs35l45-dsp1-spk-prot.wmfw &&
   check_sha512 f06cd4296eb9f2e1c5d72f28673c2d7f035688fb15ba9caf81c0f54a19c16b3ba6726aaa6a17f4370520e4e472a14f4748b724bbed495dd2111aae2896f44338 cs35l45-dsp1-spk-prot.bin &&
   check_sha512 2879c4dead57922ec74702ae07b382b6ff0fe859b671ae1ebaa2a666f25c67190a3ccd29ee5d2c4d6ed89078daef60ac2d39ade9f943aed02245f77b72c69a72 cs35l45-dsp1-spk-prot-calib.bin
then
	echo "SM-X910 CS35L45 speaker-protection firmware already verified."
	exit 0
fi

# Kernel.tar.gz is nested inside Samsung's ZIP. Keep the 640 MB intermediary
# outside the repository and extract only the three X910 CS35L45 DSP files.
unzip -p "$opensource" Kernel.tar.gz > "$tmp/Kernel.tar.gz"
for file in \
	cs35l45-dsp1-spk-prot.wmfw \
	cs35l45-dsp1-spk-prot.bin \
	cs35l45-dsp1-spk-prot-calib.bin
do
	tar -xzOf "$tmp/Kernel.tar.gz" "$prefix/$file" > "$target/$file"
done

assert_sha512()
{
	expected=$1
	file=$2
	actual=$(sha512sum "$target/$file" | awk '{print $1}')
	[ "$actual" = "$expected" ] || {
		echo "$file: SHA-512 mismatch: $actual" >&2
		exit 1
	}
}

assert_sha512 445b111839461d5028cd3e66756f868a5af1cc08e230304a536534ea58d5983ba62d83b1fe82b2c222b5a95fbd46e6d0fe917a352243ff31abeb307a4357a1f1 cs35l45-dsp1-spk-prot.wmfw
assert_sha512 f06cd4296eb9f2e1c5d72f28673c2d7f035688fb15ba9caf81c0f54a19c16b3ba6726aaa6a17f4370520e4e472a14f4748b724bbed495dd2111aae2896f44338 cs35l45-dsp1-spk-prot.bin
assert_sha512 2879c4dead57922ec74702ae07b382b6ff0fe859b671ae1ebaa2a666f25c67190a3ccd29ee5d2c4d6ed89078daef60ac2d39ade9f943aed02245f77b72c69a72 cs35l45-dsp1-spk-prot-calib.bin

echo "Staged and verified the SM-X910 CS35L45 speaker-protection firmware."
