#!/bin/sh
set -eu

for command in clang ld.lld make flex bison pahole openssl python3 dtc cpio lz4; do
	if path=$(command -v "$command" 2>/dev/null); then
		printf '%-12s %s\n' "$command" "$path"
	else
		printf '%-12s MISSING\n' "$command"
	fi
done
