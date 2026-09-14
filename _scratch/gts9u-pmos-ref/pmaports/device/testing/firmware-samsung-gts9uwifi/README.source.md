# Firmware source

These proprietary files are staged from the SM-X910 X910XXS5CYG1 stock
`vendor.img` by `scripts/stage-stock-wifi-firmware.sh`; they are intentionally
not committed. The package renames Qualcomm's Android Kiwi v2 files to the
filenames requested by mainline ath12k WCN7850/hw2.0:

- `amss20.bin` -> `amss.bin`
- `phy_ucode20.elf` -> `m3.bin`
- `bdwlan.elf` -> `board.bin`
- `regdb.bin` -> `regdb.bin`

## ADSP (audio DSP)

`scripts/stage-stock-adsp-firmware.sh` pulls `adsp.mdt`, its `adsp.bNN`
segments, `adsp_dtb.*` and the four PDR maps (`adspr`, `adsps`, `adspua`,
`cdspr`) straight from the tablet's own `apnhlos` partition, which it mounts
**read-only**. Every file is checked against `adsp-firmware.sha512` before the
build is allowed to use it.

Run it once on a machine that can reach the device over SSH:

```sh
scripts/stage-stock-adsp-firmware.sh
```

`GTS9U_HOST`, `GTS9U_KEY` and `GTS9U_PW` override the SSH target, key and sudo
password. The script is idempotent: it exits immediately when the staged files
already match the manifest.

## Why none of this is in git

Everything above is signed Samsung/Qualcomm firmware. It is not ours to
redistribute, so the repository ships the recipe and the checksums instead of
the bytes — every SM-X910 owner regenerates them from their own device.
