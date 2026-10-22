# Input bring-up: physical keys, then touch

Started 2026-10-12. Item 16 of docs/02 is the summary; this file is the trail.

## 1. Keys (Task A)

### 1.1 Facts (source: Samsung downstream DT, `_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`)

| Key         | Hardware                                   | Binding                                   | Code            |
|-------------|--------------------------------------------|-------------------------------------------|-----------------|
| Power       | PMK8550 PON `pwrkey`, irq `<0 0x13 0x7 EDGE_BOTH>` | `qcom,pmk8350-pwrkey`              | KEY_POWER (116) |
| Volume down | PMK8550 PON `resin`, irq `<0 0x13 0x6 EDGE_BOTH>`  | `qcom,pmk8350-resin`               | 114 = KEY_VOLUMEDOWN |
| Volume up   | PM8550 gpio 6, active low, pull-up, power-source 1, input-enable | `gpio-keys`, debounce 15 ms, can-disable, wakeup | KEY_VOLUMEUP (115) |

Mainline's `sm8550-qrd.dts` (7.3-rc3) uses the identical arrangement: `&pon_pwrkey` okay,
`&pon_resin { linux,code = <KEY_VOLUMEDOWN>; }` okay, a `gpio-keys` node with `key-volume-up` on
`&pm8550_gpios 6`, plus the `volume_up_n` pinctrl state. `pmk8550.dtsi` already defines `pon_pwrkey`
(compatible `qcom,pmk8350-pwrkey`, same irq, `linux,code = <KEY_POWER>`) and `pon_resin` (same irq),
both `status = "disabled"`; their interrupt specs match Samsung's exactly.

### 1.2 Kernel config (checked, not assumed; `~/.cache/dm1q-kernel-src/out-real/.config`)

`CONFIG_INPUT=y`, `CONFIG_INPUT_KEYBOARD=y`, `CONFIG_KEYBOARD_GPIO=y`, `CONFIG_INPUT_PM8941_PWRKEY=y`,
`CONFIG_PINCTRL_QCOM_SPMI_PMIC=y`, `CONFIG_INPUT_EVDEV=m` (module, loads from the rootfs).
Conclusion: **DT-only, no kernel rebuild, no module-tree refresh** (docs/06 rule 6 does not apply).

### 1.3 DTS change (`dts/dm1q/dm1q.dts`, appended before the "NOT STARTED" comment)

- `/ { gpio-keys { key-volume-up ... } }`, `&pm8550_gpios { volume_up_n ... }`
- `&pon_pwrkey { status = "okay"; }`, `&pon_resin { linux,code = <KEY_VOLUMEDOWN>; status = "okay"; }`
- `dm1q.dts` already includes `<dt-bindings/input/input.h>` and `gpio.h` (lines 35-36).

### 1.4 Test image set

`bash scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --out ../_scratch/pmos-v11-keys` -> OK.
Kernel in boot.img identical to the r5 reference; PCIe fix present. DTB diff against the r5
reference (dtc round-trip) contains only: the `volume-up-n-state` pin group, `pwrkey` and `resin`
status okay (+ `linux,code = 0x72` on resin), and the `gpio-keys` node. Nothing else changed.
Flash boot + vendor_boot only.

### 1.5 Hardware result

**PASS, 2026-10-12** (v11-keys flashed from TWRP, r5 kernel; evidence `notes/2026-10-12-v11-keys/`).

- Three input devices: `gpio-keys` (event0), `pmic_pwrkey` (event1), `pmic_resin` (event2); all three
  probes return 0 (`pm8941-pwrkey` at ~6.87 s for the two PON keys, `gpio-keys` at 0.41 s).
- One press + release per key, raw `struct input_event`: event0 code 115 KEY_VOLUMEUP, event1 code 116
  KEY_POWER, event2 code 114 KEY_VOLUMEDOWN (value 1 on press, 0 on release).
- Not tested: wakeup from suspend (no suspend path yet), long-press power-off behaviour.

### 1.6 Reading events on the phone (pitfalls)

- `hexdump -C /dev/input/eventN` fails with EINVAL (busybox reads 16 bytes; evdev wants whole 24-byte
  events). Use `sudo dd if=/dev/input/eventN bs=24 count=4 | hexdump -C` (4 events = one press+release).
- `dmesg` needs sudo on this rootfs.
- `evdev` is a module here; the nodes exist, so it loaded without help.

## 2. Touch (Task B) — scoping, B1 (spidev proof) and B2 (driver), 2026-10-12

See docs/02 item 16 and docs/05 "Touch controller ... CORRECTION 2026-10-12" for why this is an
STMicroelectronics FTS2BA61Y on SPI and not the Goodix on I2C.

### 2.1 Prior art (rule 4) — a driver exists upstream-bound, it is not in 7.3-rc3

- `grep -ri fts2ba61y` over `drivers/`, `Documentation/`, `arch/arm64/boot/dts` of the 7.3-rc3 tree:
  **no hit**. `stmfts.c` there is I2C only. Kernel config: `TOUCHSCREEN_STMFTS` unset, `SPI_QCOM_GENI=m`,
  `SPI_SPIDEV=m`, `QCOM_GPI_DMA=m`.
- LKML, 2025-09-11: *[RFC PATCH 0/2] Input: add fts2ba61y touchscreen driver* by Eric Goncalves, upstreaming
  a driver originally by Ivaylo Ivanov: binding `st,fts2ba61y.yaml` + `drivers/input/touchscreen/fts2ba61y.c`
  (588 lines). The cover letter names Galaxy S22 series and Z Fold 5 as users.
  https://lkml.iu.edu/2509.1/08064.html (patch 2/2: https://lkml.iu.edu/2509.1/08062.html)
- v1 review by Dmitry Torokhov (13 comments: error variable naming, per-call kmalloc, redundant mutex,
  no hardcoded IRQ polarity, regulator cleanup on init failure, ...); Eric agreed to most and promised v2.
  https://lkml.iu.edu/hypermail/linux/kernel/2509.3/07078.html
- DT side, 2025-10: *[PATCH v2 3/6] arm64: dts: qcom: r0q: add touchscreen support* (Galaxy S22, SM8450).
  **Relevant risk:** on r0q the SPI bus was reported broken ("driver probes, but fails to recognize the
  touchscreen"), the patch used `spi-gpio` as a workaround, and Konrad Dybcio asked whether `gpi_dma1` and
  `qupv3_id_1` were enabled before the SPI node. The outcome is not visible in the archive pages I could read.
  https://lkml.iu.edu/2510.3/04249.html, https://lkml.iu.edu/2511.0/03894.html
- **Not found / unverified:** whether a later version (v2+) of the driver was merged or what its final
  binding looks like. Check lore.kernel.org / linux-next before porting. A separate series, *Input: support
  for STM FTS5* (I2C, Pixel 3, v6 2026-09), is unrelated to SPI.

### 2.2 Protocol (from the v1 RFC driver, https://lkml.iu.edu/2509.1/08062.html; Samsung's driver agrees on mode)

SPI mode 0, 8 bits. Supplies `vdd`, `avdd`; **no reset GPIO**, no firmware load; IRQ from DT.
Opcodes: `0x10` sense on, `0x11` sense off, `0x23` read panel info (11 bytes), `0x30` touch type,
`0x62` clear events, `0x87` read event, `0xC0` custom write prefix, `0xD1` custom read (+2-byte BE address),
`0xFA` / `0xFB` register write / read. Reads discard `1 + tx_len` leading bytes (2 for `0x87`, 4 for custom
reads). Power-up: enable supplies, wait 140 ms, write `FA 20 00 00 24 81` (undocumented soft reset), wait
30 ms, poll `0x87` up to 5 x 20 ms until byte0 bits 5:2 == 0x2 and byte1 == 0x0 ("ready"), then read panel
info. Events are 16 bytes: byte0 bits 7:6 action, 5:2 touch id; X = (b1 << 4) | (b3 >> 4);
Y = (b2 << 4) | (b3 & 0xF); byte7 bits 4:0 = further pending events. **There is no device-ID read.**
This comes from a review-stage RFC; confirm against Samsung's `stm_reg.h` / `stm_spi.c` when needed.

### 2.3 Wiring of this unit (Samsung downstream DT, `dm1q_eur_openx_w00_r13.dts`)

| Item | Samsung value | Mainline `sm8550.dtsi` / status |
|---|---|---|
| SE | `0xa90000`, SPI (protocol 1) | `spi4: spi@a90000`, pinctrl `qup_spi4_data_clk` + `qup_spi4_cs` |
| MISO / MOSI / CLK | `spi_miso/mosi/clk_tsp_*`: gpio44 / gpio45 / gpio46, `qup1_se4_l0/l1/l2`, drive 6, bias-disable | `qup_spi4_data_clk`: gpio44-46, `qup1_se4`, drive 6, bias-disable: **same pins** |
| CS | `sec,gpio_spi_cs` = GPIO47 | `qup_spi4_cs`: gpio47, `qup1_se4`, drive 6: **same pin** |
| IRQ | `sec,irq_gpio` = GPIO25 (`tsp_int_*`, drive 2, bias-disable) | same pin the Goodix node used |
| Speed / mode | `spi-max-frequency` 10 MHz; `SPI_MODE_0` | - |
| IO rail | `tsp_io_ldo` = `pm_humu_l12`; overlay fragment@40: 1,800,000 uV, boot-on | L12B (humu = PM8550B, docs/05); not defined in `dm1q.dts` yet |
| AVDD rail | `tsp_avdd_ldo` = `pm_humu_l16`; overlay fragment@43: 3,000,000 uV, boot-on | L16B; not defined in `dm1q.dts` yet |
| Firmware | `tsp_stm/fts2ba61y_dm1q_boe.bin`, `..._dm1q.bin` (not on the PC) | upstream RFC driver loads none |

Samsung's driver additionally drives GPIO47 as a plain output around every `spi_sync()` (`stm_spi.c`
`gpio_direction_output(gpio_spi_cs, 0/1)`). Inference (not tested): a hint that the chip wants CS framed
around whole transactions; mainline's GENI driver asserts CS per message, so a two-transfer sequence must be
sent as ONE `spi_message`.

### 2.4 Blockers found in the repo (evidence: decompiled `_scratch/pmos-v11-keys/sm8550-samsung-dm1q.dtb`)

1. `spi@a90000` is `disabled`; `i2c@a90000` (the Goodix reading) is `okay` on the same SE — only one can be on.
2. `dma-controller@a00000` (`gpi_dma1`, which `spi4`'s `dmas` point at) is **`disabled`**; `geniqup@ac0000` is okay.
   This is exactly Konrad's question on the r0q thread, and a plausible cause of an SPI that probes but is dead.
3. `regulators-0` (PM8550B) defines only ldo5 / ldo15 / ldo17: **L12B and L16B do not exist** as regulators.
4. No driver (2.1).

### 2.5 Plan

- **B1, DT-only (no kernel build, no module refresh):** canonical `dm1q.dts`: enable `&gpi_dma1`, replace
  `&i2c4`/Goodix by `&spi4` + `touchscreen@0 { compatible = "st,fts2ba61y" ... }` (unverified binding, as in
  the RFC), add `ldo12` 1.8 V and `ldo16` 3.0 V to `regulators-0`. Test image in `_scratch` only (rule 5):
  the same plus `compatible = "rohm,dh2228fv"` so `spidev` binds, and `regulator-always-on` on both rails
  (nothing consumes them until a driver exists, and the regulator core would switch them off). On the phone:
  load `spi-geni-qcom` / `spidev`, send the reset + `0x87` read as ONE message, expect the ready event.
  Pass = the SE answers and the chip reports ready; fail modes (all `0x00` / all `0xFF`, no `/dev/spidev*`,
  probe deferred) say which of rails / CS / GPI-DMA to look at next.
- **B1 prepared 2026-10-12** (details in 2.6).
- **B2:** port the upstream FTS2BA61Y driver (latest posted version) as a kernel patch -> r6 build (user's
  sudo) -> `scripts/refresh-phone-modules.sh` (rule 6). Try without a firmware blob first.
- Open: IRQ polarity / type for GPIO25 on this chip (RFC used level-low, then moved to DT); whether the
  panel variant (`_boe` firmware) matters.

### 2.6 B1 as prepared (2026-10-12) -- result in 2.7: PASS

Canonical `dts/dm1q/dm1q.dts` now: `&gpi_dma1` okay; `&i2c4` (Goodix) kept but `status = "disabled"`;
`&spi4` okay with `touchscreen@0 { compatible = "st,fts2ba61y"; spi-max-frequency = 10 MHz;
interrupts = <&tlmm 25 IRQ_TYPE_LEVEL_LOW>; vdd-supply = L12B; avdd-supply = L16B; pinctrl ts_int_default }`;
`ts_int_default` (gpio25, drive 2, bias-disable); `regulators-0` gained `ldo12` (`vreg_l12b_1p8`, 1.8 V) and
`ldo16` (`vreg_l16b_3p0`, 3.0 V). Goodix is not deleted: i2c4 and spi4 are the same engine, so "try both" means
one image with i2c4 on (already known: every earlier boot printed `Invalid proto 1`) and one with spi4 on.

Test image set `_scratch/pmos-v12-touch-spidev/` (boot + vendor_boot to flash; dtbo / init_boot unchanged),
built from `_scratch/dts-b1/dm1q-b1-spidev.dts` = the canonical DTS + three scratch-only overrides
(`touchscreen@0` compatible `rohm,dh2228fv` so spidev binds; `regulator-always-on` on both rails). Verified by
decompiling against the flashed v11 DTB (phandle lines stripped): `gpi_dma1` disabled -> okay, `i2c@a90000`
okay -> disabled, `spi@a90000` disabled -> okay + the touch node (`interrupts = <0x19 0x08>` = gpio25 LEVEL_LOW,
10 MHz), `ldo12` / `ldo16` with the right microvolts and `regulator-always-on`, `ts-int-default-state`;
nothing else semantic changed. Kernel and PCIe fix identical to r5.

Phone-side tooling (all new, PC-tested per rule 3):

- `scripts/spi-xfer.c` (+ `build-spi-xfer.sh`, `bin/spi-xfer-aarch64`): freestanding static helper, one SPI
  message per item through `/dev/spidevB.C`. `test-spi-xfer.sh`: 27 checks incl. struct size and ioctl numbers
  against the real kernel header; the real transfer can only be exercised on the phone.
- `scripts/phone-touch-spi-probe.sh`: loads `gpi`, `spi_geni_qcom`, `spidev`; reports the SPI device, deferred
  probes, rails, GPIOs, dmesg; runs read / reset / 5 polls at 1 MHz and 10 MHz and prints
  `RESULT hz=.. pre=.. polls=.. verdict=READY|ALLFF|ALLZERO|OTHER|SHORT|XFERERR|NODEV`.
  `test-phone-touch-spi-probe.sh`: fake `/sys`, `/dev`, helper; bash and `bash --posix` (no dash / busybox on the
  PC, so busybox ash is first exercised on the phone).
- `collect-phone-state.sh <label> --touch` pushes both and writes `touch.txt` next to the usual files.

Reading the verdict: READY = the chip answered the soft reset like the upstream driver expects (SE, CS, mode,
rails all work; go to B2). ALLFF / ALLZERO = MISO stuck: no power, wrong CS framing or mode, or the chip wants
something first. OTHER = it answers but is not "ready" (look at the raw bytes). NODEV = no `/dev/spidev*`:
read the deferred-probe list and dmesg (GPI DMA / SE / pinctrl). XFERERR = the ioctl failed (errno in the log).

### 2.7 B1 result, 2026-10-12: PASS -- the FTS2BA61Y answers over SPI on the mainline kernel

Evidence: `notes/2026-10-12-v12-touch/touch.txt` (v12-touch image, r5 kernel #6, `collect-phone-state.sh v12-touch
--touch`). The other files of that collection (dmesg, journal, WLAN probe) contain MACs / SSID and are NOT
committed.

- **Probe order shows the gpi_dma1 dependency:** `probe of a90000.spi with driver geni_spi returned 517`
  (EPROBE_DEFER) at 7.3587 s, right after `a00000.dma-controller` (gpi) probed; the retry succeeds at 7.454 s
  (`returned 0`), then `spi0.0` binds `spidev` and `/dev/spidev0.0` appears. With `gpi_dma1` disabled (the
  v11 DTB) the SPI controller could never have probed. No `Invalid proto` anywhere (i2c4 is off).
- **Rails:** `vreg_l12b_1p8` 1800 mV and `vreg_l16b_3p0` 3000 mV registered, enabled (use count 1, always-on from
  the scratch override).
- **The chip talks, at both 1 MHz and 10 MHz, mode 0, native CS, ONE message per step.** Read event (`87` + 17 zeros)
  returns `00 87 | 49 00 10 00 ...`: byte 1 echoes the opcode (the "1 + tx_len leading bytes" header of the RFC
  driver), the 16-byte record starts after it. `0x49` = status type 2 (bits 5:2), event id 1, byte1 = 0 -> the
  upstream driver's "ready" test passes. The soft reset `FA 20 00 00 24 81` came back as `00 fa 20 00 00 24`
  (the MISO line shifting the TX bytes one byte late: a live chip, not a floating line).
  - 1 MHz run: the record was already pending BEFORE the reset (`pre=READY`: the chip had come up with an unread
    ready event), the reset produced a fresh one on the first poll, polls 2-5 returned all zeros (queue empty).
  - 10 MHz run (second): pre-read all zeros (the 1 MHz run drained the queue), the reset again produced the same
    `49 00 10` record on the first poll.
  - Reading: `49 00 10 ...` is the chip's "controller ready" record (the `0x10` there matches the FTS family's
    controller-ready event code -- inference from the family, not from this chip's documentation).
- **Not yet seen:** panel info (`0x23`), touch events, the interrupt line (gpio25 is not requested by anything
  in this image, so `/sys/kernel/debug/gpio` has no line for it), firmware version. No firmware blob was loaded:
  the chip's own flash firmware runs.
- **Conclusion:** SE a90000 as SPI, its pins, CS framing, the two rails and `gpi_dma1` are all correct. The
  remaining work is purely a driver (B2) plus the interrupt wiring.
- **Goodix alternative:** not tested again. With `i2c4` enabled every earlier boot logged `Invalid proto 1`
  (docs/05); and the SPI answer above means the SPI part is the one that is physically there.

### 2.8 B2 prepared (2026-10-12): the driver as a kernel patch, package r6 -- result in 2.9: PASS

**What is in the repo** (all untested on hardware):

- `kernel/patches/0002-Input-add-ST-FTS2BA61Y-SPI-touchscreen-driver.patch` (identical copy in the pmaports package as
  `add-fts2ba61y-touchscreen.patch`): `drivers/input/touchscreen/fts2ba61y.c`, its Kconfig/Makefile entries and the
  binding `st,fts2ba61y.yaml`. Port of the RFC of 2025-09-11 (`_scratch/fts2ba61y-upstream/`, not committed). A search
  on 2026-10-12 found no v2 of the driver and no merge (only the RFC and the v1 review); that is a search result, not
  proof -- re-check before any upstream submission.
- Package r6: `APKBUILD` (pkgrel 6, kernel reports `#7-samsung-dm1q-mainline`, new patch in `source`, sums updated with
  plain `sha512sum`), `config-dm1q.fragment` (`CONFIG_INPUT_TOUCHSCREEN=y`, `CONFIG_TOUCHSCREEN_FTS2BA61Y=m`),
  and `sm8550-samsung-dm1q.dts` re-synced from `dts/dm1q/dm1q.dts` (the pmaports copy was stale: it lacked the keys of
  v11 and the touch nodes of v12). `pmbootstrap apkbuild_parse` parses it. `pmbootstrap checksum` needs sudo
  (chroot), so the sums are not yet confirmed by it.

**Differences from the RFC** (each is a change to the posted code; the ones marked V are checked against Samsung's
`stm_spi` driver in `_scratch/samsung-stm-spi/`, the rest follow the v1 review and normal kernel practice):

- V: the touch-type low bits are event byte 7 bits 7:6 (`ttype_1_0:2` after `left_event:5` and `max_energy:1` in
  `struct stm_ts_event_coordinate`). The RFC masked bits 1:0 -- the "events left" counter -- which would drop any touch
  reported while more events were queued.
- V: the slot count is the vendor's `SEC_TS_SUPPORT_TOUCH_COUNT` = 10 (`sec_input.h:361`), ids above are ignored. The
  RFC used the TX channel count (`data[8]` of the panel info is a channel count, not a contact limit).
- V: panel info of all zeroes / all ones -> `-ENODEV` (vendor `stm_ts_get_channel_info`). The device-id read (`0x22`,
  5 bytes) is logged too; both go through `C0 <cmd>` then `D1 00 00` with 4 reply bytes dropped (vendor `stm_ts_spi_read`).
- V: `0x87` event read, 16-byte records, level-low interrupt (vendor `IRQF_TRIGGER_LOW`); here the trigger comes from the
  DT (`IRQ_TYPE_LEVEL_LOW`, already in `dm1q.dts`).
- No per-call `kmalloc`: two DMA-aligned bounce buffers in the driver data; one mutex guards them (shared buffers, so it
  is not redundant). Regulators are released when probe fails after enabling them. The interrupt is requested last
  (the RFC called `disable_irq()` on a line it had not requested). One `input_sync()` per interrupt. Palm is reported as
  `MT_TOOL_PALM`. An SPI error in the handler returns `IRQ_NONE` (the spurious-IRQ guard stops a dead bus from spinning
  a level interrupt forever).
- Binding: example uses this board's values, `spi-peripheral-props` added; maintainers is a placeholder
  (`dm1q-mainline@example.com`) because the archive hides the authors' addresses -- replace before upstreaming.

**Checks done on the PC** (kernel 7.3-rc3 tree, config of the earlier build + `TOUCHSCREEN_FTS2BA61Y=m`): `fts2ba61y.o`
compiles with clang `W=1` without a warning; `checkpatch --strict` clean (driver and binding); the patch passes
`git apply --check` / `patch --dry-run` on the tree with the sec-log patch applied. **Not done:** `dt_binding_check`
(no `dtschema` here), a full module link, and anything on the phone.

**Known unknowns the first boot will answer** (all would show in dmesg as `fts2ba61y spi0.0: ...`):

1. The dm1q-specific protocol assumptions are the RFC's (written for the S22 series): no reset GPIO, no firmware
   upload, `0x30` touch-type value `0x0061`, `0x10` sense-on at `open()`. B1 proved reset + ready; nothing past that.
2. The panel resolution the chip reports vs the display (1080x2340 expected): the driver logs
   `id <5 bytes>, resolution WxH, N TX x M RX`. If it differs from the display, `touchscreen-size-x/y` goes into the DT.
3. Whether the interrupt (gpio25, level low, `ts_int_default` pinctrl) fires.

**Steps** (the user runs these; sudo needed only for the first):

1. `pmbootstrap checksum linux-samsung-dm1q-mainline && pmbootstrap build linux-samsung-dm1q-mainline` (the build log
   must show `add-fts2ba61y-touchscreen.patch: OK` next to the two older patches; `git diff` of the APKBUILD after the
   checksum step should be empty).
2. `bash scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --out ../_scratch/pmos-v13-touch-driver --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r6.apk --new-kernel`
   (canonical DTS: `compatible = "st,fts2ba61y"`, no `regulator-always-on` -- the driver holds the rails).
3. Flash `boot` + `vendor_boot` from TWRP (`scripts/flash-recovery.sh`), boot, then **before** anything else
   `bash scripts/refresh-phone-modules.sh --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r6.apk --reboot`
   (rule 6: the kernel code changed; the placeholder form `<the r6 apk>` pasted literally makes the shell redirect
   into a file named `--reboot` in the repo root -- that is where the stray empty `--reboot` file came from).
4. On the phone: `sudo dmesg | grep -i -E 'fts2ba61y|spi0'`, `cat /proc/bus/input/devices` (a `STMicroelectronics
   FTS2BA61Y Touchscreen` entry), `grep -i -E 'fts|geni' /proc/interrupts`, then touch the screen while
   `sudo cat /dev/input/eventN | hexdump -C` runs (N from the devices list; touch events are `type 3` abs codes
   `0x35/0x36` = X/Y, `0x39` = tracking id, evdev records are 24 bytes).

### 2.9 B2 result, 2026-10-13: PASS -- touch works on the mainline kernel (r6 + canonical DTS)

Evidence: `notes/2026-10-13-v13-touch-driver/touch-driver.txt` (pasted by the user; the decode of the raw evdev dump is
mine). Built and flashed by the user following the steps of 2.8 (r6 kernel, canonical DTB, module tree refreshed); the
paste does not show `uname -a`, the image-set name or the refresh output; that the r6 kernel and its module tree
are what ran is inferred from `fts2ba61y` loading as a module and probing.

- **Probe:** `fts2ba61y spi0.0: id 53 54 40 36 01, resolution 4095x4095, 16 TX x 34 RX channels`, then
  `input: STMicroelectronics FTS2BA61Y Touchscreen ... input3` and `probe of spi0.0 ... returned 0 after 182868 usecs`
  (140 ms supply wait + 30 ms reset wait + reads). The canonical DTS has no `regulator-always-on` on the two rails; the
  driver enables them itself (`regulator_summary` was not collected this time, so the rails' state is not shown).
- **Input device:** `/proc/bus/input/devices` lists it on `event3` (Bus 0x1c = SPI), `PROP=2` (direct), `BTN_TOUCH` and the
  multitouch ABS set.
- **Interrupt:** `178: 205 ... msmgpio 25 Level fts2ba61y` -- gpio25 as a level interrupt (the DT's `IRQ_TYPE_LEVEL_LOW`)
  fired 205 times by the time of the capture.
- **Events** (one touch, decoded): `BTN_TOUCH 1` + tracking id 3 + `MT_X 2040` / `MT_Y 1991` + major 15 / minor 8 +
  pressure 17, then moves (x 2039, 2036 / y 1992, 1994), reports ~8 ms apart, then `tracking id -1` + `BTN_TOUCH 0`: press,
  move and release all work through the driver's slot handling. The ~8 ms spacing is ~120 Hz; Samsung's DT has
  `sync-reportrate-120` (the match is an inference, nothing else was measured).
- **Coordinate space:** the chip reports 4095x4095, and Samsung's DT says `sec,max_coords = <0x1000 0x1000>`
  (`dm1q_eur_openx_w00_r13.dts`, touchscreen@0 of `fragment@68`): a normalized 4096x4096 space, not the 1080x2340 of the
  display. The input device advertises 0..4095 on both axes and a compositor / libinput scales that to the output, so
  the DT needs no `touchscreen-size-x/y`. Not yet checked: axis orientation and inversion (the single touch above sits near
  the middle of the range; where the finger was is not recorded).
- **Chip id bytes** `53 54 40 36 01` are `'S' 'T'` and a 24-bit id `0x403601` (the vendor driver builds `chip_id` from
  bytes 2..4); what that id maps to was not looked up.
- **Not yet verified:** the four corners / orientation, two or more fingers, palm rejection, the pressure range, sensing off
  at `close()`, suspend / resume (no display driver yet, so nothing turns the panel off), the `_boe` panel variant (the
  chip runs the firmware in its own flash; none was loaded), behaviour over hours. The Goodix-on-I2C variant is not tested
  and cannot be on this unit: the SE is SPI and every earlier boot with `i2c4` on logged `Invalid proto 1` (2.7).
- **Next:** multi-touch (two fingers), then the open items above. The corner test is done, see 2.10.

### 2.10 Corner test and one boot where touch did not work (2026-10-13)

Evidence: `notes/2026-10-13-v13-touch-driver/corners-and-failed-boot.txt`.

- **Orientation: no DT flags needed.** Touching top-left, top-right, bottom-right, bottom-left in turn gave
  (333,27), (3887,133), (3864,3999), (32,3919): X grows to the right, Y grows downward, both over the full 0..4095
  range. No `touchscreen-swapped-x-y` / `-inverted-x/y` required. (Corner order is the user's; the decode agrees with it.)
- **An intermittent failure, not explained.** After the first reboot following the first `refresh-phone-modules.sh`
  run touch worked; after a later reboot the input device existed but a touch produced nothing. In that boot dmesg was
  identical to the working one (probe OK, same id/resolution line, no errors) and `/proc/interrupts` showed
  `fts2ba61y` at 2 and unchanged over a 10 s touch with `cat /dev/input/event3` holding the device open (the driver
  sends SENSE_ON on open): the chip did not raise gpio25. The user then re-ran the same `refresh-phone-modules.sh ... r6.apk
  --reboot` and touch has worked after every reboot since. Whether that re-run or just a different reboot fixed it is
  unknown -- one data point, no controlled test.
- **Candidate cause, untested:** the chip keeps state across a warm reboot that the driver's soft reset does not
  restore. Samsung's driver does more after the reset than the RFC driver: touch-function write, `C0 13` force
  calibration and `C0 62` clear-events (each waiting for an echo event), then `A0 00 01` (scan mode MS+SS, echo-checked),
  and only then SENSE_ON (`stm_core.c` `stm_ts_hw_init` / `stm_ts_start_device`, `stm_fn.c` `stm_ts_set_scanmode`). Our
  driver never sets the scan mode. This is a reading of the vendor source, not something observed on the chip.
- **If it recurs:** capture, in the bad state, `grep fts /proc/interrupts` before and after a touch with `cat
  /dev/input/event3` running, plus `sudo dmesg | tail -n 60`; then add the vendor init sequence (and a raw-transfer
  debugfs file so the chip can be poked without a kernel rebuild) as package r7. Not done speculatively: nothing
  proves the sequence is the cause, and every kernel change costs a rebuild and a module refresh.

### 2.11 It happens again: touch works for a while, then stops (2026-10-19/20, reported by Baraa)

- Baraa reports that touch works for a while and then stops responding while the keys keep working. He saw it on the tty with the on-screen keyboard (buffyboard) **before the GPU work** and again in Plasma Mobile
  (2026-10-19 ~21:05). So it is not caused by the GPU, Plasma, kwin or the lock screen alone; it fits the unexplained failure of 2.10 (and the unverified items of 2.9: `close()`, suspend/resume, long runs).
- What the Plasma run's logs show (`notes/2026-10-19-gpu-plasma2/`, uncommitted): no kernel error of any kind in the window (no `nobody cared`, no SPI/geni error, no hangcheck, no SMMU fault); kwin held `event0..3` open; `gpio25` reads `in high` in the capture taken
  after Plasma stopped (not conclusive: device closed); the panel was power-cycled three times (`panel id 81 02 25` at +67, +88, +110 s); the screen locker started mid-session. The moment and the trigger are not known.
- Hypotheses H1 to H6 (chip stops scanning / interrupt asserted but unserviced / count rises but evdev silent / userspace ignores / coupled to the panel power cycle / SPI or regulator state) and the plan (read-only `phone-touch-watch.sh`, recovery
  experiments, only then the driver update with Samsung's init sequence) are in `notes/2026-10-20-handoff-touch.md` sections 3 and 4. Status: handed to a fresh chat, nothing measured yet (Step A, the code comparison, is 2.12).

### 2.12 Step A (PC only, 2026-10-20): what our driver lacks compared with Samsung's `stm_spi`

Sources, all read in full for the paths named: our `fts2ba61y.c` (kernel patch 0002) and `../_scratch/samsung-stm-spi/stm_spi/` (`stm_core.c`, `stm_fn.c`, `stm_reg.h`). Everything in the table is FACT (read in the files); the
readings below the table are INFERENCE. Not read yet: `stm_ts_systemreset`, `stm_ts_wait_for_echo_event`, `stm_ts_set_spi_mode`, `sec_input_handler_start`, `stm_ts_external_func`, and the display notifier (it lives in the
sec_input core, which is not in `stm_spi/`).

| Area | Samsung `stm_spi` | Ours |
|---|---|---|
| Event dispatch | `stm_ts_irq_thread` (core:2054): id = byte0 & 3; status, coordinate, gesture and vendor events each have a branch; unknown events are logged | `fts2ba61y_handle_event` returns unless id == coordinate: every status or vendor event is read from the FIFO and dropped, **no log line** |
| Error status (stype 1) | id 0x01 "IC Event Queue is full" -> release all fingers; id 0x02 "ESD detected" -> `reset_work` (core:1775-1795) | ignored |
| IC reset notice (stype 2, id 0x00, data 0x10) | logged "IC Reset" -> `reset_work` (core:1796-1805). This is the same record `49 00 10` that our soft reset produces at probe (2.7) | ignored |
| Vendor events `F3 02` / `F3 46` | `reset_work` (core:2121-2128) | ignored |
| `reset_work` (fn:914) | `stop_device` (disable irq, release fingers, **rails off**, pinctrl off), 35 ms, `start_device` (pinctrl on, **rails on**, 35 ms, `reinit`, chip id, SENSE_ON, enable irq) | none |
| Init sequence (`hw_init`, core:2458; `reinit`, core:1535) | system reset, chip id, channel info, touch-function `C0 30`, force calibration `C0 13` (echo-checked), clear events `C0 62` (echo-checked), **scan mode `A0 00 <mode>` (echo-checked)**; `reinit` repeats system reset, clear events, feature setup and scan mode on every start | soft reset, ready wait, id and panel info, `C0 30` (0x61). **No calibration, no clear-events, no scan mode** |
| `input_open` (core:2161) | `start_device`: rails on, reset + init, SENSE_ON, enable irq | SENSE_ON only |
| `input_close` (core:2323) | `stop_device` (core:2387): disable irq, release all fingers, **rails off** (or a low-power mode) | SENSE_OFF only; rails stay on; slots are not released |
| Suspend / resume / panel power | the handlers read here are open and close; in the vendor tree screen on/off reaches the driver through them (INFERENCE: the notifier itself was not read) | no `pm_ops`, no panel hook |
| Empty FIFO (byte0 == 0, `get_event` core:1840) | logs "event buffer is empty", returns an error, `IRQ_HANDLED` | `get_events` returns 0, `IRQ_HANDLED`, **no log**: a level-low line stuck asserted with an empty FIFO would loop silently |
| SPI read error | `IRQ_HANDLED` | `IRQ_NONE` (the core would print `nobody cared` and disable the irq after 99,900 of 100,000 unhandled; no such line was seen) |
| FIFO overflow (`left` >= 31) | clear events + release all fingers | clear events, no release, `IRQ_NONE` |
| Slot bookkeeping | `release_all_finger` on queue-full, overflow, start and stop | `INPUT_MT_DIRECT` without `DROP_UNUSED` and no release-all path: a lost release event leaves a contact active |

Readings (INFERENCE):

- The failure signature so far (silent, no kernel line, keys unaffected, the first occurrence with gpio25 never asserting although sensing was on) is what the code predicts if **the chip leaves scanning by itself**
  (IC reset or ESD error) and the driver cannot notice: the event that says so is read and thrown away, nothing is logged, SENSE_ON is not re-sent. Samsung's driver contains a full power-cycle recovery for exactly these
  two events, which says the chip does this in the field. This is H1.
- A plausible trigger is the panel power cycle (H5): the panel driver is powered down and up under the console blank timer or DPMS, and the chip is never told. The tty case before the GPU work would fit a console blank
  after the default 600 s; that timer value was not checked on the phone.
- Our driver cannot show which of H1/H2/H3 it is, because it logs nothing about non-coordinate events. The decisive observation without a rebuild is the SPI traffic itself: the kernel has the `spi:spi_transfer_stop`
  tracepoint, whose output prints the first 64 bytes of tx and rx of every transfer, so the last `0x87` event reads before the chip goes quiet would show the status record. The PC-side kernel build config
  (`out-real/.config`, which predates the touch fragment) has `TRACEPOINTS`, `EVENT_TRACING`, `FTRACE` and `DEBUG_FS` set, and `include/trace/events/spi.h` of the 7.3-rc3 tree has the tx/rx dump; whether the phone's
  running kernel exposes `/sys/kernel/tracing/events/spi` is NOT verified and the first script checks it.
- Fix direction (D, only after a measurement names the cause): log and act on status events (queue full, ESD, IC reset), a recovery work item that power-cycles the rails and re-initialises, Samsung's init including scan mode,
  rails off at close or at panel-off with a full re-init at open, release-all on error paths, `IRQ_HANDLED` with a log on an empty FIFO.

### 2.13 Regression after the boot setup (2026-10-21, reported by Baraa) and the touch watcher (Step B)

FACT (Baraa, 2026-10-21 06:01, nothing captured yet): after the GPU firmware moved into the default firmware path and `plasma-mobile.service` was enabled at boot (docs/11 9.12), touch "no longer works at all ... it
crashes as soon as plasma launches". Before, touch worked for a while and then stopped (2.10, 2.11); now it is dead from the start of the autostarted session. The power key (sleep / wake of the desktop) works.

What changed between the two behaviours (FACT, from the 9.12 captures): (a) the GPU firmware is loaded during boot: `load_gpu` runs at ~7.66 s, the touch driver probes at 7.74-7.79 s in every boot, so the two overlap
(INFERENCE: this could matter for timing, nothing shows it does); (b) the UI now starts a few seconds after boot instead of minutes later by hand, so KWin opens the touch evdev node close to the probe; (c) the first
manual Plasma start ran for 240 s with touch working at first. No kernel error line has been seen in any of these.

Candidates (INFERENCE, to be separated by the measurement, not ranked on the evidence we have): chip state after a warm reboot (2.10 had one boot where gpio25 never asserted), the first `input_open` right after probe
(SENSE_ON only, no reinit, 2.12), the panel power cycle at session start (H5), a pure userspace failure (H4: the device delivers, the compositor does not use it).

**The instrument: `scripts/phone-touch-watch.sh`** (POSIX sh, root, read-only except the tracefs controls of one event, restored at exit; PC-side test `scripts/test-phone-touch-watch.sh`, 70 checks, plus `shellcheck -s sh`).
Collector flags: `--touch-watch[=SECONDS]` (default 45), `--touch-sleepwake[=SECONDS]` (default 20; implies the watch), `--touch-recover` (implies the watch). Baraa drags a finger continuously during every window.

| Phase | What it records |
|---|---|
| `touch` | a background reader holds the evdev node open; once a second: fts2ba61y interrupt count (and delta), gpio25 level, evdev events (count and delta, 24-byte records), seconds since anything changed, runtime-PM state of spi0.0 and of the serial engine, L12B / L16B state, DSI-1 enabled/dpms, backlight bl_power/brightness; at the end a verdict, the new kernel lines, the last `spi:spi_transfer_stop` records of spi0.0 with raw tx / rx |
| `sleepwake` | the same, while Baraa presses the power key (screen off), waits 5 s, presses it again |
| `rebind`, `modreload` | only with `--touch-recover` and only if the first window had no events: unbind / bind of spi0.0 (the driver's remove / probe switch L12B and L16B off and on: a real power cycle of the chip), then `modprobe -r` / `modprobe fts2ba61y`; each is followed by a 15 s window; it stops at the first one that brings events back; the device is always left bound |

How the verdicts will be read (this is the plan, the readings are INFERENCE until a run exists):

| Verdict | Where the chain breaks | Next step |
|---|---|---|
| `EVENTS-FLOW` while the UI is dead | not in the kernel: the chip, the interrupt and evdev work (H4) | a userspace probe: which process holds the node, KWin / libinput device list and journal |
| `IRQ-COUNTS-NO-EVDEV` | the driver consumes interrupts but reports nothing (H3: slot logic, event decoding) | read the SPI trace records against `fts2ba61y_handle_event` |
| `IRQ-LINE-LOW-NOT-SERVICED` | gpio25 asserted, thread not running or masked (H2) | `/proc/irq/<n>`, the irq thread's state |
| `CHIP-SILENT`, recovered by `rebind` | the chip left scanning or lost its state and a rail power cycle brings it back (H1, H5) | driver fix direction D of 2.12, using the status record seen in the SPI trace |
| `CHIP-SILENT`, nothing recovers it | below the driver: SPI controller / pinctrl / rails (H6) | rails and `spi_geni_qcom` state, a raw transfer through debugfs |
| `NO-DEVICE` | probe failed this boot | the probe's dmesg lines (boot race with GPU init or the regulators) |

Not verified: whether the phone's kernel has `/sys/kernel/tracing/events/spi` (the script says "skipped" and carries on without the SPI records if not), and whether the evdev reader changes the chip's behaviour (it only opens the node, as KWin does).

### 2.14 First touch-watch result (2026-10-21, boot at uptime 890 s) and the flight recorder

Raw capture: `notes/2026-10-21-touch-watch/touch-watch.txt` (uncommitted, like all raw captures). Baraa dragged a finger in every window. State at the start: `plasma-mobile.service` active, the evdev node held by
`kwin_wayland`, `systemd` and `systemd-logind`, the fts2ba61y interrupt count already **11464**.

FACTS (read from the capture):

| Window | What was measured |
|---|---|
| `touch`, 45 s | interrupt count constant (11464), gpio25 high in all 45 samples, 0 evdev bytes, rails L12B 1.8 V / L16B 3.0 V enabled with 1 user, DSI-1 enabled/On, backlight bl_power 0 / 2047, the SPI controller (a90000.spi) runtime-suspended, the SPI device itself reports `unsupported` runtime PM. 0 new kernel lines. The SPI trace buffer held 0 records of spi0.0 (the driver reads the chip only after an interrupt). Verdict CHIP-SILENT. |
| `sleepwake`, 20 s | the power key switched DSI-1 to disabled/Off with bl_power 4 for ~7 s, then back to enabled/On; one new kernel line (the panel driver read the panel id `81 02 25` again at re-enable); touch stayed silent. |
| `rebind` | unbind: L12B and L16B disabled (users 0); bind: both enabled again; probe took 188 ms and printed `id 53 54 40 36 01, resolution 4095x4095, 16 TX x 34 RX channels`. In the next 15 s: +1706 interrupts (~114 per second), 11811 evdev records, gpio25 never sampled low. The SPI trace showed one 18-byte read (2 header bytes + one 16-byte event, id 0) every ~8.3 ms, i.e. 120 Hz coordinate reports. |
| kernel log | no line about the touch chip between the failure and the capture, no `nobody cared`, no SPI error. |

Readings (INFERENCE, labelled as such):

- The chip, not the interrupt line, the SPI controller or the panel path holds the failed state: gpio25 stayed high (the chip did not assert it, so H2 "asserted but not serviced" is out for this occurrence), no interrupts arrived
  (so H3 "driver swallows them" and H4 "userspace ignores the device" are out for this occurrence), the rails were on (H6 for the rails). The rebind only touches the chip's rails and a freshly allocated driver state; the
  SPI controller and its pinctrl are not reset by it, so they work. A full power cycle plus soft reset plus re-init revives the chip at once: this is the H1 class (the chip stops reporting by itself).
- A panel power cycle does not revive it (`sleepwake` window), so the panel path is not a recovery. It is not excluded as a trigger: the chip was already silent before that window.
- The interrupt count of 11464 at the start of the first window means the chip had raised interrupts earlier in this boot (at ~114-123 per second of dragging that is on the order of 100 s of use; the status records the driver drops
  would also count, so this is an order of magnitude, not a measurement). That fits "works for a while, then stops" (2.10, 2.11) better than "dead from the start of Plasma" (2.13); the two statements are not reconciled and the
  recorder below will settle it with timestamps.
- Nothing recorded what the chip said last: the trace was started after the failure. Hence the recorder.

**The recorder: `scripts/phone-touch-trace.sh`** (collector flag `--touch-trace=arm|dump|disarm`; PC-side test `scripts/test-phone-touch-trace.sh`, 66 checks). `arm` starts a dedicated trace instance
(`/sys/kernel/tracing/instances/dm1q-touch`, 4 MB per CPU, overwrite mode) for `spi:spi_transfer_stop` of bus 0 / cs 0; once the chip goes quiet nothing new is written, so the buffer keeps the final ~minute of its traffic
(at ~120 records per second and ~250 bytes per record). It lives in RAM until the next reboot (arm after every boot). `arm` also runs a 6 s alive check and, if touch is dead at that moment, revives it with the rebind so that the
*next* failure is the recorded one. `dump` is read-only and prints: the buffer statistics, the age of the last record against the boot clock, the event-id counts, every non-coordinate record (id 1 = status, with its stype and the
raw bytes), the last 20 records, the records per second in the last 10 s before the end, the largest gap.

How a dump will be read (plan; INFERENCE until a dump exists):

| What the dump shows | Reading | Fix direction |
|---|---|---|
| a status record `id=1 stype=2` with `49 00 10` just before the end | the chip reset itself (the IC-reset notice of 2.12) and our driver dropped it and never re-sent SENSE_ON | handle status events: log, full re-init (Samsung's `reset_work`) |
| a status record `stype=1` (error: ESD, queue full) | the chip reported a fault | same, plus power cycle |
| coordinate records at full rate, then nothing, no status record | the chip stopped without telling | a watchdog is the only driver-side answer (touch seen, then no interrupt for N s while the screen is on is not distinguishable from an idle screen: needs another signal) or chip configuration (scan mode `A0 00 01` never set, 2.12) |
| the rate decays before the end, or the records change shape | degradation (supply, scan mode switching to a low-power rate) | scan mode / rail investigation |
| the age of the last record far below the uptime gap | tells when it died (compare with the wall clock Baraa noted) | correlate with panel on/off, GPU load, suspend |

### 2.15 Slow wake from the power key after a long sleep (2026-10-21, reported by Baraa)

FACT (Baraa, no capture yet): after the phone has "deep slept" for about 30 minutes (he is not sure of the duration), one press of the power key takes 20-30 s to wake it. Short screen-off / screen-on cycles (the 5 s test of 2.14)
are immediate: DSI-1 was back On within a second.

Not known (do not assume): whether the system ever suspended (docs/08 section 1.5: wakeup from suspend was never tested, "no suspend path yet"), what the PowerDevil / logind idle action is, which device resumes slowly, and whether this
started with the GPU firmware at boot / Plasma autostart (9.12) or was always there. `dmesg` of the 2026-10-21 08:41 capture has no `PM:` suspend line (it ends before the long sleep).

Candidate readings (INFERENCE, to be separated by the probe): (a) a real suspend-to-idle with a slow device resume or a timeout (the log shows `PM: suspend entry` / `exit` and per-device errors, `-110`); (b) no system suspend, only
the screen off + CPU idle, and a slow display / GPU runtime-resume or compositor path; (c) the key press does not wake the SoC by itself and something else (a timer, Wi-Fi) wakes it 20-30 s later.

**The probe: `scripts/phone-sleep-probe.sh`** (collector flag `--sleep-probe`; PC-side test `scripts/test-phone-sleep-probe.sh`, 52 checks; READ-ONLY, writes not even a temp file). Sections: power configuration (`/sys/power/*`,
`suspend_stats`), cpuidle states, wakeup sources by total time, input devices and their wake setting, the kernel-log timeline (suspend entries / exits counted, `PM:`, timeouts, `-110`, GPU / display lines, the last 60 lines),
runtime PM of the display / GPU / storage / SPI / PCIe devices, this boot's journal lines about suspend / power key / idle / powerdevil, the logind / sleep / PowerDevil / screen-locker configuration, RTC and battery, current
state. It must run after a slow wake and before a reboot.

### 2.16 The phone is hot and laggy with very high CPU since the autostart (2026-10-21 / 22, reported by Baraa)

FACTS (Baraa's reports, no capture yet): (1) when it lags, `top` shows a very high CPU usage (no numbers or process names given); (2) by 2026-10-22 01:50 the phone is "in an unusable state" since the GPU firmware and
Plasma were made automatic at boot (9.12), and it "heats up so badly" that he reads it as extremely high CPU use. The earlier manual Plasma runs lasted 240 s each (docs/10 9), so a long-running session was never observed before.

Not known (do not assume): which process burns the CPU, whether it is a CPU renderer (llvmpipe) at the panel's refresh rate, a crash / respawn loop of `plasma-mobile.service` (its drop-in allows 4 starts per 180 s, 9.12), a
lock-screen greeter that cannot authenticate (the known PAM problem), an interrupt storm (the touch line is level-low), or a GPU hang-recovery loop now that the GPU initialises at boot. Whether the high CPU use and the touch
drop-out (2.14) are related is open: the touch failure has a different signature (no interrupts at all, gpio25 high), so a starved irq thread does not explain it.

**The probe: `scripts/phone-load-probe.sh`** (collector flag `--load-probe`; PC-side test `scripts/test-phone-load-probe.sh`, 47 checks; READ-ONLY, writes not even a temp file, never opens a `/dev/dri` node). It must run WHILE
the phone is hot: loadavg and pressure, per-CPU busy / user / system / irq / softirq / iowait over 3 s, the 10 interrupts with the highest rate, top (processes, then threads; the second frame only), `plasma-mobile.service`
state with `NRestarts` and its last journal lines, stored core dumps, which processes hold a `/dev/dri` node (a compositor on the GPU holds `renderD128`), devfreq GPU frequency, renderer / crash lines of the journal, stall /
throttling / GPU-hang lines of the kernel log, cpufreq and the hottest thermal zones.

Safety: the rollback of the autostart is `--boot-setup=undo-plasma` (reversible with `--boot-setup=plasma`); it disables the unit for the next boot and does not stop the running session, so the running phone stays hot until it is
rebooted. The GPU firmware at boot stays (it is a separate step, `--boot-setup=undo-gpu-fw`).

**Result (2026-10-22, `notes/2026-10-22-hot-cpu/`, FACT unless marked):** boot uptime 441 s, plasma-mobile.service active. Load average 9.71 / 6.57 / 3.09; all CPUs ~89 % busy; the time is `llvmpipe` threads (8 each) of
`kwin_wayland` (~50 %) and the Angelfish browser (~31 %); temperatures 84 to 90 C; GPU devfreq `cur=0`; Mesa client errors (zink incompatible driver, dri2 screen failure). In that boot the GPU firmware was NOT found
(`a740_sqe.fw` `error -2` at 8.05 s, `error -40` later; docs/11 9.13), so the GPU never initialised and Plasma rendered on the CPU. After `--gpu-powerup=full` (the GPU initialises, no zap error) Baraa reports the lag is gone
(2026-10-22 11:52). So the hot / laggy state is the llvmpipe fallback, not a GPU hang and not the zap (INFERENCE for the causal step, FACT for the correlation). It is also the likely reason for the lag Baraa saw earlier: every boot
after 2026-10-20 21:16 captured so far lacks the firmware at boot (docs/11 9.13).

**Slow wake (2.15), what the 2026-10-22 sleep probe shows (same capture):** `suspend_stats success = 0`, 0 suspend entries and exits in the kernel log, `mem_sleep` is `s2idle [deep]`, `gpio-keys` and `pmic_pwrkey` have wake enabled; the `systemd` sleep units never ran;
the journal has one `Power key pressed short` and no sleep, suspend or idle-action line. The boot was only ~7 min old, so it holds no slow wake. FACT: this phone has not suspended in that boot; INFERENCE: the 20 to 30 s wake is then not a suspend
resume but the screen-off path (display, GPU and compositor on a saturated CPU, or PowerDevil): the probed boot had all cores busy from software rendering, so the slow wake may share that cause. Not tested: it needs a slow wake reproduced in a boot WITH the GPU,
then `--sleep-probe` before any reboot. Also seen: the clock starts at 1970 (RTC `1970-01-01 14:53`) and jumps when `systemd-timesyncd` syncs (journal timestamps of the early boot are unreliable), PowerDevil retries i2c for ddcutil (`EACCES`, 100 ms doubling to 800 ms, ~3 s at startup), `kscreenlocker_greet: Worker not ready yet, cannot authenticate` (the known PAM problem).
