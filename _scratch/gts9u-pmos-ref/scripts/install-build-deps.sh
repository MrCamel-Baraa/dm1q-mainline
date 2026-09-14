#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
	bc \
	bison \
	build-essential \
	clang \
	cpio \
	device-tree-compiler \
	dwarves \
	flex \
	libelf-dev \
	libssl-dev \
	lld \
	llvm \
	lz4 \
	patch \
	pkg-config \
	python3 \
	rsync \
	zstd
