# References

## Prior art — same SoC family (SM8550/kalama)

- **postmarketos-galaxy-tab-s9-ultra** (agcarbajo/GitHub) — mainline-first pmOS
  port of the Tab S9 Ultra Wi-Fi (SM-X910, gts9uwifi).
  **CORRECTED 2026-09-13 (second pass, retracting the same day's earlier
  "discredited" verdict — see history at bottom of this entry).** This is a
  real, legitimate, technically competent unmerged personal port — not
  fabricated. What actually happened: `kernel/PROVENANCE.md`'s reference to
  a "pmaports package" refers to this repo's own local `pmaports/` subfolder
  (a personal pmaports-formatted device+kernel package tree used with
  `pmbootstrap`, never submitted upstream) — not a claim that it's merged
  into the official gitlab.postmarketos.org repo. That's a completely normal
  state for a community port. Verified directly, not taken on faith:
  - `pmaports/device/testing/device-samsung-gts9uwifi/deviceinfo` uses real
    pmOS deviceinfo fields correctly, with a screen resolution (2960×1848)
    matching the tablet's actual real-world spec.
  - The kernel package APKBUILD pulls the kernel tarball from a real,
    correctly-formed `git.kernel.org/torvalds/t/...` URL, and pulls a shared
    config from a **specific commit hash on the real pmaports repo** —
    `b7681d0e857d395edfaa6c8e5cd0d89e4315fd3f` — which we confirmed actually
    exists in pmaports' real history (`git cat-file -t` → `commit`). A
    fabricated project doesn't cite real, resolvable commit hashes from
    someone else's 14,885-commit repository.
  - `kernel/patches/hi847-libcamera-compliance.patch` is a real, correct,
    idiomatic kernel patch against the actual mainline `drivers/media/i2c/hi847.c`
    driver, using proper V4L2 APIs (`v4l2_fwnode_device_parse`,
    `get_selection`, standard libcamera front/back-location properties).
    Not fabricated placeholder code.
  **Working conclusion: treat this as a legitimate, usable reference/
  starting-point template for dm1q's SM8550 bring-up.** Remaining honest
  caveat: we've verified the *code is real and technically sound*, not that
  every hardware-status claim in the README has been independently
  reproduced on physical hardware by anyone outside that one project — normal
  epistemic caution for any single-source, unmerged, un-peer-reviewed port,
  not the "possibly fabricated" level of doubt from earlier today.
  `github.com/agcarbajo/postmarketos-galaxy-tab-s9-ultra`

  *(History of this entry, kept for transparency: earlier today this same
  entry was marked "discredited," reasoning that a false self-reported
  pmaports provenance implied likely-fabricated content. That reasoning was
  based on an unwarranted assumption — that "pmaports package" must mean
  "in the official upstream repo" — rather than considering the much more
  mundane explanation confirmed above. Correcting in place rather than
  hiding the mistake.)*
- **ubuntu-galaxy-tab-s9-ultra** (agcarbajo/GitHub) — companion repo by the
  same author, reuses the kernel work from the pmOS repo above.
  **Same correction as above applies: this is legitimate, not fabricated.**
  See the pmOS repo entry above for the verification detail (real deviceinfo
  conventions matching actual device spec, real resolvable pmaports commit
  hash cited, real correct V4L2 patch code). Contains the same real
  `kernel/dts/sm8550-samsung-gts9uwifi.dts` and driver/patch set. The one
  claim still worth extra scrutiny before relying on it specifically: the
  README's hardware-compatibility table asserts full camera support (4
  cameras, autofocus, flash) — genuinely unusual for mainline Qualcomm
  Spectra-ISP work anywhere, and worth a closer read of
  `docs/hardware-status.md` (which claims to document per-component
  evidence) before assuming it transfers cleanly. This is ordinary
  single-source caution, not a fabrication concern.
  `github.com/agcarbajo/ubuntu-galaxy-tab-s9-ultra`
- Related repo `kquote03/linux-gts9`, which cites the pmOS repo above as an
  input, is now reasonable mild external corroboration rather than a
  meaningless echo, given the correction above.
- **Update to the "no reference exists" conclusion below: retracted.** The
  pmaports-search results (no Samsung SM8550 device in the *official*
  pmaports repo — checked across the whole SM8550 lineup, not just gts9u)
  are still accurate and worth keeping, but the conclusion drawn from them
  ("no trustworthy reference exists anywhere") was downstream of the now-
  corrected fabrication verdict above and no longer holds. The
  agcarbajo/postmarketos-galaxy-tab-s9-ultra repo — unmerged into official
  pmaports, but real and legitimate — is exactly this kind of reference.
  (Original text kept below for the accurate part of it — the pmaports
  search results themselves were correct, just the conclusion was wrong.)
- **Exhaustive check, 2026-09-13: no trustworthy SM8550/kalama Samsung
  reference exists anywhere, for any device in the line.** Beyond dm1q/dm2q/
  dm3q (S23/S23+/S23 Ultra) and the Tab S9 Ultra (gts9uwifi), also checked
  pmaports directly for the rest of the SM8550 Samsung lineup — Z Flip5
  (`b5q`), Z Fold5 (`q5q`), Tab S9 (`gts9wifi`), Tab S9+ (`gts9p`) — zero
  matches for any of them. Web search for Z Flip5/Fold5 mainline work turns
  up only downstream Android kernel forks (KernelSU-Next, Samsung OSRC-based,
  still on Android's 5.15 LTS branch) — not mainline Linux, not relevant to
  this project. **Working conclusion: this is genuinely a from-scratch
  mainline port with no same-SoC devicetree/driver reference to lean on.**
  Plain upstream mainline kernel + the downstream crDroid source tree (for
  real hardware values — GPIOs, regulator names, timing) are the only
  trustworthy sources going forward.

## Camera bring-up methodology reference

- **Fairphone 6 wide camera experimental support** (nondescriptpointer.com) —
  walkthrough of bringing up the OmniVision OV13B10 sensor on Fairphone 6
  (SM7635 "milos") by comparing the downstream TFE665 ISP block against the
  already-mainlined TFE530 block, then wiring up libcamera. This is the shape
  of the work that would be needed for the S23's Spectra 780 ISP.
  **Note (2026-09-13): a since-discredited source (see agcarbajo repos
  above) briefly appeared to supersede this "no one has done it yet"
  framing with a camera-working claim for SM8550/kalama; that claim's
  source has a confirmed false provenance statement and should not be
  trusted. This Fairphone 6 reference stands as originally written: the
  best real methodology reference we have, and kalama/Spectra camera
  bring-up should still be treated as effectively unstarted.**
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


## Bootloader method reference — Samsung SDM670 case study (2026-09-15)

- **A70q (SM-A705FN, SDM670/sm6150) "vibe-coded" mainline pmOS port** —
  raised in conversation as an unverified community claim (AI-assisted,
  ChatGPT, non-technical author), later reported as verified working by ROM
  maintainers with logs/video. Cloned and directly inspected both repos
  rather than trusting the secondhand description:
  - `github.com/redzrush101/linux`, branch `a70q/mainline-next` — real DTS
    at `arch/arm64/boot/dts/qcom/sm6150-samsung-a70q.dts`.
  - `github.com/redzrush101/pmaports`, branch `a70q/pmaports-next` (NOT
    `main` — the default branch has no A70q content at all) — real device
    package at `device/testing/device-samsung-a70q/`, plus a substantial
    kernel patch set (`device/testing/linux-postmarketos-qcom-sm6150/`)
    covering display, GPU, Venus, ADSP, touchscreen enablement and CPU/
    cluster power-collapse tuning. Granular, plausible, non-trivial patch
    work — not fabricated placeholder content.
  - **Bootloader method confirmed from the real deviceinfo file:
    `deviceinfo_flash_method="heimdall-bootimg"`.** No U-Boot, no uniLoader,
    no intermediate chainloaded bootloader at all — Samsung's stock SBL
    loads a standard Android boot.img (mainline kernel + DTB + ramdisk)
    directly, flashed to the BOOT partition via Heimdall (open-source Odin
    protocol tool). Rootfs flashed separately to USERDATA.
  - Flashing flow (from a Heimdall-based pmOS install doc, screenshotted in
    conversation): clear the stock DTBO partition first
    (`heimdall flash --DTBO empty_dtbo.img`) so it can't silently override
    the mainline devicetree, then `pmbootstrap install --split` +
    `pmbootstrap export` to produce separate boot/root images, then
    `img2simg` to convert both to Android sparse image format (required by
    Heimdall/Odin's protocol) before flashing.
  - **Relevance to dm1q:** dm1q shares the same Samsung SBL lineage. This
    suggests `heimdall-bootimg` (no intermediate bootloader) may be viable
    for dm1q too, which would avoid U-Boot chainload work entirely if it
    pans out. Worth testing early once bootloader-stage work starts, rather
    than assuming U-Boot is required by default.

## Kupfer — U-Boot/aboot gap (2026-09-15)

- Kupfer's own porting docs confirm the workflow is: take an existing pmOS
  device port (unofficial/local is fine — upstream pmaports merge is NOT a
  prerequisite) and port its APKBUILD/deviceinfo to Kupfer's PKGBUILD
  scheme, using existing Kupfer device ports as a template.
- **Gap that matters for sequencing:** Kupferbootstrap currently only knows
  how to produce Android aboot-style boot images. It does not yet call into
  `boot-deploy` (postmarketOS's boot-artifact-assembly tool, successor to
  android-bootimg-updater) for U-Boot targets. If dm1q ends up needing a
  U-Boot chainload (as opposed to the heimdall-bootimg approach noted
  above), Kupfer bring-up would need `boot-deploy` support wired into
  Kupferbootstrap first — that's tooling work upstream in Kupfer itself, not
  something resolvable in this repo alone. If heimdall-bootimg works for
  dm1q instead, this gap may not apply at all.
