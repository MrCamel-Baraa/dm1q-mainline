#!/bin/sh
# phone-wlan-log.sh -- ON THE PHONE (busybox sh), no root needed. Logs one line every ~25 s: power-save state,
# the station's TX counters (tx packets / tx failed), the AP's current rate towards us, and the loss of a
# 10-ping burst to the gateway. For catching WHEN a lossy link comes back (docs/07 section 15.9-15.10).
#   sh phone-wlan-log.sh [gateway] >> /tmp/wlanlog.txt 2>&1 &      # default gateway: the default route
#   tail -n 60 /tmp/wlanlog.txt                                    # read it
#   pkill -f phone-wlan-log.sh                                     # stop (it does not survive a reboot)
GW="${1:-$(ip route | awk '/^default/ {print $3; exit}')}"
while :; do
	s=$(iw dev wlan0 station dump | awk '/tx packets/ {p=$3} /tx failed/ {f=$3} /rx bitrate/ {r=$3} END {print "tx", p, "failed", f, "rx", r}')
	l=$(ping -c 10 -i 0.5 -W 1 "$GW" 2>&1 | grep loss)
	echo "$(date +%T) ps=$(iw dev wlan0 get power_save | cut -d' ' -f3) $s | $l"
	sleep 20
done
