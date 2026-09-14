#!/bin/bash
set -euo pipefail

base="${PMOS_WORKDIR:-/root/pmos-gts9u}"
mkdir -p "$base"

clone_if_missing() {
    local url="$1"
    local target="$2"
    if [ ! -d "$target/.git" ]; then
        git clone --depth 1 "$url" "$target"
    else
        echo "already present: $target"
    fi
}

clone_if_missing \
    https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git \
    "$base/pmbootstrap"
clone_if_missing \
    https://gitlab.postmarketos.org/postmarketOS/pmaports.git \
    "$base/pmaports"

python3 "$base/pmbootstrap/pmbootstrap.py" --version
git -C "$base/pmbootstrap" rev-parse HEAD
git -C "$base/pmaports" rev-parse HEAD
