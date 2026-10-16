# Pixel test on r7 (kernel 7.3.0-rc3, package r7), 2026-10-15

Run: `bash scripts/collect-phone-state.sh drm-test --drm-test`, image set `../_scratch/pmos-v15-display-r7`.
Observer: Baraa, watching the panel (user-reported, ~05:00 local).

Observed sequence on the phone screen:
1. full colour bars with the grey gradient strip
2. solid red
3. solid green
4. solid blue
5. solid white
6. the console again (fbcon restored)

Defects reported: none. No flicker, no noise.

Machine-side log of the same run: `drm-test.txt` (this directory). Raw dmesg/journal/gpio/session files of
the run exist locally and are deliberately not committed (they contain MAC addresses and the Wi-Fi SSID).
