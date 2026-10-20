# Handoff 2026-10-20: the touchscreen works for a while, then stops (STM FTS2BA61Y)

This is the FULL version of the prompt Baraa pastes into a new chat. The repo (`/home/elgamal/Documents/GitHub/dm1q-mainline`) is the record and the
source of truth; reference material is in `/home/elgamal/Documents/GitHub/_scratch`. Do not re-derive what the docs settle. Write findings into the repo
(docs/08 for the touch work, a new section or file as needed), not only into the chat.

## 0. Read first, in this order

1. `git log --oneline | head -25` and `git status` (HEAD was `7a2312b` plus the handoff commit; local only, Baraa pushes).
2. `README.md`, `docs/00-overview.md`, `docs/01-phase1-workplan.md`, `docs/02-open-questions-and-risks.md` (newest UPDATE lines at the end of item 18),
   `docs/06-pmos-userspace-plan.md` (process rules).
3. **`docs/08-input-bringup.md` completely**, sections 2.9 and 2.10 first: the driver's design, what was verified, and the FIRST occurrence of this problem.
4. `docs/11-gpu-bringup.md` sections 5 and 9.5 to 9.10 (how the phone got to its current state), `docs/10-plasma-mobile.md` sections 5 to 9.
5. The driver: `kernel/patches/0002-Input-add-ST-FTS2BA61Y-SPI-touchscreen-driver.patch` (same patch in `pmaports/device/testing/linux-samsung-dm1q-mainline/add-fts2ba61y-touchscreen.patch`),
   Samsung's vendor driver `../_scratch/samsung-stm-spi/stm_spi`, the RFC series `../_scratch/fts2ba61y-upstream/rfc-0806{2,3,4}.txt`.
6. The Project memory file `overview.md`. Then answer in three or four lines (see section 7).

## 1. Hard constraint and rules (they cost time when forgotten)

- **Only Baraa can ssh to the phone** (the PC loses internet and the chat drops while it is on the phone's USB network). You cannot run anything on the phone.
  Phone-side work = a POSIX-sh script + a PC-side test + a flag in `scripts/collect-phone-state.sh`; Baraa runs
  `bash scripts/collect-phone-state.sh <label> --<flag>`, reconnects, says "done", you read `notes/<date>-<label>/`. TWRP flashes, watching the screen, touching it and sudo
  are Baraa's: ask. Give ONE exact command at a time.
- Label claims **FACT** (read in a file / seen on the phone) or **INFERENCE**. Never commit MACs, SSIDs or serials (raw `notes/<date>-*/` captures stay uncommitted). Never push.
- Every phone-side script has a PC-side test (dash and busybox are not installed on the PC: the tests skip dash and run bash; also `bash --posix -n` and `shellcheck -s sh -S warning`).
  Pattern to copy: `scripts/phone-gpu-probe.sh` + `scripts/test-phone-gpu-probe.sh` (env overrides, fake sysfs, stubs, tripwires, no-write checks).
- **Do not run apk on the phone, and warn Baraa before anything that would** (rule 3 of docs/06): any apk operation touching a trigger dir regenerates `/boot/initramfs-extra`, and the regenerated file
  hangs stage 1 (`cpio: can't remove old file lib: Is a directory`, then an endless `couldn't open /dev/input/` loop; the stage-1 log is in `dtbo@1MiB`:
  `adb exec-out "dd if=/dev/block/by-name/dtbo bs=1M skip=1 count=4" | strings`). Repair from TWRP: `bash scripts/fix-phone-initramfs-extra.sh` (dry run), then `--yes`.
  This happened on 2026-10-19 after Baraa ran `apk upgrade` (docs/11 9.4); the same upgrade also broke PAM (docs/11 9.10).
- Kernel code or config changes: the user builds (`pmbootstrap checksum linux-samsung-dm1q-mainline && pmbootstrap build linux-samsung-dm1q-mainline`, needs his sudo) and runs
  `scripts/refresh-phone-modules.sh <apk> --reboot`. DT-only changes: `scripts/make-dtb-image-set.sh` then `scripts/flash-recovery.sh boot|vendor_boot <img>` from TWRP; announce every flash first and keep a rollback
  (`../_scratch/pmos-v19-gpu-bind` is flashed now; `../_scratch/pmos-v17-splash-iommu` is the known-good set before the GPU node).
- The shell on the PC is **fish**: wrap commands in `bash -c '...'`; heredocs inside `bash -c` break under fish (use the Filesystem `write_file` / `edit_file` tools to write files). Desktop Commander's `start_process` runs commands.
- Keep rollbacks; leave the phone on a working configuration between sessions.

## 2. Where the project is (all FACT, details in the docs)

- Mainline Linux 7.3-rc3 + 3 patches (panel, touch, PCIe iommu-cells) on the Galaxy S23 (dm1q, SM8550-AC), postmarketOS userspace. Display (native panel, 120 Hz command mode + DSC), WLAN, UFS, keys and touch work.
- **GPU (docs/11):** `&gpu` is enabled in the flashed v19 DTB only (`../_scratch/pmos-v19-gpu-bind/dm1q-gpu.dts`; the canonical `dts/dm1q/dm1q.dts` does NOT have it yet). The Adreno 740 binds, the GMU boots, and with Samsung's own signed zap shader
  (pulled from the phone's vendor partition; the generic linux-firmware zap is refused by the secure world with -22) `hw_init` completes with no error. **The firmware is NOT in a standard path, so after every reboot the GPU is down**:
  to bring it up run `DM1Q_GPU_FW=/home/elgamal/Documents/GitHub/_scratch/dm1q-gpu-fw-vendor-run bash scripts/collect-phone-state.sh <label> --gpu-powerup=full` (it points `firmware_class.path` at a staging copy for one open of the
  render node, then restores it). **Touch debugging does not need the GPU.**
- **Plasma Mobile** (installed with apk, 1155 packages): after the PAM override (`/etc/pam.d/systemd-user` and `systemd-run0`, marker `# dm1q-pam-fix`, created by `scripts/phone-pam-fix.sh`) it ran for 240 s with 0 restarts via
  `bash scripts/collect-phone-state.sh <label> --pam-fix --gpu-powerup=full --plasma-start=240` (with `DM1Q_GPU_FW` as above). kwin logged `Added render device /dev/dri/renderD128: FD740` and
  `Chose /dev/dri/renderD128 as the primary GPU`; no SIGILL (the old llvmpipe/SVE crash is gone), no GPU hang, no SMMU fault. NOT verified: that the GPU executes work (the `gpu-irq` counter was not captured after the run).
  Baraa saw the desktop on the panel; the power and volume keys work.
- Phone state: v19 image set flashed (boot + vendor_boot), `/boot/initramfs-extra` repaired from TWRP, PAM override in place, `/root/dm1q-gpu-fw` holds the vendor firmware set, ui user is uid 10000, ssh `user@172.16.42.1`.

## 3. THE PROBLEM

**Symptom (Baraa, 2026-10-19/20):** touch works for a while and then stops responding; the physical keys keep working. He saw it in Plasma Mobile (2026-10-19 ~21:05) and **also earlier on the tty,
using the on-screen keyboard (buffyboard) before the GPU work existed** - so it is NOT caused by the GPU, Plasma, kwin or the lock screen alone. A first occurrence, after a warm reboot with no display driver, is documented in
docs/08 2.10 (the chip never raised gpio25; the driver's soft reset does not restore whatever state the chip keeps; "fixed" by re-running `refresh-phone-modules.sh ... --reboot`, never explained).

**The driver today (docs/08 2.9, kernel/patches/0002):** SPI (`spi0.0` on the geni SE at `a90000`), level-low interrupt `gpio25` (`178: ... msmgpio 25 Level fts2ba61y`), threaded handler; supplies `vdd` L12B 1.8 V and
`avdd` L16B 3.0 V enabled by the driver (no always-on in the DT); probe: supply wait, soft reset, id read (`53 54 40 36 01`, resolution 4095x4095, 16 TX x 34 RX); SENSE_ON is sent on input open; reports ~120 Hz
(`sync-reportrate-120` in Samsung's DT). It **never sets the scan mode** (Samsung's sequence: touch-function write, `C0 13` force calibration and `C0 62` clear-events each with an echo event, `A0 00 01` scan mode MS+SS echo-checked, then SENSE_ON; see
`stm_core.c` `stm_ts_hw_init` / `stm_ts_start_device`, `stm_fn.c` `stm_ts_set_scanmode`). Listed in docs/08 as "not yet verified": sensing off at `close()`, suspend/resume, behaviour over hours.

**What the 2026-10-19 Plasma run shows (`notes/2026-10-19-gpu-plasma2/`, uncommitted, FACT):**
- The kernel log has NO error line in the window: no `irq 178: nobody cared`, no SPI/geni errors, no hangcheck, no SMMU fault, no msm error. The failure is silent.
- kwin had all four input devices open (`/dev/input/event0..3`).
- `gpio.txt` (taken after Plasma stopped, so with the device closed and probably sensing off: NOT conclusive) shows `gpio25 : in high` (the idle level).
- The panel was power-cycled three times (`panel id 81 02 25` printed by the panel driver at +67 s, +88 s, +110 s after the start: DPMS off/on or the power key).
- A `kscreenlocker_greet --immediateLock` process appeared mid-session (the screen locked) and the greeter logs `Worker not ready yet, cannot authenticate` (the `kde` PAM service; separate bug, see section 5).
- A virtual `buffyboard` input device appeared at +121 s (kernel log), with no buffyboard process in the final `ps`.

**Not known:** when exactly it stops and what triggers it (idle time, number of touches, panel off/on, temperature, time since open), and whether the CHIP stops raising the interrupt, the DRIVER stops reading, or USERSPACE stops listening.

**Hypotheses (all INFERENCE), each with the observation that decides it:**
- **H1 the chip stops scanning/reporting** (no scan mode set, ESD or low-power state, display-sync loss). Decider: with a reader holding the evdev device open and a finger moving, `fts2ba61y` in `/proc/interrupts` stays frozen and gpio25 stays high.
- **H2 interrupt asserted but not serviced:** gpio25 LOW while dead and the count frozen (handler thread stuck, a oneshot irq never unmasked after an error path, an `IRQ_NONE` return). Decider: gpio25 level + count + the driver's error paths.
- **H3 the count keeps rising but evdev is silent** (slot/tracking-id logic stuck, a missing leave event, an unhandled event type). Decider: raw bytes from the evdev node vs the interrupt count.
- **H4 evdev still produces events but userspace ignores them** (libinput/kwin/buffyboard grab or stuck slot, lock screen). Least likely: the tty case.
- **H5 coupled to the display power cycle** (the chip is synced to the DDI; the vendor driver re-inits on LCD on). Decider: failure follows a `panel id` line in dmesg; test by blanking/unblanking the backlight/panel without touching.
- **H6 SPI controller or regulator state** (runtime PM of the SE, rail state). Decider: `/sys/bus/spi/devices/spi0.0/power/*`, the SE's `runtime_status`, `regulator_summary` for L12B/L16B.

## 4. THE STEP: instrument first, then fix (docs/08 2.10 already says not to change the kernel speculatively)

- **A (PC only).** Read the driver patch and the vendor driver side by side; write down in docs/08 (new 2.11) which behaviours ours lacks: init sequence, scan mode, error/ESD/status event handling, reset-on-error, `close` / suspend / resume, event FIFO reading, `IRQ_NONE` paths.
- **B (read-only capture, the first phone-side script).** `scripts/phone-touch-watch.sh` + `scripts/test-phone-touch-watch.sh` + `--touch-watch=SECONDS` in `collect-phone-state.sh`. POSIX sh, root. It finds the evdev node by name
  (`STMicroelectronics FTS2BA61Y Touchscreen` in `/proc/bus/input/devices`), holds it open with a background reader that counts bytes/events (opening it sends SENSE_ON, so only a held-open device is a valid test), and every 0.5 to 1 s prints a timestamp, the `fts2ba61y`
  interrupt count, gpio25 level (`/sys/kernel/debug/gpio`), evdev bytes/events, the SPI device's and the SE's runtime-PM status, L12B/L16B regulator state, DRM connector `DSI-1` state and backlight (`bl_power`, brightness), temperature, and any NEW dmesg lines;
  it marks when the interrupt count has not moved for N seconds. Run it on the tty (no Plasma, no GPU needed; stop buffyboard first so nothing else holds the device) while Baraa drags a finger in slow circles for the whole window and says roughly when it felt dead; a second run
  with the panel blanked/unblanked (backlight 0 / `bl_power`) and NO touching tests H5. Read-only; it must never open `/dev/dri/*` (the GPU powers up on the first open).
- **C (recovery experiments, only once dead, one per step, each reversible):** `echo spi0.0 > /sys/bus/spi/drivers/fts2ba61y/unbind` then `bind`; `rmmod`/`modprobe fts2ba61y`; close and reopen the reader; blank/unblank the panel. Whether touch returns tells H1/H2/H5 apart.
- **D (the fix, only after B/C name the cause):** driver update as kernel patch 0002 (and the pmaports copy, package rebuild): Samsung's init sequence, scan mode, error/ESD event handling, proper `close`, suspend/resume or a panel-power hook, and the debugfs raw-transfer file docs/08 2.10 proposed so the chip can be poked without a rebuild.
  Compile-check against the kernel tree before asking for a build. Then the user builds, `refresh-phone-modules.sh`, and a long-run test (hours, with idle and screen-off cycles).
- Record each result in docs/08 (FACT/INFERENCE), update the docs/02 item if one applies, commit locally (never push), and update this handoff's status at the end.

## 5. Later steps (not for this chat unless the touch work is done)

1. Verify the GPU really executes under Plasma: capture `gpu-irq` / `gmu` interrupt counts and devfreq `cur_freq` during use (extend `phone-plasma-start.sh`'s monitor), kwin's renderer, hangcheck behaviour under load.
2. Make the GPU come up by itself at boot: ship the three firmware files (SQE and GMU are byte-identical to linux-firmware's; the zap is the phone's own `a740_zap.mbn`, sha256 `60cf7ab4f3d96e09...`, proprietary Samsung: not in the repo) where the kernel looks at the first open after boot
  (`/lib/firmware/postmarketos/qcom/...`); an apk install triggers mkinitfs, so TWRP `fix-phone-initramfs-extra.sh` before the next reboot. Then decide about merging `&gpu` + the zap `firmware-name` into the canonical `dts/dm1q/dm1q.dts`.
3. Plasma at boot (enable `plasma-mobile.service` or autologin), the lock screen (`kde` PAM service: "Worker not ready yet, cannot authenticate"; check `fingerprint-auth` / `postlogin` includes), screen timeout and DPMS behaviour, `buffyboard` / `ttyescape` coexistence with kwin.
4. Remove the PAM override when linux-pam / systemd are consistent again (`scripts/phone-pam-fix.sh ... undo` via `--pam-fix=undo`); consider reporting the linux-pam 1.7.1-r4 / systemd-262 pam_selinux mismatch upstream.
5. GPU polish: the 719 MHz OPP and speedbin handling, `mesa-vulkan-freedreno` (check `/lib/apk/db/triggers` first), `eglinfo` / `kmscube`, thermals, suspend.
6. Display open items (docs/09): warm-reboot panel id `00 00 00`, HBM / brightness above 0x07ff, 60 Hz / VRR, suspend/resume, AVDD source, dispcc WARN.
7. Packaging and upstreaming: pmaports pkgrel bumps (device package sysctl file, firmware package), panel and touch binding + driver submissions, the 3 kernel patches.
8. Remaining hardware by priority (docs/01 scope decisions stand: camera and modem are out of scope for now): audio, battery/charging, suspend, USB gadget, Bluetooth, sensors. Kupfer after postmarketOS.

## 6. Cheat-sheet

- Collector flags in this area: `--gpu`, `--gpu-powerup=sqe-gmu|full` (needs `DM1Q_GPU_FW=<dir with qcom/a740_sqe.fw, qcom/gmu_gen70200.bin, qcom/sm8550/a740_zap.mbn>`), `--pam`, `--pam-fix[=check|undo]`, `--plasma-start=SECS`,
  `--display`, `--drm-test`, `--backlight`, `--touch` (only for the spidev test image of docs/08 B1, not for the normal kernel). Output goes to `notes/<date>-<label>/` (`dmesg.txt`, `gpio.txt`, `probe.txt`, `session.log`, plus the flag's own file).
- Useful existing tools: `scripts/phone-display-probe.sh`, `scripts/phone-backlight-test.sh`, `scripts/flash-recovery.sh`, `scripts/fix-phone-initramfs-extra.sh`, `scripts/refresh-phone-modules.sh`, `scripts/make-dtb-image-set.sh`.
- Evidence of this session (uncommitted): `notes/2026-10-19-gpu-plasma2/` (Plasma run), `2026-10-19-pam-diag/`, `2026-10-19-gpu-powerup-full-vendor/`, `2026-10-19-gpu-bind/`, `2026-10-18-gpu-baseline/`, `2026-10-19-v19-gpu-bind-hang/`.
- Pitfalls met: fish heredocs; `apk upgrade` (initramfs-extra and PAM); the edge mirror printed `HTTP: unrecognized server error` / redirects; the ISP (TE Data) hijacks plain http (use https mirrors); a reboot drops the GPU until `--gpu-powerup=full` is run again.

## 7. First reply expected

Read the files above, then tell Baraa in three or four lines: what the driver lacks compared with Samsung's, which hypothesis you rank first and why, and what the first phone-side script (`phone-touch-watch.sh`) will capture.
No flash and no kernel change in the first step.

## 8. Status, end of 2026-10-20

- Step A is done and committed (`docs/08` section 2.12: what our driver lacks vs Samsung's `stm_spi`; H1 ranked first, H5 the likely trigger; the `spi:spi_transfer_stop` tracepoint as the no-rebuild way to see the chip's last event, not yet checked on the phone).
- Step B (`phone-touch-watch.sh`) was NOT started: Baraa redirected the session to "later steps" 1-2 of section 5 (GPU firmware at boot, Plasma autostart). Written and PC-tested, not yet run on the phone: `scripts/phone-boot-setup.sh`, `scripts/test-phone-boot-setup.sh`, `--boot-setup=MODE` in the collector; record and order of steps in `docs/11` 9.12.
- Consequence for touch: once Plasma starts at boot there is no tty on-screen keyboard, and the lock screen cannot authenticate (docs/11 9.12), so the touch drop-out gets more costly. Resume with Step B whenever Baraa says so.
