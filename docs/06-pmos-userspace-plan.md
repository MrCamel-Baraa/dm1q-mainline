# Phase 2 workplan — postmarketOS userspace

Goal of Phase 2: replace the hand-built busybox initramfs (kernel/initramfs/
init-v4 through v12's diagnostics) with a real postmarketOS/Alpine rootfs
that boots on dm1q via pmaports packaging, reachable over a getty (UART7
and/or the USB CDC-ACM gadget) with UFS as root storage. Display, WLAN, and
a graphical session are explicitly out of scope for Phase 2 Step 0 — see
"What Phase 2 Step 0 does NOT include" below.

## Where Phase 1 left off (read docs/01-phase1-workplan.md for the full log)

As of the v12 boot (2026-09-26), confirmed live on real hardware:

- Kernel 7.3.0-rc3 + `dts/dm1q/dm1q.dts` boots clean, no crash, uptime
  tested to ~4h51m.
- UART7 console works (`console=tty0` + framebuffer console today; UART7
  itself is wired and enabled, not yet used as the primary getty).
- USB: CDC-ACM gadget binds, `/dev/ttyACM0` gives an interactive shell —
  first working USB path in this project.
- UFS (real SCSI host, all six LUNs, full partition table) works — this
  is the actual boot/root storage.
- Display: only the ABL splash framebuffer via `simple-framebuffer` +
  `CONFIG_DRM_SIMPLEDRM` — no native SM8550 DPU/DSI panel driver.
- WLAN/BT (QCA6490): devicetree node exists, never exercised against a
  real driver/userspace stack.
- Open: SPMI USID-7 (PM8550B) identify-read fails every boot (Finding 1,
  2026-09-25/26) — doesn't block anything currently wired, not yet
  root-caused.
- PCIe/GPU/camera/touch: wired in devicetree (PCIe, touch) or deliberately
  not attempted (GPU/display, camera) — see dts/dm1q/dm1q.dts's own
  trailing "NOT STARTED" comment.

## What Phase 2 Step 0 does NOT include

- A native display driver (panel work is unstarted — see
  docs/02-open-questions-and-risks.md item 3b). The simple-framebuffer
  path is kept working since it's the only way to see a console without
  UART/USB hardware in hand, but a graphical session (Xorg/Wayland,
  `deviceinfo_drm`'s real intended use) is not a Phase 2 Step 0 goal.
- WLAN. QCA6490/`ath11k` has never been exercised on this board. Getting
  console access first (UART/USB) removes the dependency on Wi-Fi for
  reaching the device during bring-up.
- Automating the flash. ABL's rejection of a mainline DTB via the stock
  DTBO overlay (see docs/01, 2026-09-21/23 entries) means the current
  working boot image is hand-assembled (invalid-dtbo + DTB-appended-to-
  gzip(Image)), not pmbootstrap's normal `--split`/`export` output. This
  needs its own script before `deviceinfo_flash_method`/`generate_bootimg`
  can be anything other than the placeholders in the skeleton below.

## What's been created this session (2026-09-27)

A pmaports-style local package skeleton, structurally templated on the
Tab S9 Ultra reference (`../_scratch/gts9u-pmos-ref/pmaports/`), populated
with dm1q's own real, hardware-verified files — not copied placeholder
content:

- `pmaports/device/testing/device-samsung-dm1q/{deviceinfo,APKBUILD}` —
  minimal device package. No device-specific userspace hooks yet (no
  display/sensor/audio bring-up exists to hook into). `deviceinfo_drm`,
  `deviceinfo_getty`, `deviceinfo_external_storage`, `deviceinfo_chassis`
  etc. are set to what's actually confirmed about this hardware (no
  microSD, handset chassis, 1080x2340). `deviceinfo_flash_method="none"`
  and `deviceinfo_generate_bootimg="false"` — deliberately not claiming
  pmbootstrap's normal flash path works yet, since it doesn't (see above).
- `pmaports/device/testing/linux-samsung-dm1q-mainline/` — kernel package.
  `sm8550-samsung-dm1q.dts` is a synced copy of the real `dts/dm1q/dm1q.dts`
  (keep these in sync by hand until this package is the canonical location
  — see "Next" below). `config-dm1q.fragment` matches
  `kernel/config/dm1q.fragment` plus the storage/PMIC/pstore options found
  to silently need to be built-in (not `=m`) during the 2026-09-23 UFS
  investigation (see docs/01's "UFS never worked at all" entry) — real
  pmOS rootfs images DO support loadable modules (unlike the bring-up
  initramfs), but UFS is `/` itself, so its drivers must still be built-in
  or root can never mount. `add-samsung-sec-log-console.patch` is the
  same patch as `kernel/patches/0001-...patch`.

**Both packages are unbuilt placeholders in one specific sense**: `sha512sums`
are all-zero stubs (nothing has actually been fetched/hashed through
`abuild` yet) and the device APKBUILD's `deviceinfo` checksum is likewise
fake. This is flagged in-file with `abuild checksum` TODOs. Don't treat
these as ready to `pmbootstrap build` without running that first.

## Next steps, in order

1. ✅ **Done 2026-09-27.** Point `pmbootstrap` at this local pmaports tree
   and confirm it parses `device-samsung-dm1q` / `linux-samsung-dm1q-mainline`
   without errors. See the Log entry below for exactly how and what it found.
2. Run `pmbootstrap checksum linux-samsung-dm1q-mainline` (and the device
   package) once the kernel tarball/config/DTS/patch are actually staged,
   replacing the placeholder `sha512sums`. **Blocked** — see Log: needs
   root inside `pmbootstrap`'s native chroot, which needs an interactive
   `sudo` this session's shell access can't run. Baraa needs to run this
   step himself from a real terminal (see Log for the exact command).
3. Build `linux-samsung-dm1q-mainline` for real (this is the expensive
   step — a full kernel build, same as the v-series manual builds in
   docs/01, just now going through `abuild`/`postmarketos-installkernel`
   instead of a hand-run `make`).
4. Write the boot-image-assembly script that encodes the current
   hand-verified working recipe (invalid `dtbo` + DTB appended to
   `gzip(Image)`, AVB footers, `mkbootimg`) so it's reproducible and not
   re-derived from scratch each session — this is the actual blocker for
   `deviceinfo_flash_method`/`generate_bootimg` ever being real.
5. Get a genuine Alpine rootfs (postmarketos-base) booting and reachable
   via getty over UART7 and/or the USB ACM gadget, with UFS as root. This
   is the actual Phase 2 Step 0 milestone — no display/WLAN required for
   it to count as done.
6. Only after 5: revisit display (panel driver work) and WLAN
   (`ath11k`/QCA6490 exercised for real) as their own follow-on efforts,
   per the existing risk notes in docs/02-open-questions-and-risks.md.

## Log

- 2026-09-27: Read the current state of the art from docs/00–02 and the
  Phase 1 log, confirmed v12 is the latest verified-on-hardware kernel
  state (UART7 console wired, USB CDC-ACM working, UFS working, no
  display/WLAN driver exercised, SPMI USID-7 still open). Created the
  pmaports device + kernel package skeleton described above, templated
  structurally on the real gts9uwifi reference package
  (`../_scratch/gts9u-pmos-ref/pmaports/device/testing/`). Did not run
  `pmbootstrap`/`abuild` or touch the physical device this session —
  next real step is validating the package skeleton with pmbootstrap
  (see "Next steps" above) before any build or flash is attempted.
- 2026-09-27 (later same day): validated the skeleton with `pmbootstrap`.
  `pmbootstrap`'s cached pmaports checkout already existed on this machine
  at `~/.local/var/pmbootstrap/cache_git/pmaports` (config: `aports =` that
  path). Symlinked this repo's `pmaports/device/testing/device-samsung-dm1q`
  and `.../linux-samsung-dm1q-mainline` into that checkout's own
  `device/testing/`, then `pmbootstrap config device samsung-dm1q`.
  Results:
  - `pmbootstrap apkbuild_parse device-samsung-dm1q` — clean parse, all
    fields resolved correctly (depends, sha512sums, etc.).
  - `pmbootstrap apkbuild_parse linux-samsung-dm1q-mainline` — clean parse;
    `$_kernelver`/`$_flavor` substitution resolved correctly
    (`pkgver=7.3_rc3` → `linux-7.3-rc3.tar.gz`, `_flavor=samsung-dm1q-mainline`),
    all 5 sources matched 1:1 with their sha512sums placeholders.
  - `pmbootstrap config` correctly reports `Device: samsung-dm1q (aarch64)`
    once selected — the deviceinfo itself loads without error.
  - **Found a real blocker**: `pmbootstrap checksum` (the next step, to
    replace the placeholder hashes) needs to initialize pmbootstrap's
    native chroot, which does `sudo mkdir -p .../chroot_native/dev` etc.
    This session's shell tool (Desktop Commander) has `sudo` in its
    blocked-commands list — a deliberate safety boundary on Baraa's
    machine, not something to route around. So the actual checksum fetch
    and every step after it (build, chroot, install, flasher) needs Baraa
    to run it himself, interactively, from a real terminal where `sudo`
    can prompt. The command to run is:
    ```
    pmbootstrap config device samsung-dm1q
    pmbootstrap checksum linux-samsung-dm1q-mainline
    ```
    (the `device-samsung-dm1q` symlink is already in place from this
    session, so no setup is needed beyond that — just the sudo password.)
- 2026-09-27 (after Baraa ran checksum): kernel package now has real
  sha512sums. Audited the package copies against the canonical files:
  the DTS copy was functionally identical to `dts/dm1q/dm1q.dts` (only
  comments had been trimmed), but has since been replaced with a byte-exact
  `cp` to prevent drift -- **so the kernel APKBUILD's DTS checksum is stale
  and `pmbootstrap checksum linux-samsung-dm1q-mainline` must be re-run.**
  `config-dm1q.fragment` differs from `kernel/config/dm1q.fragment` by 7
  intentional additions (UFS_QCOM, ICE, QMP/QMP_UFS, PSTORE x3; docs/01
  line ~470 documents UFS_QCOM/ICE/QMP_UFS being `=m` in defconfig and
  needing to be built-in; the PSTORE lines are unverified additions from
  this session, not from a booted config). The device package's
  `deviceinfo` checksum is still the zero placeholder -- needs
  `pmbootstrap checksum device-samsung-dm1q`.
- 2026-09-28: Baraa re-ran checksum; verified both APKBUILDs now carry
  real hashes matching the files on disk (DTS `fb4e95d8...`, deviceinfo
  `9b064f7a...`). Wrote `scripts/make-boot-images.sh` (step 4): builds
  boot/vendor_boot/dtbo with the v12 recipe. **Verified by round-trip**:
  feeding it v12's own Image + DTB reproduces v12's `boot.img` and
  `vendor_boot.img` byte-identical up to the AVB footer. Correction found
  while writing it: dtbo partition is 16 MiB (not 8). It does NOT build
  init_boot and flashes nothing. Still needs a real pmOS initramfs +
  root= cmdline before it can boot pmOS; today it reproduces the
  busybox bring-up boot.
- 2026-09-28 (kernel package built): first attempt failed abuild validation
  (maintainer must be a valid RFC822 address; `@localhost` is rejected) --
  changed to `<dm1q-mainline@example.com>` in both APKBUILDs (swap in a real
  address if desired; checksums unaffected). Second run: `pmbootstrap build
  linux-samsung-dm1q-mainline` succeeded (~40 min) -> `linux-samsung-dm1q-mainline-7.3_rc3-r1.apk`
  (91 MiB) in `~/.local/var/pmbootstrap/packages/edge/aarch64/`. Inspected
  the apk offline (no sudo needed, it is a tarball):
  - kernel.release 7.3.0-rc3; `sm8550-samsung-dm1q.dtb` is 121890 bytes,
    identical size to the v12 DTB.
  - built-in (not modules): ufs-qcom, phy-qcom-qmp-ufs, qcom_ice,
    phy-snps-eusb2, phy-nxp-ptn3222, i2c-qcom-geni, simpledrm. ath11k is a
    module (fine, WLAN is not needed for boot).
  - kernel Image contains the sec_log driver strings, simple-framebuffer
    and TER16x32 font, so the fragment merged as intended (the sec-log
    patch applied). Note `bool` options never show in modules.builtin, so
    this was checked via strings in the Image instead.
  - **Gotcha:** `/boot/vmlinuz` in the apk is an EFI zboot wrapper
    (gzip payload inside), NOT a raw Image. ABL needs gzip(raw Image)+DTB,
    so the zboot payload must be unwrapped first (python: read u32 offset
    and size at header bytes 8..16, gunzip that slice). Raw Image is 58 MB
    vs 42.6 MB for the bring-up v12 kernel (pmOS config is larger).
  - `scripts/make-boot-images.sh` ran cleanly on it (AVB footers verified);
    output in /tmp only, NOT flashed and NOT tested on hardware.
    Open: a pmOS-config kernel has never booted on this device; only the
    trimmed arm64-defconfig kernel has.
- 2026-09-28 (device pkg + first `pmbootstrap install --split`): both
  built. Read the generated initramfs offline (`chroot_rootfs_samsung-dm1q/boot/initramfs`,
  gzip cpio; `initramfs-extra` 12 MB lives in the pmOS boot partition).
  **Storage finding:** pmOS initramfs has a "subpartitions" path
  (`mount_subpartitions` in init_functions.sh): it looks at
  /dev/disk/by-partlabel/userdata (or system*), `losetup -P`s it, and finds
  the pmOS_boot and pmOS_root partitions *inside* it. So the intended layout
  for this device is ONE combined pmOS disk image flashed to `userdata`
  (no repartitioning, no spare boot partition) -- `--split` was the wrong
  install mode; re-run `pmbootstrap install` WITHOUT `--split`. Baraa
  confirmed nothing on the phone matters (not his daily), so overwriting
  userdata is accepted. Rollback set remains boot-backup-20260921-restored/
  (boot, init_boot, vendor_boot, dtbo; userdata contents would be gone, so
  restoring crDroid afterwards needs a full reflash, not just those four).
  **USB access:** kernel has libcomposite/NCM/RNDIS/ECM/ACM built in, and
  initramfs defaults to `ncm.usb0` (`deviceinfo_usb_network_function`
  unset -> ncm.usb0), so the pmOS debug shell/telnet and later ssh should be
  reachable over USB with no keyboard. Untested on hardware.
  **Correction (to earlier chat wording, not to any doc):** display is not
  dead -- the simple-framebuffer console works (that is how the kernel log
  was photographed); what is missing is a native panel driver. Touch is
  untested. The phone has no other input, so USB is the only way in.
  `scripts/make-boot-images.sh` now also (a) accepts pmOS `/boot/vmlinuz`
  (auto-unwraps the EFI zboot gzip payload) and (b) builds init_boot.img
  from a gzip initramfs via `--initramfs` (legacy LZ4, 8 MiB footer).
  Re-verified: boot/vendor_boot still byte-match v12 pre-footer. init_boot
  is legacy-LZ4 (magic 02 21 4c 18) with the same decompressed cpio as v2 but
  different compressed bytes (lz4 version/level), so not byte-identical to
  v2 -- format equivalent, not proven on hardware with this exact encoder.
- 2026-09-28 (non-split install failed; workaround): `pmbootstrap install`
  (no --split) died at `mkfs.ext4 /dev/installp2: Device size reported to be
  zero`. Root cause: host kernel has `/sys/module/loop/parameters/max_part`
  = 0, so loop devices cannot scan partitions and pmbootstrap's
  `losetup -f -P` never yields /dev/installp2. (--split worked earlier because
  it formats bare files, no partition table.) The failed run also left
  /dev/loop0 attached to samsung-dm1q.img and overwrote the earlier split
  images. Not fixed at the source (would need `loop.max_part=8` on the
  kernel cmdline/modprobe + reboot); instead added
  `scripts/make-pmos-disk.sh`: builds the combined GPT disk image
  (pmOS_boot ESP-typed + pmOS_root Linux-root-arm64-typed, 1 MiB aligned)
  from the two `--split` images using only regular files/sfdisk/dd, and
  grows the root fs (default 4 GiB) since pmOS cannot grow it at first boot
  inside a subpartition image. Tested on dummy filesystems (partition
  contents byte-identical, labels correct, e2fsck clean); not yet run on the
  real images. Untested assumption: initramfs `losetup -P` over the UFS
  userdata block device with 512-byte image sectors (UFS LUs are 4 KiB);
  `deviceinfo_rootfs_image_sector_size` exists if that turns out wrong.
- 2026-09-28 (pmOS boot set flashed, userdata NOT yet): images built into
  `_scratch/pmos-v1/` (boot bc1de9de.., init_boot 8437fa5c.., vendor_boot
  89e6dc8e.., dtbo a5aab00d.., pmos-userdata.img 29694bf9.. 4.5 GiB GPT with
  pmOS_boot 512 MiB + pmOS_root 4 GiB). Pre-flash backup of the installed
  set in `_scratch/pre-pmos-backup-20260928/` (boot/vendor_boot == v12
  exactly, init_boot 207474c1.. as logged earlier) = rollback. Recovery is
  TWRP, root adbd; by-name: boot=sda25 init_boot=sda26 recovery=sda27
  vendor_boot=sda28 dtbo=sda37 userdata=sda41 (239 GB, unmounted).
  **Lesson:** streaming with `adb exec-in "dd of=/dev/block/by-name/X"` from
  the host CORRUPTED the boot partition (19 of 96 MiB matched neither old nor
  new image, caught by readback) -- do not use exec-in for writes. The proven
  path is push to recovery /tmp -> device sha256 == host -> dd conv=fsync ->
  readback (exec-out reads are reliable). Redone that way; all four small
  images now written and readback-verified. userdata (4.5 GiB) exceeds
  recovery /tmp (3.0 GiB free) so it must be pushed and written in chunks.
- 2026-09-28 (first pmOS boot attempt: kernel panic): after flashing the
  full pmOS set (boot/init_boot/vendor_boot/dtbo + 4.5 GiB userdata image,
  all readback-verified; userdata full-image sha256 29694bf9.. verified),
  the phone showed the kernel log freezing at ~0.5 s with
  `Kernel panic - not syncing: No working init found. Try passing init=
  option to kernel.` at [0.499]. So it is an early PANIC (not a display
  takeover): the kernel found no runnable /init, i.e. the initramfs was
  missing/empty/not runnable in the kernel's rootfs. Never reached pmOS
  code, so USB never came up (no lsusb device) -- consistent. Recovery's
  /proc/last_kmsg is useless for this (recovery overwrites sec_log_buf on
  its own boot; only XBL/ABL/recovery text present). Ruled out offline:
  the pmOS kernel config has RD_LZ4/BLK_DEV_INITRD/DEVTMPFS/BINFMT_ELF/
  BINFMT_SCRIPT built in; /init is `#!/bin/busybox ash` with bin/busybox
  (aarch64) and lib/ld-musl-aarch64.so.1 present in the cpio. Differences
  vs v12 that are still candidates: pmOS cpio is 7.2 MB uncompressed (v12
  busybox cpio 1.1 MB); kernel Image grew 42.6 -> 58 MB, which may move
  where ABL places/keeps the ramdisk; ramdisk lz4 encoder differs from v2.
  Discriminating experiment: restored the pre-pmOS busybox init_boot
  (207474c1..) while keeping the new pmOS kernel/vendor_boot/dtbo -- if it
  boots the busybox shell, kernel is fine and the pmOS ramdisk is at fault;
  if it panics the same way, kernel size/placement is at fault.
- 2026-09-28 (RESULT: kernel is fine, pmOS ramdisk is the problem): with
  the old busybox init_boot restored the phone booted normally on the new
  pmOS-config kernel (user-confirmed, "this fixed it"). So the 58 MB kernel
  and its layout are OK; the "No working init found" panic came from the
  pmOS init_boot ramdisk (7.2 MB unpacked, gzip->legacy-LZ4 repack) -- still
  UNRESOLVED which property: size, the lz4 encoding, or the cpio contents.
  Also confirmed the ramdisk on the phone is init v9 (extracted from the
  backup, sha256 207474c1..): it already flushes dmesg to dtbo@1MiB every 3 s
  and starts the USB ACM shell, but ends with a foreground on-screen replay
  (15 s wait, then 25 lines per 8 s) that takes many minutes. Fix: new
  `kernel/initramfs/init-v13` = v9 minus the replay (prints `dmesg | tail
  -n 20` once, then execs the shell). Built from the extracted v9 tree with
  only /init replaced (newc cpio, gzip -> legacy LZ4 via
  make-boot-images.sh) and flashed to init_boot with the push/hash/dd/
  readback method: sha256 9474fe78.. (copy at _scratch/init_boot_v13.img).
  Not yet booted -- v13 boot time is untested. Next for pmOS: find why the
  kernel rejects the pmOS ramdisk (see photo of the lines above the panic,
  and try variants: plain gzip, xz, smaller cpio, concatenated-only).
- 2026-09-28 (ROOT CAUSE of the pmOS panic found): with the busybox v13
  ramdisk running, talked to the phone over the USB ACM shell (host needed
  `sudo modprobe cdc_acm` + chmod on /dev/ttyACM0; new helper
  `scripts/acm-run.sh '<cmd>'`). Full kernel log saved to
  `notes/2026-09-28-pmos-v1-hang/dmesg-busybox-v13-live.txt` (4844 lines,
  7.3.0-rc3, no oops in the boot path). No hang: the two big gaps are
  ~10.2 s (deferred-probe timeout after arm-smmu 3da0000.iommu -517) and
  ~21 s (`regulator: Not disabling unused regulators`, regulator_ignore_unused
  timeout) -> ~31 s of waiting, cosmetic, could be trimmed later.
  Kernel unpacks 10200K of initrd at 0.093-0.116 s and runs /init at 0.497 s;
  the pmOS panic at 0.499 s is the same moment. The pmOS initramfs is
  usr-merged (bin -> usr/bin, lib -> usr/lib, sbin -> usr/bin symlinks) and
  Samsung's vendor ramdisk (unpacked first) has /lib as a REAL dir
  (lib/modules). The kernel initramfs unpacker cannot replace a non-empty
  directory with a symlink, so `lib -> usr/lib` was silently dropped,
  /lib/ld-musl-aarch64.so.1 never existed, dynamic /bin/busybox could not exec
  (ENOENT), => "No working init found". (The old busybox ramdisk was static
  with a real /bin, so it never hit this.) Verified by diffing entry types of
  vendor ramdisk vs pmOS cpio: exactly ONE conflict, `lib` (dir vs symlink);
  live `ls -la /` confirmed /lib is a real directory. `make-boot-images.sh`
  now (1) flattens lib into a real dir with usr/lib -> ../lib and (2) injects
  `kernel/initramfs/dtbo-logger.sh` (dmesg + /pmOS_init.log -> dtbo@1MiB every
  3 s) into the pmOS stage-1 init right after mount_proc_sys_dev. New
  init_boot: sha256 35ea9693.. (`_scratch/init_boot_pmos_v2.img`), 0 type
  conflicts vs vendor ramdisk. NOT yet flashed/booted.
  Also confirmed: busybox v13 flusher works -- dtbo@1MiB holds the current
  boot's dmesg (Linux version .. through the 31.7 s regulator line).
- 2026-09-28 (fixed pmOS init_boot flashed): wrote init_boot_pmos_v2.img
  (35ea9693..) via push/hash/dd/readback -- verified. userdata head 1 MiB
  still equals the pmOS image (0bb9f371..), so the pmOS disk image is
  intact after the busybox detour. Phone now has: pmOS kernel + vendor_boot
  + fixed pmOS init_boot + pmOS userdata. Next: boot it. Expected: pmOS
  stage-1 splash, USB gadget with ncm.usb0 (host gets an interface, DHCP from
  unudhcpd, device 172.16.42.1, ssh user@172.16.42.1). If it stalls, reboot to
  recovery and read dtbo@1MiB (dmesg + /pmOS_init.log).
- 2026-09-28 (RESULT: no panic, got further, found the real remaining bug):
  the lib/usr-merge fix worked -- kernel reached /init, USB gadget + DHCP
  server started. Pulled dtbo@1MiB from recovery (now
  notes/2026-09-28-pmos-v1-hang/dtbo-log-pmos-v2.txt, has both dmesg AND
  pmOS's own stage-1 log -- confirms the injected logger works end to end).
  Failure: 'ERROR: failed to mount subpartitions!' after the 10s timeout in
  mount_subpartitions() (init_functions.sh) -- it drops into pmOS's own
  debug/recovery shell (mass-storage log dump), not a kernel panic.
  Root cause: that function runs 'fdisk -l <real-partition>' DIRECTLY on
  /dev/sda41 (userdata) to count subpartitions -- it never goes through
  deviceinfo_rootfs_image_sector_size at this stage (that only affects the
  later losetup --sector-size call, which is never reached). UFS reports
  4096-byte logical sectors (confirmed: blockdev --getss
  /dev/block/by-name/userdata = 4096), but scripts/make-pmos-disk.sh built
  the GPT with sfdisk's default 512-byte sectors -- so fdisk, reading the
  real device at its true 4096-byte sector size, looked for the GPT header
  at the wrong byte offset and found none. Confirmed on the actual disk
  image, not just theory: sfdisk -l (default 512) on the freshly-built
  image misread it as a dos label with one ee (protective-GPT) entry;
  sfdisk --sector-size 4096 -l on the same file correctly showed the GPT
  with both partitions -- i.e. the verification step in the original script
  had the identical bug and was silently confirming a broken image as fine.
  Fixed both call sites in make-pmos-disk.sh (build AND the sfdisk -l
  self-check) to pass --sector-size 4096. Content placement is MiB-based
  so is sector-size-agnostic in principle, but a second build showed
  e2fsck/resize2fs regenerate a few filesystem-metadata bytes near the
  root partition's start even with unchanged input -- so a 'just patch the
  head/tail 1 MiB' shortcut was NOT safe here; did a full re-flash instead
  (all 4610 MiB, chunked push/hash/dd/readback as before, full-image sha256
  also verified: b3d55cc6..). init_boot is unchanged (still 35ea9693..).
  Not yet booted. Also queued but not yet applied: the ~31s of kernel
  built-in-timeout wait noted earlier is still present and will still slow
  every boot; not addressed this round.
- 2026-09-28 (initramfs-extra fixed, third reflash): pmOS stage 1 mounted
  subpartitions fine (the sector-size fix from the previous entry worked),
  but stage 2 extraction of /boot/initramfs-extra failed: 'cpio: can't
  remove old file lib: Is a directory'. initramfs-extra has its OWN
  top-level bin/lib/sbin usr-merge symlinks (same pattern as stage-1's
  initramfs, confirmed by listing it directly from the pmbootstrap boot
  dir), and cpio refuses to replace the now-real /lib (created by stage-1's
  FIX 1) with a symlink. Everything after that error in the log (ERROR:
  udev not found!, parted: not found, e2fsck: not found) was fallout: those
  binaries only exist inside initramfs-extra and never got extracted.
  Fix: new scripts/fix-initramfs-extra.sh strips the 3 top-level symlinks
  from initramfs-extra's cpio (leaves every other usr/* path untouched,
  since real bin/lib/sbin already exist by the time it extracts). Edited
  the ext2 boot image in place with 'debugfs -w' (no loop device, no root
  needed) rather than rebuilding it, e2fsck -fy came back clean after.
  Wired the same fix into make-pmos-disk.sh so it auto-detects and applies
  automatically on any future boot image, not just by hand.
  Reflash: hoped a partial (boot-region-only) patch would suffice since only
  boot.img changed; checked first and found root region also differs
  (e2fsck/resize2fs regenerate a few superblock bytes even on unchanged
  input, same finding as the previous entry) -- corrected the stale comment
  in make-pmos-disk.sh that claimed partial reflash was safe. Did a full
  4610 MiB chunked reflash again (all chunks + full-image sha256 verified:
  6aab0570..). init_boot unchanged (35ea9693..). Not yet booted.
- 2026-09-28 (MILESTONE: first real pmOS userspace boot on hardware):
  after the initramfs-extra fix (previous entry), the phone booted all the
  way to the real postmarketOS root filesystem on UFS -- confirmed live via
  ssh (Baraa's own session, not adb/recovery): /etc/os-release
  PRETTY_NAME='postmarketOS edge', hostname samsung-dm1q, uname 7.3.0-rc3
  '#2-samsung-dm1q-mainline'. usb0 (ncm.usb0 gadget) came up with
  172.16.42.1 as designed, ssh login with the password Baraa set during
  pmbootstrap install worked. This is the actual Phase 2 Step 0 milestone
  from the top of this doc (a real Alpine/pmOS rootfs, reachable over a
  getty/shell, UFS as root) -- done, on real hardware, not just in tooling.
  Non-fatal: 'sleep not found' from kernel/initramfs/dtbo-logger.sh's
  background loop (busybox in this initramfs apparently lacks a bare
  'sleep' applet/symlink) -- cosmetic, the flusher is backgrounded so it did
  not block boot; low-priority fix is to call it as 'busybox sleep' like
  the rest of the script already does for other commands.
  **UPDATE 2026-10-17: not cosmetic after all.** After `switch_root` the loop kept running in
  the deleted initramfs and flooded the text console forever (no /tmp, no busybox, no sleep =
  busy loop). Fixed in the script (silenced, ends when /dtbo-logger.sh disappears), tested on
  the PC, patched init_boot built but not flashed: docs/09 section 16.
  Not yet characterized from inside pmOS itself: boot time end-to-end,
  whether udevd/mdev actually populated /dev fully, disk space headroom
  (root is 4 GiB), swap, and of course display/touch/WLAN (still no driver
  work done -- out of scope for Step 0 per the top of this doc).
- 2026-09-28 (dmesg + live fdisk review of the booted system): read the full
  5341-line dmesg (notes/2026-09-28-pmos-v1-hang/dmesg-ssh-live.txt) and
  live 'sudo fdisk -l /dev/sda41' output. Nothing fatal. Notable, all
  pre-existing/cosmetic, not new to this session: [Firmware Bug] kernel
  image misaligned at boot (ABL loading quirk, harmless in practice);
  'bootconfig found but CONFIG_BOOT_CONFIG is not set' (Samsung's stock
  vendor bootconfig -- panel id, lpcharge flags etc -- is silently ignored,
  which is fine, we don't need those args); a batch of 'ramoops: error in
  header' lines on this first boot into a fresh ramoops region (expected,
  pstore/ramoops still registered fine after); two 'OF: reserved mem:
  failed to reserve memory' lines for uh-heap@b0200000/uh-guest@b1000000
  (TrustZone/hypervisor regions -- same CLASS of region that caused resets
  on the gts9uwifi reference port when touched; system has run fine so far,
  but worth remembering as a standing risk, not yet root-caused).
  CORRECTION to the 2026-09-28 storage-layout entry above, which said 'pmOS
  cannot grow root at first boot inside a subpartition image' -- that was
  WRONG. Live evidence: 'sudo fdisk -l /dev/sda41' now shows a 222.87 GiB
  GPT disk with p2 (root) spanning sectors 131328-58424817 (222.4G) --
  pmOS's init DOES auto-grow the last partition to fill whatever real space
  exists on the containing block device (sda41/userdata, 239 GB total) even
  in the subpartitions/dd-to-raw-partition layout, same as its ordinary
  SD-card/eMMC install behavior. This is why 'df -h /' showed 216G instead
  of the ~4G scripts/make-pmos-disk.sh built -- intended pmOS behavior, not
  a bug. Net effect: the device now has ~222 GB of real usable root storage
  (though scripts/make-pmos-disk.sh's ROOT_MIB arg is still meaningful as
  the *initial* size before this auto-grow, so it should stay reasonably
  small to keep image-build/reflash time down; no need to build it any
  bigger than needed just to end up with more headroom).
- 2026-10-01 (process rule: kernel rebuilds vs. the rootfs' modules): the
  "&pcie0 breaks whenever the devicetree changes" regression (docs/07, "ROOT
  CAUSE FOUND 2026-10-01") was a coupling in THIS workflow, not a devicetree
  bug: pmaports' mainline config signs every module with a per-build random
  key and forces kernel lockdown, the rootfs (and its /lib/modules) is built
  once, and the boot images are rebuilt often -- so every rebuilt kernel
  refused every module (PCIe PHY, pwrseq, clock controllers, ...). Rules from
  now on: (1) `config-dm1q.fragment` forces lockdown off from r4 on, so a key
  mismatch is tolerated (tainted modules) instead of fatal; (2) after every
  `make-boot-images.sh` run
  `scripts/check-kernel-module-key.py --boot <boot.img> --rootfs
  _scratch/pmos-v1/pmos-userdata.img` -- MISMATCH is acceptable for DTS-only
  changes, but after any kernel *config* change (this kernel has no
  MODVERSIONS, so nothing else guards the module ABI) refresh the rootfs'
  `/usr/lib/modules/<release>` from the new APK (tar over ssh on the USB
  gadget network, then `depmod`) or rebuild the rootfs; (3) keep
  `_scratch/pmos-v1/` and the pmbootstrap rootfs chroot -- they are the only
  copies of the module set that matches the pmos-v1 kernel (`r1.apk` in
  pmbootstrap's packages/ was overwritten by a later build).
- 2026-10-03 (process rule: apk operations on the phone regenerate /boot/initramfs-extra):
  `postmarketos-mkinitfs`'s apk trigger watches `/lib/firmware/*`, `/usr/lib/udev`,
  `/usr/share/kernel/*`, `/usr/share/deviceinfo`, `/usr/share/mkinitfs/*`,
  `/usr/share/plymouth` and `/usr/lib/systemd/boot` (see the rootfs' `/lib/apk/db/triggers`).
  Any `apk add/upgrade/del` that touches those paths rewrites `/boot/initramfs` and
  `/boot/initramfs-extra` on the phone, and the regenerated initramfs-extra has the
  usr-merge symlinks `bin`/`lib`/`sbin` again -- stage 1 (real `/lib`) then dies with
  `cpio: can't remove old file lib: Is a directory`, stage 2 has no udev/e2fsck/parted,
  and the phone never leaves the initramfs (log: endless `couldn't open /dev/input/`;
  docs/07 section 12 is the worked example, caused by installing
  `linux-firmware-ath11k`). Rule: after ANY apk change on the phone, re-apply the fix
  before the next boot -- from recovery `scripts/fix-phone-initramfs-extra.sh` (dry run
  by default, `--yes` installs, `--file` rolls back). Check what a package would trigger
  first with `cat /lib/apk/db/triggers` on the phone/rootfs.
- 2026-10-04 (process rule: the PC is on the phone's USB network OR on the internet, never both):
  while the PC is connected to the phone (ssh to 172.16.42.1) it has no internet, and a chat
  session running on that PC drops -- any output in flight is lost (this is what ate the first
  "continue" of the 2026-10-03/04 session). So never make the chat wait for the phone's
  network: the PC-side steps that need the phone in recovery (adb over USB, no network:
  flashing, pulling the dtbo log, the initramfs-extra repair) can be done with the chat
  connected; everything that needs the phone's USB network goes through
  `scripts/collect-phone-state.sh <label> [--reboot] [--reload]`, which the user runs in a
  terminal (password typed at most twice), which saves everything under `notes/<date>-<label>/`,
  and which says "done" -- only then reconnect to the internet and tell Claude, who reads the
  files from disk. Never apk-install anything on the phone without checking the mkinitfs
  trigger list first (rule above) -- download packages on the PC beforehand
  (`_scratch/phone-pkgs/` holds the ath11k firmware, already installed).
- 2026-10-08 (process rule: verify the instrument before the experiment): the 2026-10-07 `--fresh`
  run's register sampler printed `????????` for every register -- it read MMIO with `dd if=/dev/mem`,
  which cannot work on arm64 (`read()` on `/dev/mem` only serves mapped RAM, `valid_phys_addr_range()`;
  docs/07 section 14.2) -- and its idle mode never enabled the endpoint's memory space, so a run that
  cost the user two password prompts and a network switch answered nothing. Rules: (1) MMIO is read with
  `scripts/bin/mmio-read-aarch64` (`mmap`; source `scripts/mmio-read.c`, built by
  `scripts/build-mmio-read.sh`), never with dd/od on `/dev/mem`; (2) every sampler first reads a known
  value and REFUSES TO RUN when it cannot (`phone-mhi-regdump.sh` self-tests the helper); (3) every
  phone-side script gets a PC-side test against a fake environment before the user is asked to run it
  (`scripts/test-mmio-read.sh`, `scripts/test-phone-mhi-regdump.sh`; `shellcheck -s sh`); (4) a
  measurement that comes back all-`?` or all-ff is a broken instrument until shown otherwise, not a
  finding.
- 2026-10-08 (process rule: check the kernel snapshot for known regressions; carrying an upstream patch):
  we run an -rc snapshot (7.3-rc3), so a hardware stall can be an upstream regression -- before spending
  experiments on chip-side theories, search the subsystem list (linux-pci, linux-arm-msm, ...) for the
  driver involved (docs/07 section 14 is the worked example: a known, already-fixed `pcie-qcom` bug).
  To carry a patch: add it to the package (`source=` + `sha512sums`, bump `pkgrel`); prove it IS the
  upstream patch (the file's git blob hash equals the patch's pre-image `index` line and the patched
  file's blob hash equals the post-image: `notes/2026-10-08-pcie-bdf-sid-regression/build-patch.sh`);
  compile the touched object against the real config in a scratch `O=` dir with the cached tree restored
  afterwards (`compile-check.sh`, ~20 s, no sudo); put the upstream commit / message-id and "drop me
  when ..." in the patch header. A DT-only workaround for a test is built with
  `scripts/make-dtb-image-set.sh` (no kernel build, verified against a reference set); the repo DTS stays
  canonical and the workaround lives in `_scratch/`.
- 2026-10-10 (milestone): WLAN. The QCA6490 boots under ath11k (firmware WLAN.HSP.1.1-03125-...-3.6510.41),
  `wlan0` associates and gets DHCP after a normal reboot (test image v9: the cause was the PCIe
  BDF-to-SID table, docs/07 sections 14-15). Phase 2 step 6's WLAN half is reached; link quality and
  DNS are open (docs/02 item 15); the display half is not started (item 18).
- 2026-10-11 (process rule 2, extended; found by the r5 first boot, docs/07 section 15.12): the rule of
  2026-10-01 only named kernel *config* changes. A kernel whose *code* changed (any patch) also makes the
  rootfs' old module tree unusable: every module fails BTF validation (`failed to validate module [x] BTF:
  -22`, `CONFIG_MODULE_ALLOW_BTF_MISMATCH` is not set) and the phone boots without PCIe, clocks, RTC, ...
  Rule: every image set built with `--new-kernel` (or from a new kernel APK) is handed over together with
  `bash scripts/refresh-phone-modules.sh --apk <that APK> --reboot` as step 1, run while the phone still
  boots a kernel that can reach userspace; `scripts/check-kernel-module-key.py` stays as the second check.
  The swap moves the old tree to `/var/lib/dm1q-modules-backup/`; rolling back to an older kernel means
  moving it back (the older kernel refuses the new tree for the same reason).
- 2026-10-11 (milestone): the PCIe fix is carried properly. Kernel r5 (upstream "Honor IOMMU provider's
  #iommu-cells" patch) + the canonical DTS + a refreshed module tree: `wlan0` up with no devicetree
  workaround (docs/07 15.13). The v9 `iommu-map` override is retired. Baseline from here:
  `_scratch/pmos-v10-r5-pcifix/` and the r5 module tree on the rootfs.
- 2026-10-11 (process rule 7, privacy of raw captures): the repo is public and the phone's own logs carry
  the home network's SSID, the access point's BSSID, the phone's and the USB gadget's MAC addresses (and
  scan results list neighbours). The six WLAN commits of 2026-10-11 were pushed with them, then redacted and
  force-pushed (31 distinct MACs -> `xx:xx:xx:xx:xx:NN`, same width, one number per address; SSID ->
  `<home-ssid>`; module-signing key serials and SKIDs are longer colon chains and are left alone; every
  redacted file un-redacts back to its original, checked). The private map and a backup bundle live in
  `_scratch/redact/`, never in the repo. Rule: raw captures (`notes/`, `collect-phone-state.sh` output) are
  redacted BEFORE they are committed. To do: fold the redaction into `collect-phone-state.sh` so it
  happens at capture time.
