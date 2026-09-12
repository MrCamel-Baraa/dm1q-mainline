# Phase 1 workplan — devicetree bring-up

Goal of Phase 1: a `dm1q.dts` that boots mainline (or near-mainline) Linux far
enough to attempt display + storage + basic input, built from a clear
understanding of what's SoC-baseline vs. board-specific.

## Step 0 — Verify assumptions before writing any code

These gate everything below. Do these first; don't start diffing devicetrees
until they're answered.

- [ ] Confirm dm1q's bootloader can actually be OEM-unlocked / already is
      (should be, since it's running crDroid — but note exact method used,
      for the record).
- [ ] Confirm dm1q pmaports package: kernel type, maintainer, last activity.
      (`pmbootstrap init`, see docs/00-overview.md)
- [ ] Identify the WCN Wi-Fi/BT chip actually used in dm1q's crDroid kernel
      tree (grep for `wcn6855`, `wcn7850`, or `qcom,wcn*` compatible strings).
      This determines ath11k vs ath12k and whether the Tab S9 Ultra's
      PCIe/WiFi node structure is directly reusable.
- [ ] Identify the exact PMIC part(s) paired with dm1q (PM8550 vs PM8550B vs
      PM8550VE, etc.) from the crDroid kernel tree / downstream DT.
- [ ] Note the panel driver/compatible string and touch controller vendor
      used in the downstream kernel — these are 100% board-specific and will
      need their own driver regardless of what else transfers.

## Step 1 — Get reference materials in one place

- [ ] Clone the Tab S9 Ultra pmOS repo (see 03-references.md) into a scratch
      location (not committed here — it's someone else's repo, just a
      reference to diff against).
- [ ] Pull a recent mainline kernel tree (or at least `arch/arm64/boot/dts/qcom/`)
      to get the baseline `sm8550*.dtsi` files.
- [ ] Extract dm1q's downstream device tree / kernel source from crDroid.
      This is the ground truth for board-specific values (regulators,
      pinctrl, panel init sequence).

## Step 2 — The diff

Diff the Tab S9 Ultra's board `.dts` against the mainline `sm8550.dtsi`
baseline. This split is the actual workplan:

**Transfers directly (SoC-level):**
- Core sm8550 dtsi include — clocks, GCC/RPMH, interconnects, CPU/cluster topology
- Adreno 740 GPU node + Turnip/Mesa userspace config
- UFS controller node (protocol-level — storage *layout* still device-specific)
- USB controller (DWC3) core setup
- PCIe controller node structure — **contingent on WCN chip match, see Step 0**

**Needs full rebuild (board-level, source from crDroid tree):**
- Display panel driver (S23's AMOLED panel is a different part from the
  tablet's LCD/OLED — needs its own DSI panel driver from scratch)
- Touch controller driver
- PMIC regulator mapping (rail names/voltages are per-board-schematic —
  the single most Samsung-model-specific piece)
- Battery fuel gauge, charger IC
- Pinctrl/GPIO mapping
- GPU/CPU OPP tables — SM8550-AC is a factory-tested higher bin than
  reference kalama, so voltage/frequency points likely need retuning,
  not copy-pasting

## Step 3 — First boot attempt

Follow the standard pattern used across sdm845/qcom mainlining efforts
(see the "crosshatch mainlining" reference in 03-references.md for the
canonical version of this checklist):

1. Build kernel with a stub DT, confirm it reaches `start_kernel` and reboots
   cleanly (proves boot chain / boot.img format is right before debugging
   actual hardware).
2. Add regulator + clock nodes, confirm no hangs.
3. Bring up UART/USB early console for real debug output.
4. Bring up display last, once everything upstream of it is confirmed stable.

## Log

_(append dated entries here as work happens)_

- 2026-09-13: Repo created, workplan drafted from initial research. No boot
  attempt yet. Step 0 items outstanding.
