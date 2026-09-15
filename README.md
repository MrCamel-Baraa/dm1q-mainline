# dm1q-mainline

Mainline Linux / postmarketOS / Kupfer porting project for the Samsung Galaxy S23
(codename **dm1q**, Qualcomm SM8550 "kalama", Snapdragon 8 Gen 2).

Current daily driver on the device: crDroid (fully unlocked/modifiable bootloader).

## Goal

1. Get postmarketOS booting on dm1q with display, GPU accel, Wi-Fi, Bluetooth,
   audio, and basic sensors working on a mainline-first kernel.
2. Once pmOS hardware bring-up is solid, port the device into Kupfer
   (Arch Linux ARM for mobile) by reusing the same deviceinfo/kernel work.
3. Camera and modem are treated as stretch goals, not blockers — see
   `docs/02-open-questions-and-risks.md` for why.

## Repo layout

- `docs/00-overview.md` — current state of the art (what exists, what doesn't)
- `docs/01-phase1-workplan.md` — the devicetree bring-up plan
- `docs/02-open-questions-and-risks.md` — things to verify before assuming they transfer
- `docs/03-references.md` — links to prior art, guides, upstream projects
- `docs/04-gts9u-vs-mainline-devicetree-diff.md` — categorized diff of the
  Tab S9 Ultra reference devicetree against plain upstream mainline
- `docs/05-dm1q-real-hardware-values.md` — real regulator/GPIO/pinctrl
  values extracted directly from dm1q's own downstream devicetree source
- `dts/` — devicetree work (diffs, drafts, extracted downstream references)
- `notes/` — scratch notes, kernel config diffs, log dumps
- `../_scratch/` — frozen snapshots of external reference repos (real dm1q
  downstream devicetree source, Tab S9 Ultra reference ports, upstream
  mainline qcom devicetree files, pmaports). See `../_scratch/README.md` for
  exact sources/commits. Committed deliberately for self-containment, not
  gitignored — these are reference material, not our own work.

## Status

Phase 1 Step 0 (verify assumptions) is complete — see
`docs/01-phase1-workplan.md` for the full checklist and what was found,
including two corrections to earlier assumptions (WCN chip is QCA6490, not
WCN6855; multi-part PMIC, not a single part). Step 1 (reference materials)
is done. Step 2 has a first-pass structural map
(`docs/04-gts9u-vs-mainline-devicetree-diff.md`) plus real hardware values
extracted (`docs/05-dm1q-real-hardware-values.md`).

**`dts/dm1q/dm1q.dts` exists now** — a first real draft (model/compatible/
board-id, WLAN/BT regulators and the QCA6490 PMU node, a touch controller
placeholder). Compiles cleanly with `dtc` (see the file's own header
comment for the exact command). Not tested on hardware. Display, PCIe, UFS,
USB, and camera are explicitly not started yet — see the file's own
trailing comment block for what's deliberately left out. No boot attempt
yet.
