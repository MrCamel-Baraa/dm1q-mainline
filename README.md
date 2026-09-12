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
- `dts/` — devicetree work (diffs, drafts, extracted downstream references)
- `notes/` — scratch notes, kernel config diffs, log dumps

## Status

Planning phase. No boot attempt yet.
