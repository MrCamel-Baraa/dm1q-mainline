#!/bin/sh
# phone-wlan-pstest.sh -- ON THE PHONE, as root (iw set power_save needs it): power-save A/B on the current link.
# on / off / on / off, 40 pings to the gateway each, with the station's `tx packets` / `tx failed` before and after,
# and power save left OFF at the end. For telling a power-save problem from a link problem (docs/07 section 15.10).
#   sudo sh phone-wlan-pstest.sh [gateway]
GW="${1:-$(ip route | awk '/^default/ {print $3; exit}')}"
st() { iw dev wlan0 station dump | awk '/tx packets/ {p=$3} /tx failed/ {f=$3} END {print "tx", p, "failed", f}'; }
echo "power save now: $(iw dev wlan0 get power_save)"
for ps in on off on off; do
	iw dev wlan0 set power_save "$ps"; sleep 3
	echo "== power_save $ps  before: $(st)"
	ping -c 40 -i 0.3 "$GW" | tail -n 2
	echo "   after: $(st)"
done
iw dev wlan0 set power_save off
