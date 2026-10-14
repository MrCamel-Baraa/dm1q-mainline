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
- `docs/06-pmos-userspace-plan.md` — Phase 2 plan: postmarketOS userspace
  (pmaports device/kernel package skeleton, what's left before a real
  Alpine rootfs boots)
- `docs/07-wlan-bringup.md` — WLAN (QCA6490/ath11k) bring-up: the full
  investigation trail, including the 2026-10-01 root cause of the "pcie0
  regression" (kernel module-signing key mismatch, not the devicetree) and
  the 2026-10-09 finding that 7.3-rc3 mis-programs the PCIe controller's
  BDF-to-SID table (upstream regression; fix carried as a patch, section 14), confirmed on
  hardware 2026-10-10 with a DTS workaround and 2026-10-11 with the patched kernel (r5) and the
  canonical DTS: `wlan0` is up (section 15; 15.12 is the module-tree pitfall of kernel rebuilds)
- `docs/08-input-bringup.md` — input bring-up: physical keys (power / volume, DT-only,
  2026-10-12), touch (STMicroelectronics FTS2BA61Y on SPI): confirmed on hardware 2026-10-13 with
  the driver carried as a kernel patch (package r6); orientation verified (no DT flags needed); one
  unexplained no-touch boot, see 2.10; multi-touch still to check
- `docs/09-display-bringup.md` — display bring-up (MDSS/DPU + DSI + panel): research and draft only, nothing
  flashed (2026-10-13). This unit's panel is the Samsung S6E3FAC; its DCS init sequence, DSC parameters, rails
  and GPIOs are recorded; draft DT nodes compile; next is a panel driver + kernel r7
- `pmaports/` — local pmaports-style device (`device-samsung-dm1q`) and
  kernel (`linux-samsung-dm1q-mainline`) packages, structurally templated
  on the gts9uwifi reference; see docs/06 for status (unbuilt skeleton,
  not yet validated with pmbootstrap/abuild)
- `dts/` — devicetree work (diffs, drafts, extracted downstream references)
- `notes/` — scratch notes, kernel config diffs, log dumps
- `kernel/` — kernel patches and config fragments applied on top of upstream
  (currently: `samsung-sec-log` persistent console, readable from recovery
  as `/proc/last_kmsg`)
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
yet flashed as of 2026-09-20. First flash attempt (2026-09-21) did not boot: Download Mode with a vbmeta/AVB error — see the 2026-09-21 entry in `docs/01-phase1-workplan.md`.** A real upstream mainline kernel
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

**Update 2026-09-26: first mainline boot confirmed stable on real hardware**
(kernel 7.3.0-rc3, v12) — UART7 console, USB CDC-ACM shell, and UFS
storage all working; uptime tested to ~4h51m with no crash. Display is
still bootloader-splash-passthrough only (no native panel driver) and
WLAN is not yet exercised. **Phase 2 (postmarketOS userspace) has started**
— see `docs/06-pmos-userspace-plan.md` for the current plan and the new
`pmaports/` package skeleton.
