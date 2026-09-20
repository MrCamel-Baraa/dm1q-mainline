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
- `../_scratch/` — sibling directory (outside this repo, gitignored) with
  frozen snapshots of external reference repos, kernel build workspace, and
  boot-image materials. See `../_scratch/README.md` for exact contents/
  sources/commits. Deliberately kept out of the repo — see
  `docs/01-phase1-workplan.md`'s 2026-09-14/15 entries for why.

## Status

Phase 1 Step 0 (verify assumptions) is complete — see
`docs/01-phase1-workplan.md` for the full checklist and what was found,
including two corrections to earlier assumptions (WCN chip is QCA6490, not
WCN6855; multi-part PMIC, not a single part). Step 1 (reference materials)
is done. Step 2's devicetree work is essentially done for a first boot
attempt — see `docs/05-dm1q-real-hardware-values.md` for the full research
trail (most values live-verified directly on the physical device, several
independently cross-confirmed against a real already-upstream mainline
board, `sm8550-samsung-q5q.dts`).

**`dts/dm1q/dm1q.dts` is wired and evidence-backed for: UART console, UFS
(boot/root storage), WLAN/BT (QCA6490) + PCIe0, USB (both PHYs + the real
eUSB2 repeater), and the touch controller.** Compiles cleanly with `dtc`
(see the file's own header comment for the exact command). Display/panel
driver and camera are explicitly not started — real Samsung GPL panel
driver source has been obtained and its logic confirmed real, but the
exact DCS byte table wasn't located yet (see docs/05 for where to pick
this up).

**A real kernel + boot images now exist, ready for a flash attempt — not
yet flashed, not yet tested on hardware.** A real upstream mainline kernel
was built with `dm1q.dts`, paired with a minimal busybox-based initramfs
(just enough to prove the kernel initializes real hardware and reaches a
shell — not postmarketOS itself, no Alpine userspace yet). The actual
device's boot/init_boot/vendor_boot partitions were pulled directly off
the phone first (both as a real reference for building compatible
replacement images, and as a full recovery backup), and three replacement
images were built and verified against the originals. See
`docs/01-phase1-workplan.md`'s 2026-09-20 entry for the full process,
including the safety planning that preceded it (this is the user's daily
phone). All materials are in `../_scratch/boot-backup-<date>/`.
