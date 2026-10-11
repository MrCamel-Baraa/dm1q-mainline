#!/usr/bin/env bash
# Run one command in the dm1q initramfs busybox shell over the USB ACM gadget
# and print its output. Needs /dev/ttyACM0 readable+writable (host: modprobe
# cdc_acm, chmod 666 /dev/ttyACM0).
# Usage: scripts/acm-run.sh '<command>' [timeout_seconds]
set -uo pipefail
DEV="${ACM_DEV:-/dev/ttyACM0}"
CMD="${1:?command}"; TMO="${2:-30}"
OUT="$(mktemp)"; trap 'kill "$RD" 2>/dev/null; rm -f "$OUT"' EXIT
stty -F "$DEV" raw -echo 115200
cat "$DEV" > "$OUT" &
RD=$!
sleep 0.3
M="__ACM_DONE_$$__"
printf '\n%s; echo %s\n' "$CMD" "$M" > "$DEV"
for _ in $(seq 1 $((TMO * 5))); do
	# the marker appears once echoed by the command (line by itself)
	grep -q "^$M" "$OUT" && break
	sleep 0.2
done
grep -v "^$M" "$OUT" | tr -d '\r' | sed '1,/^$/{/^$/!b};' | grep -v -F "$CMD; echo $M"
