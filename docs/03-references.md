# References

## Prior art — same SoC family (SM8550/kalama)

- **postmarketos-galaxy-tab-s9-ultra** (agcarbajo/GitHub) — mainline-first pmOS
  port of the Tab S9 Ultra Wi-Fi (SM-X910, gts9uwifi). Best available reference
  for SM8550 devicetree/clock/regulator/UFS bring-up. Actively maintained as
  of ~30 days before this doc was written.
  `github.com/agcarbajo/postmarketos-galaxy-tab-s9-ultra`
  Dev notes (in Spanish): `docs/development-notes.md` in that repo.

## Camera bring-up methodology reference

- **Fairphone 6 wide camera experimental support** (nondescriptpointer.com) —
  walkthrough of bringing up the OmniVision OV13B10 sensor on Fairphone 6
  (SM7635 "milos") by comparing the downstream TFE665 ISP block against the
  already-mainlined TFE530 block, then wiring up libcamera. This is the shape
  of the work that would be needed for the S23's Spectra 780 ISP — no one has
  done it yet for kalama/Spectra as far as we've found.
  `nondescriptpointer.com/articles/fairphone-6-wide-camera-linux/`

## Waydroid camera passthrough mechanics

- `github.com/waydroid/waydroid` issue #519 — libcamera support feature request,
  explains Waydroid only passes through V4L2/libcamera devices the host kernel
  already exposes; it has no independent camera driver capability.

## postmarketOS project infrastructure

- postmarketOS wiki: `wiki.postmarketos.org` (blocks automated fetches — must
  be read manually in a browser)
- postmarketOS wiki category listing devices: Category:Android lists a
  "Samsung Galaxy S23" page (content unread — see open questions doc)
- **pmaports repo (current, correct): `gitlab.postmarketos.org/postmarketOS/pmaports`**
  — migrated here from gitlab.com on 2024-10-06. The old
  `gitlab.com/postmarketOS/pmaports` is now archived/read-only; use it only
  for pre-Oct-2024 history if needed, not as the live reference.
  Status page confirming the migration: `status.postmarketos.org`
- pmbootstrap docs: `docs.postmarketos.org/pmbootstrap/usage.html`
- Deviceinfo reference: `docs.postmarketos.org/pmaports/main/deviceinfo-reference.html`
- "Porting to a new device" guide (older mirror, but methodology still valid):
  `yuvadm.github.io/pmosweb/wiki/Porting-to-a-new-device/`

## Qualcomm mainlining methodology reference

- pmaports issue #153, "crosshatch: mainlining attempt: progress and
  questions" — Google Pixel 3 XL (sdm845) mainlining log. This is the
  canonical example of the incremental bring-up process (stub DT → boots to
  start_kernel → regulators/clocks → USB → display), referenced as the
  template for our Step 3 first-boot sequence.
  `gitlab.com/postmarketOS/pmaports/issues/153`

## Kupfer

- Kupfer homepage / docs: `kupfer.gitlab.io` — explicitly states it reuses
  postmarketOS deviceinfo files and recommends doing the pmOS port first.
- Kupfer supported devices list: `kupfer.gitlab.io/devices/index.html`
  (as of last check: only sdm845-and-older devices supported)

## Device identification

- dm1q = Samsung Galaxy S23 (SM-S911x), dm2q = S23+, dm3q = S23 Ultra
- SoC: SM8550-AC "Snapdragon 8 Gen 2 for Galaxy" — same die as reference
  kalama SM8550, but a higher factory-tested clock/voltage bin
- LineageOS device pages (for hardware spec cross-referencing):
  `wiki.lineageos.org/devices/dm1q/`

## WCN chip confirmation (Wi-Fi/Bluetooth)

- iFixit "Galaxy S23 Ultra Chip ID" teardown — directly identifies the
  Qualcomm WCN7851-101 FastConnect 7800 part on the S23 Ultra board.
  `ifixit.com/Guide/Galaxy+S23+Ultra+Chip+ID/158052`
- XDA Forums thread, "Which Snapdragon 8 Gen2 Modem Configuration..." —
  states, citing Qualcomm's own device finder page, that the S23 Ultra uses
  FastConnect 7800 while the S23 and S23+ use FastConnect 6900.
  `xdaforums.com/t/which-snapdragon-8-gen2-modem-configuration-fast-connect-7800-wi-fi-7-or-6900-wi-fi-6e.4555581/`
- Samsung Community threads (multiple, DE and EU boards) independently
  confirm the S23 series ships Wi-Fi 6E only in software/firmware despite the
  Ultra's chip having native Wi-Fi 7 capability — consistent with the
  FastConnect 7800/WCN7850 identification above.
