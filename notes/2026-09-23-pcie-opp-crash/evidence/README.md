Photos of the dm1q screen taken with another phone (downscaled to 1800 px; originals were on the
user's Desktop, EXIF 2026-09-21/22). All are kernel-console captures of the ~10.47 s oops.

- `otg-keyboard.jpg` — v4 build: the call-trace TAIL incl. `dev_pm_opp_set_opp+0x6c/0xcc`,
  `qcom_pcie_set_max_opp+0x4c/0x88`, `qcom_pcie_probe+0x1a8/0x414`, and the `Code:` line
  `2a1f03e6 9409333d 14000012 f85f0261 (394022a2)`. THE key evidence.
- `2026-09-22-10-31-02-091.jpg` — v4 build: oops header (`ESR = 0x96000004`, DABT) interleaved with the
  `arm-smmu 3da0000.iommu: deferred probe timeout` lines (two writers racing on fbcon).
- `not_connected.jpg`, `2026-09-22-10-41-34-489.jpg` — v4 / v5 boots stopping at the arm-smmu -110 lines.
- `second_boot.jpg` — corrupted pstore replay (v5); do NOT read offsets from it (that is where the
  wrong `+0x4c/0xc0` came from).
