#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
tag="${LINUX_TAG:-v7.2-rc3}"
target="$base/linux-mainline"

if [ ! -d "$target/.git" ]; then
    git clone --depth 1 --branch "$tag" \
        https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
        "$target"
else
    echo "already present: $target"
fi

git -C "$target" describe --always --dirty
find "$target/arch/arm64/boot/dts/qcom" -maxdepth 1 -type f \
    \( -name '*sm8550*.dts' -o -name '*sm8550*.dtsi' \) \
    -printf '%f\n' | sort
