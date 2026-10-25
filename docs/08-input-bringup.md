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

### 2.17 Possible fix: evdev failed its BTF check at boot (2026-10-22, PC-side review of the reboot capture)

FACT (`notes/2026-10-22-plasma-boot/dmesg.txt`, uptime 3 s): `failed to validate module [evdev] BTF: -22`, followed by `evdev: module verification failed: signature and/or required key missing - tainting kernel`. The kernel is tainted from that point (the taint alone does not explain the touch failure).

FACT (`notes/2026-10-22-plasma-boot/probe.txt`, `gpu.txt`, `session.log`): the "Modules linked in" list of the display-clock WARNING (`disp_cc_mdss_mdp_clk_src`, at about 7 s) includes `evdev`, so the module was loaded despite the BTF line (audit 2.20: the earlier wording "module list printed in the kernel log" hid that this list belongs to an unrelated warning). The captures do not contain `/proc/bus/input/devices`, `lsmod`, or the touch device list, so whether the input devices are present and bound in this boot is not yet verified.

Background: the header of `scripts/refresh-phone-modules.sh` records (citing docs/07 section 15.12) that modules refused by BTF validation once left PCIe, the PHY and wlan0 missing. The script rebuilds the module tree from a kernel APK: `--apk FILE --reboot`. The 2026-10-11 rule that an earlier draft of this section cited does not exist in the docs; it was removed (see 2.18).

INFERENCE (not checked): the evdev BTF failure is a module-tree mismatch. If evdev is loaded from a stale tree, event delivery could be affected, and a dead touch could look like a chip fault. This is a candidate for the touch problem, not a confirmed cause.

Plan (step 1 was run on 2026-10-23, see 2.18; steps 2 and 3 were not):
1. Read-only input check, run in the same boot as the reboot test: `/proc/bus/input/devices`, `lsmod | grep evdev`, `/sys/module/evdev` presence, and the BTF/taint lines of `dmesg`. Expected healthy result: the FTS2BA61Y touch device and the three key devices listed, bound to evdev.
2. If evdev is missing or the touch device is absent, run `refresh-phone-modules.sh --apk <kernel apk> --reboot` and repeat the check.
3. Only then re-run the touch trace (`--touch-trace=arm`) so the recorder is not tested against a broken input stack.

Status: step 1 done. evdev is loaded and the four input devices are bound (FACT, 2026-10-23 `input-check-boot`), so the BTF line is not the cause of a missing device. The BTF check is not proven harmless for evdev: it stays a candidate until the module tree is refreshed and a dead-touch window is measured (2.18).

### 2.18 Re-analysis of the touch captures (2026-10-23): what is measured, what is not

This section replaces the working reading of 2.14-2.17 for the 2026-10-23 captures. FACT means read from a capture named here; INFERENCE means reasoned and not yet measured. Audited the same day: the corrections are listed in 2.20 and the corrected passages below are marked (audit).

**Boot timeline (FACT).** `input-check-boot` ran at 05:10:01 with uptime 20024.7 s. `touch-dead-snapshot` ran at 05:17:02 with uptime 375.4 s. So the phone rebooted at about 05:10:47, about 45 s after that capture. The previous boot's journal has no shutdown or reboot lines, so that boot did not end in a logged clean shutdown. The reason is not known (INFERENCE: a crash, a hard reset or a manual power cut). Whether the reboot was intended is a question for the user.

**Interrupt count in the new boot (FACT).** At uptime 396.56 s (arm) the count was 2 (audit: a value for 375 s that an earlier draft gave here was not found again in the captures). The user reported at about 05:16 that touch was not working. Two interrupts in six minutes is very few if the screen was in use, so touch was most likely dead from early in this boot. The drag during that window was not recorded.

**The rebind revived it (FACT).** `arm` checked for six seconds with the finger dragging: 0 interrupts while touch was dead; it then power-cycled spi0.0 and the second check, with the finger dragging, rose from 160 to 522 interrupts. The recorder was armed after that.

**The dump (FACT, `touch-dump-1`).** 763 SPI records of spi0.0 between 404.66 s and 435.52 s. The last twenty are coordinate records; the final one (`c0`) looks like a release. The only status record is `49 00 10` at 405.87 s, which is the chip's reply to the rebind's probe, not an error before it. Nothing is recorded after 435.52 s. The dump was taken at 453 s.

**After the dump (FACT).** The interrupt count was 709 at 453 s, 709 at 587 s (`touch-dead-irq-check`), 709 at 996 s and 1149 s (`touch-irq-state`, `touch-irq-thread`), and 718 at about 05:36 (`touch-scanmode-2`, before the swap). (audit, corrected) The 709 seen before the swap of `touch-scanmode-1` (about 05:33) is the same value as at 453 s, so the count was flat for about 15 minutes. The step from 709 to 718 lies after the unbind and rebind of spi0.0 that `touch-scanmode-1` performed (its restore step power-cycles and re-initialises the chip), so those nine interrupts are most likely the probe traffic of that rebind (INFERENCE, not measured). An earlier version of this paragraph read them as the chip still reporting; that is withdrawn. No drag is recorded for the flat window (the user's belief that touch was dead is not a measurement), and evdev was not read in it.

**The dead state with a drag, the only measured one (FACT, 2.14).** In the 21 October boot, with Baraa dragging, the window of 45 s had 0 evdev bytes and gpio25 high in every sample; the rails were enabled with one user each; the rebind brought events back at once. This is the strongest dead-with-drag evidence in the docs.

**Interrupt line and driver (FACT).** The device tree sets `interrupts = <25 IRQ_TYPE_LEVEL_LOW>` (kernel patch 0002). gpio25 is therefore active-low: high means not asserted. The driver requests the IRQ with `IRQF_ONESHOT` and a NULL primary handler. The handler thread was idle (state S, wait channel `irq_thread`) in `touch-irq-thread`. So the thread is not stuck, and the earlier "stuck in SPI" idea is ruled out.

**IRQ enable state (FACT).** This kernel has no `irq/irqs/178` debugfs entry, so `IRQ=unknown` is the correct result, not a parser failure. Enable state is not measurable with the current tools.

**The rails during the dead state (FACT).** L12B and L16B show enabled with one user in every capture taken before a swap (`2026-10-21 touch-watch`, `touch-trace-arm`, `touch-scanmode-2`). So the rails are on while touch is dead, as far as the regulator framework knows.

**The unbind drops the rails (FACT, `touch-scanmode-2`).** Unbinding fts2ba61y took both rails from one user to zero. The regulator framework switches an unused regulator off unless it is always-on, so the chip was unpowered during the swap (INFERENCE, not measured on the chip). The guard in `phone-touch-scanmode.sh` aborted before any command was sent, and the restore rebound the touch driver.

**BTF (FACT).** In the 2026-10-23 boot the only module failing BTF validation is `evdev`. evdev is loaded regardless.

**Corrections to earlier analysis.**
- The gpio25 "low" reading after the unbind (`touch-scanmode-1`) was most likely an artifact of an unpowered chip and a released pin, not a sign that the chip was asserting (audit: INFERENCE; the driver's power-off action disables the rails at unbind, but the chip's output was not measured). I had also suggested the opposite reading in the chat; it is withdrawn.
- "The chip stopped asserting its interrupt and went silent" (from `touch-dump-1` plus the frozen count) is not established for boot 1 from `touch-dump-1` alone (audit, corrected): the last record at 435 s is a release (decoded: event byte `c0`, TCHSTA 3), no drag is recorded after it, and the nine later interrupts are the rebind of `touch-scanmode-1`. It is established for boot 2 (count flat at 8189 with a 20 s drag at 571 s and a 15 s drag during the PM test) and by 2.14.
- The scan-mode test in `phone-touch-scanmode.sh` cannot run on this image, because unbinding unpowers the chip. The script now refuses to run unless `ALLOW_UNBIND=1` is set.
- The 2.17 reference to a "2026-10-11 rule" was not in the docs and has been removed.

**Revised hypotheses** (none is confirmed; these names are retired, 2.20 uses H1 to H6 of 2.10 and 2.12):
- H-boot: touch is dead from early in a boot. The probe leaves the chip in a state that only a power cycle clears. Consistent with this boot. Separated by: a drag right after a boot.
- H-mid: touch works after a boot and then stops after some time or use (2.10, 2.11, 2.14). Separated by: a drag right after a boot, then a dump at the failure.
- H1 (the chip stops reporting without a status record): consistent with 2.14; not confirmed by any capture after 435 s.
- H-scan (scan mode never sent, 2.12): untested. Its test is blocked on this image (see above).
- H-rails (rails off in the dead state): not supported. The rails were on in every dead-state capture.

**Plan, no code change needed.**
1. Confirm with the user: whether the phone was rebooted at about 05:10:47 and how; whether touch worked in the boot before that and in this boot before 05:16; whether a finger was moving during 05:17 to 05:18, after 435 s, and from 05:29 to 05:36.
2. On the next boot, as soon as it is up, run `--touch-watch=45` with a continuous drag. Its verdict says whether events flow in the first minute after boot (H-mid or healthy) or the chip is silent from the start (H-boot).
3. If events flow after boot and later stop, run `--touch-trace=arm` right after the boot, with the same drag, and `--touch-trace=dump` at the failure, before any rebind.
4. Only then decide the driver change. The candidate changes are a status-event handler with a re-init (docs/08 2.12), or a scan-mode knob that needs a kernel build.

Status: open. Nothing here is a confirmed cause.

**Addendum, 2026-10-23 05:43 (user answers and the touch-watch after a hard reset).** FACT, from the user: the 05:10:47 reboot was a hard reset done by hand; the user does not remember whether touch worked before 05:16 and thinks it did not; a finger was probably moving during the 05:17-05:18 rebind window.

FACT (`notes/2026-10-23-boot-touch-watch/touch-watch.txt`, boot at about 05:43:08, touch-watch at uptime 32 s): `verdict=EVENTS-FLOW`, 45 s of continuous dragging, 36,869 evdev events, interrupt delta 5545, gpio25 low in one sample, L12B and L16B enabled with one user, DSI on, no new kernel line, plasma-mobile active. The evdev node was held by kwin_wayland and the touch reader. So touch worked in this boot from its first minute.

What this changes:
- H-boot ("dead from early in every boot") is not supported: the 05:43 boot was healthy within 32 s of boot. The 05:10 boot had only 2 interrupts by 375 s, so that boot was dead early and recovered by rebind.
- Touch is therefore not dead by design at boot. It fails in some boots, and the trigger is not identified. The hard reset may or may not matter; there is no controlled comparison yet.
- The recorder is not armed in this boot, so no failure in it is recorded yet.

Next (no code change): in this boot, arm the recorder and use the touchscreen normally. Arming runs a six-second alive check (drag during it; it revives only if touch is dead). When touch stops, drag continuously for about 10 s to confirm silence, then dump before any rebind or reboot. The arm is lost at the next reboot.

Status: open. The question is now what makes touch fail in a boot that worked, not whether it fails at boot.

**Addendum 2, 2026-10-23 05:47 (the boot that worked, then stopped).** FACT, from `notes/2026-10-23-boot-touch-watch` (uptime 32 to 77 s): EVENTS-FLOW with drag. FACT, from `notes/2026-10-23-touch-trace-arm-2` (armed at uptime 221.85 s): the first six-second alive check (drag requested) saw 0 interrupts and gpio25 high, so touch was dead at about 222 to 228 s; the rebind revived it (418 interrupts in the second check, drag requested). FACT, from `notes/2026-10-23-touch-dump-2` (uptime 262.9 s): 764 SPI records of spi0.0 from 229.99 s to 241.92 s, all coordinate records after the rebind's probe (`49 00 10` at 231.2 s), the last one a release (`c0`); nothing from 241.92 s to the dump.

What this establishes: in this boot, touch worked from the first minute (EVENTS-FLOW at 32 to 77 s) and was dead by 222 s. So the failure happened in the window 77 s to 222 s of a boot that was healthy at first (audit: it did not start at 77 s; the count went on from 6863 at the end of the watch, row t=45, to 7441 at 222 s, about 580 more interrupts, so the chip kept reporting for part of that window; the kernel log has a panel power-on at 102.9 s and 224.0 s and a `buffyboard` input device at 111.5 s inside it). That is the "works for a while, then stops" pattern of 2.10 and 2.11 with a timing: somewhere within about two and a half minutes of boot. The stop itself was not recorded, because the recorder was armed only at 222 s. Whether a finger was moving at 222 to 228 s has not been confirmed.

Status: the recorder stays armed in this boot (since 221.85 s; the dump does not disarm it), so the next stop should be in the buffer if it happens before any reboot. Do not run `--touch-trace=arm` again while it is armed: its alive check revives touch if it is dead, which erases the state we want to see.

**Addendum 3, 2026-10-23 05:51 (user answers and dump 3).** FACT, from the user: during the arm check at about 222 s the finger was dragging; from about 80 s to about 220 s the phone was on the lock screen the whole time (the window in which touch failed; the failure itself is not timed).

FACT (`notes/2026-10-23-touch-dump-3`, uptime 406.25 s): the decoded records are identical to dump 2 (764 records, last at 241.92 s, a release). The interrupt count was 8189 at 262 s and 8189 at 406 s, so no interrupt arrived in those 144 s. That is either no touch in that time or touch dead again; the dump cannot tell which, and no drag is recorded.

INFERENCE, the new lead: the failure was in a window that was entirely the lock screen. Earlier notes already tie the lock screen to this (2.11: "the screen locker started mid-session"; `docs/11` 9.10: the lock greeter cannot authenticate). Two mechanisms are possible and neither is measured: (a) the greeter (kscreenlocker_greet) holds or releases the touch evdev node or the input seat, which would affect event delivery, not the chip; (b) the lock or the screen blank turns the panel off, and the chip is then left in a state the panel power cycle does not restore (2.14 shows a panel off/on does not revive it, but that test came after the failure, not before). The `--touch-watch` verdict already lists the processes holding the evdev node, so a window taken while on the lock screen will show whether the greeter holds it.

Next test (no code change): with a continuous drag, run `--touch-watch=20` now, to find out whether touch is dead at this moment; the verdict and the holder list show the state. Then lock and unlock the phone while a `--touch-watch` runs, to see whether the failure follows the lock.

**Addendum 4, 2026-10-23 05:52 (correction).** FACT, from the user: touch fails both in and out of the lock screen. So the lock screen is not a required condition for the failure, and the lead in addendum 3 (lock-screen correlation) is withdrawn. The 80-to-220 s window of the lock screen does not by itself explain the failure; the window in which it stopped is still not timed. The hypotheses of 2.18 stand as before, with H-lock dropped. Next: a drag-based `--touch-watch` now, to see whether touch is dead at this moment, and a dump at the next failure (recorder still armed since 221.85 s).

**Addendum 5, 2026-10-23 05:57 (the runtime-PM test, and the silence).**

FACT, `notes/2026-10-23-touch-watch-now` (uptime 571 s, drag 20 s): `verdict=CHIP-SILENT`, 0 interrupts, 0 events, gpio25 high in every sample, serial engine `suspended`, the rails enabled with one user each.

FACT, `notes/2026-10-23-touch-pm-1` (drag 15 s; the user reports 20 s): with power/control held on, the serial engine went `active` at once, and the interrupt count stayed 8189 for all 15 s. `RESULT pm ... delta=0 verdict=NO-CHANGE`. The SPI device itself reports runtime PM `unsupported`, so its control setting had no effect. Controls were restored to `auto`.

So the runtime power state of the serial engine is not enough to bring the chip back. The correlation with `suspended` in the two dead captures does not hold as a cause.

FACT, from `touch-dump-2` (raw buffer): there are 14 release records (`c0`) between 231 s and 242 s, and touch went on being reported after several of them (for example 232.0 s, 232.4 s, 235.1 s, 239.2 s). So a release is not what stops the chip, and the last record at 241.92 s was not special. The silence starts after it: the interrupt count is 8189 at 262 s, 406 s, 571 s and through the PM test. No record was made after 241.92 s, and two drags (571 s, about 650 s) produced nothing. The stop itself happened between 241.92 s and the first later drag; we cannot time it more closely from these captures.

What is now established about the dead state: the chip produces no interrupt and no status record before going silent; holding the bus awake does not revive it; a panel off/on does not (2.14); a full rebind does (rails off and on, probe and reset). That points at the chip's internal state (H1 class). The unexplored candidate is the scan mode that our driver never sends (2.12), which the chip could leave in an idle mode. Testing it needs a way to send the command to the chip while the driver is bound. Our driver has no such knob (the only transfer helper is `fts2ba61y_write`, used by the probe), so the test needs a kernel change, as 2.10 already noted: a debugfs file that takes a raw transfer, so the chip can be poked without a rebind.

Status: open. The next test is the knob, not more runtime-PM tests.

### 2.19 A raw SPI knob in the touch driver (patch 0004, written 2026-10-23, not built)

Purpose: the scan-mode test (2.12, `phone-touch-scanmode.sh`) cannot run without unbinding the driver, and an unbind drops the touch rails and unpowers the chip (2.18). So the driver gets a debugfs file that sends raw bytes to the chip while the driver stays bound.

**The patch:** `kernel/patches/0004-Input-fts2ba61y-debugfs-raw-transfer-knob.patch`, on top of patch 0002. It changes only `drivers/input/touchscreen/fts2ba61y.c`. The file is `/sys/kernel/debug/<spi device>/raw` (`spi0.0/raw` on this phone), mode 0600, removed on unbind.
- Write: hex bytes as one full-duplex SPI transfer, e.g. `echo "A00001" > raw` sends scan mode MS+SS. `+N` clocks out N zero bytes after the hex, e.g. `echo "87+17" > raw` clocks one 18-byte event read. The transfer holds `ts->lock`, the same lock as the driver's own transfers.
- Read: the last raw transfer as `tx <hex> rx <hex>`, kept in `raw_tx`/`raw_rx`, apart from the bounce buffers.

**What was checked (FACT):**
- `git apply --check` succeeds on a clean copy of the file as patch 0002 leaves it, and the applied result matches the edited file.
- The edit was made against the file extracted from patch 0002, so the new patch is a delta on exactly that state.

**What was not checked (say so before relying on it):**
- The driver has NOT been compiled. The kernel trees on this PC are partial (`linux-7.3-rc3`) or lack the generated arch headers (`full/linux-7.3-rc3` plus `out-real`); a syntax-only clang run stopped on generated `cpucap` headers. The real build is the sudo build (docs/06 rule 6), and that is the first compile.
- Nothing is flashed or loaded. The phone still runs the old module.

**Plan, once the module is rebuilt and loaded (needs a reboot to load the new module, then `refresh-phone-modules.sh`):**
1. After a boot, with touch dead (check with `--touch-watch=20`): `sudo sh -c 'echo "A00001" > /sys/kernel/debug/spi0.0/raw; cat /sys/kernel/debug/spi0.0/raw'`, then drag and check the interrupt count. Scan mode sent with the driver bound is the test 2.12 asked for.
2. If touch does not come back: `echo "87+17" > raw; cat raw`. A chip that answers with a non-trivial event record is alive, and the reply is the first thing to read. An all-00 or all-ff reply means no chip response.
3. Read the reply the same way for the reset sequence (`FA 20 00 00 24 81`) if the first step does nothing.

**If the knob shows nothing (research, as the user asked):** the candidates in order are (a) the full init sequence of Samsung's `stm_spi` (calibration `C0 13`, clear events `C0 62`, scan mode, sense on) against our bare reset (2.12); (b) the SPI mode and the clock, since the device tree sets 10 MHz and the chip's documented limits were not checked; (c) the chip's power-up order and reset pin (gpio25 and the rails at probe). Each needs a source read before a test, as 2.12 did.


**Package (pmbootstrap), r9.** The patch is also in the pmaports package as `add-fts2ba61y-raw-knob.patch` (identical copy of `kernel/patches/0004-*`), listed in `source` right after `add-fts2ba61y-touchscreen.patch`, with `pkgrel=9` (`KBUILD_BUILD_VERSION` becomes `#10-samsung-dm1q-mainline`). The sha512 was computed with plain `sha512sum`, as the APKBUILD notes describe; `pmbootstrap checksum` should leave it unchanged. The driver debugfs knob needs `CONFIG_DEBUG_FS`; the running kernel has debugfs mounted (`/sys/kernel/debug/gpio` is read by the scripts), so no fragment change is needed.

**Steps, pmbootstrap (the user runs them):**
1. `pmbootstrap checksum linux-samsung-dm1q-mainline` (needs sudo for the chroot). Afterwards `git diff` of the APKBUILD should show only the r9 change from this session.
2. `pmbootstrap build linux-samsung-dm1q-mainline`. The build log must show `add-fts2ba61y-raw-knob.patch` applied after `add-fts2ba61y-touchscreen.patch`. This is the first compile of the knob; a failure there is the first real check.
3. Build the boot image set from the r9 apk with the GPU DTS and the v19 reference (CORRECTED 2026-10-23, see docs/11 9.14; the first version of this step used the canonical DTS and the default v10 reference and produced an image with the GPU disabled): `bash scripts/make-dtb-image-set.sh --dts ../_scratch/pmos-v19-gpu-bind/dm1q-gpu.dts --out ../_scratch/pmos-v20-knob-gpu --ref-set ../_scratch/pmos-v19-gpu-bind --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r9.apk --new-kernel`. The module tree of the rootfs was already refreshed for this kernel (r9, #10), so step 5 is not needed again.
4. Flash `boot` and `vendor_boot` from recovery as in 2.8 step 3 (`scripts/flash-recovery.sh`), then boot.
5. Refresh the rootfs modules before anything else (rule 6, the kernel code changed): `bash scripts/refresh-phone-modules.sh --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r9.apk --reboot`. Then boot again.
6. On the phone, after the boot: `sudo ls /sys/kernel/debug/spi0.0/` should list `raw`. Then the knob test from the plan above, starting with `echo "A00001" > raw` while touch is dead.

Status: patch in repo and package, applies, pkgrel 9, not yet built with pmbootstrap, not flashed. Open.

**First pmbootstrap build (2026-10-23 08:06): failed, fixed.** The log (`~/.local/var/pmbootstrap/log.txt`, line 324772) shows one error, and it is in the new code only: `fts2ba61y.c:432: call to undeclared function 'hex2bin'` (implicit declaration). The rest of the tree compiled, including the other drivers and the rc keymaps. The fix: `#include <linux/hex.h>` (in this kernel `hex2bin` is declared there, not in `kernel.h`). The patch was regenerated (`kernel/patches/0004-*`, 153 added lines), checked with `git apply --check` on the patch-0002 state, copied to the package, and the APKBUILD sha512 updated with plain `sha512sum` (`a16bf8b8...`). `pkgrel` stays 9, since r9 was never published as an apk. Next: rerun the build; if abuild reports a checksum mismatch, run `pmbootstrap checksum linux-samsung-dm1q-mainline`.

### 2.20 Audit of the touch analysis (2026-10-23, after the GPU image fix)

Method: every number in 2.18 and its addenda was read again from the raw captures, the driver (patch 0002) and 2.12 were read again, and the SPI trace dumps were decoded for control commands. Hypothesis names are those of 2.10 and 2.12: H1 the chip stops scanning, H2 interrupt asserted but not serviced, H3 interrupts counted but evdev silent, H4 userspace ignores the device, H5 coupled to the panel power cycle, H6 SPI or regulator state. The names H-boot, H-mid, H-scan, H-rails and H-lock that 2.18 introduced are retired.

**Checked and correct (FACT).**
- Boot 2 `touch-watch` (uptime 32 to 77 s): EVENTS-FLOW, count 1318 to 6863, 36,869 events, serial engine `active`, rails on.
- `touch-trace-arm` (boot 1): 6 samples flat at 2, then after the rebind 160 to 522. `touch-trace-arm-2` (boot 2): flat at 7441, then after the rebind 7569 to 7987 (418).
- `touch-watch-now` (571 s, 20 s drag) and `touch-pm-1` (15 s drag): count flat at 8189, gpio25 high in every sample, serial engine `suspended` before the hold and `active` during it, no change.
- Rails: `vreg_l12b_1p8` 1800 mV and `vreg_l16b_3p0` 3000 mV, use count 1, in the dead state.
- gpio25 is active-low: it read `low` in one of the ten drag samples of the boot 2 watch and `high` in every dead sample.
- No `fts2ba61y` line in the kernel log between the probe and the dead state, and no `nobody cared`. The three WARNINGs per boot (trace events at 0 s, SPMI PMIC arbiter at 0.147 s, display clock at 6.8 s) are unrelated to touch and also appear in boots where touch worked.
- The event byte decodes as ID bits 1:0 = 0 (coordinate), TID bits 5:2, TCHSTA bits 7:6 with 2 = move and 3 = release (patch 0002), so `80` is a move and `c0` a release.

**Errors found and corrected in 2.17 and 2.18 (marked (audit) there).**
1. The nine interrupts from 709 to 718 were read as the chip still reporting. They come after the unbind and rebind of `touch-scanmode-1`, which power-cycles the chip; they are most likely its probe traffic. The count was flat for about 15 minutes. The 2.18 correction that said "interrupts did arrive later" is withdrawn too.
2. The count of 2 at 375 s was not found again; only 396.56 s is verified.
3. The failure window of boot 2 is 77 to 222 s, but the chip kept reporting for part of it (about 580 interrupts after the watch ended).
4. The "module list in the kernel log" of 2.17 is the module list of the display-clock warning.
5. The gpio25 `low` after the unbind is an INFERENCE (unpowered chip, released pin), not a fact.
6. 2.18 invented hypothesis names instead of using H1 to H6.

**New FACT from the recorder dumps (the main result of the audit).** The trace records the task that issued every transfer. In `touch-dump-1` and `touch-dump-2` the sequence after each rebind is the same: `sh` (the rebind) sends SENSE_OFF `c0 11`, the soft reset `fa 20 00 00 24 81`, `c0 22`, `d1`, `c0 23`, `d1`, `c0 30 61 00`; then three short-lived openers, `(udev-worker)`, `libinput-fuzz-extract` and `libinput-fuzz-to-zero`, each send SENSE_ON `c0 10` and about 20 ms later SENSE_OFF `c0 11`; then `systemd-logind` sends SENSE_ON and the device stays on. From there to the end of the buffer there are only event reads (`87`, 18 bytes): 749 in dump 1 (ends 435.52 s) and 750 in dump 2 (ends 241.92 s). No SENSE_OFF, no reset, no other command. Both buffers end with a release of slot 0.

What this shows:
- The two recorded stops were not caused by our `input_close` (SENSE_OFF) or by any other host command: the last control command was SENSE_ON, and the last transfer an ordinary event read, not a status record. That fits H1 (the chip stops by itself) and weakens the variant of H5 in which a close and reopen of the evdev node leaves the chip off.
- The chip survived three SENSE_ON / SENSE_OFF pairs right after its reset and then reported for 12 and 30 s, so SENSE_OFF followed by SENSE_ON is not by itself fatal (weak: it was tested only just after a reset).
- After the last release the chip never reported again: boot 2, no interrupt from 241.92 s to at least 650 s, with drags at 571 s and later; boot 1, a flat count until the rebind of `touch-scanmode-1`.

What it does not show: the first death of each boot was never recorded, because the recorder was armed after it in both boots. In boot 2 the first death lies in 77 to 222 s, where the log has a panel power-on at 102.9 s and 224.0 s and a `buffyboard` input device at 111.5 s (a session or console change). So H5 stays open for the first death (INFERENCE). Whether anyone touched the screen in the silent windows is not recorded.

**Candidate added (INFERENCE, not tested), H7: the chip stops after a pause in touch.** Every recorded stop follows a release, and boot 1 had only 2 interrupts by 396 s after a boot in which the user did not touch for several minutes. The timelines are consistent with a chip that drops out of scanning after some idle time and does not wake for the next touch; the scan-mode command that our driver never sends (2.12) is one candidate for what governs this. Idle blank timers and the panel power cycle (H5) move together, so the timeline alone cannot separate them.

**Tests, in this order (no further code change; the raw knob of 2.19 is in the running kernel).**
1. Arm the recorder within seconds of a clean boot while touch works (drag during the six-second check), use the phone normally, and dump at the first death before reviving it. The dump names the task and command nearest the stop, which none of the dumps so far could.
2. Idle test: after the arm, touch once, then leave the phone untouched for 1, 2 and 5 minutes in turn, then drag under `--touch-watch=20`. Run it once with the screen kept on and once with the screen blanked, to separate H7 from H5.
3. With touch dead, poke the chip through the knob, one step at a time, dragging after each and reading the interrupt count: `87+17` (does it answer, what does the FIFO hold), `C010` (SENSE_ON again), `A00001` (scan mode), and only last `FA2000002481` (the soft reset). The first step that revives the chip names the missing command.

Status: open. The audit changes the picture from "the chip fell silent somewhere" to "no host command caused the two recorded stops; the first death of a boot is unrecorded; idle is a candidate".

**Addendum (2026-10-23, after the DTS fix).** FACT (`notes/2026-10-23-gpu-after-restore-2/dmesg.txt`, kernel #10): `failed to validate module [evdev] BTF: -22` at 2.68 s is still present in the boot after the user ran the module refresh for r9, so it is not explained by a stale module tree (INFERENCE; that the refresh completed was not independently verified). It concerns evdev only, and evdev works. Low priority, open. Corrected: the soft reset in 2.19 step 3 had an extra byte; the driver sends opcode `FA` plus `20 00 00 24 81` (patch 0002, `fts2ba61y_reset`), that is `FA 20 00 00 24 81`, and the knob test in 2.20 uses `FA2000002481`. The opcodes of the driver are `87` (read event), `C0` (custom write: `10` sense on, `11` sense off, `22` device id, `23` panel info, `30` touch type, `62` clear events), `D1` (custom read) and `FA` (register write).

### 2.21 The first recorded death of a boot (2026-10-23 evening, r9 kernel, image set `pmos-v20-knob-gpu`)

Captures: `notes/2026-10-23-post-v20` (uptime 31.5 s: recorder armed) and `notes/2026-10-23-post-v20-touch_dump` (uptime 375.6 s: dump after the touch had died). This is the first death of a boot that the recorder saw from the start.

**FACT (seen in the files).**
- The boot is healthy otherwise: GMU firmware v4.1.9 loaded at 8.04 s, 0 "no GPU device was found" lines, `gpu_fw=installed`, `gpu_state=initialised`, `plasma_boot=enabled`; `fts2ba61y` bound at 7.64 s (id `53 54 40 36 01`); the evdev BTF `-22` line is still there.
- Armed at uptime 31.69 s, alive check 713 interrupts in 6 s, so touch worked at arming.
- The dump holds 4810 records from 33.755 s to 313.182 s (cpu0 only, no overrun). The interrupt count 4821 is the 11 probe-time interrupts plus the 4810 records: every interrupt after arming has a record, and none arrived after 313.18 s. At 375.6 s gpio25 is high, l12b and l16b are enabled, the IRQ thread sleeps in `irq_thread`.
- All 4810 transfers are `87` event reads issued by the IRQ thread (pid 1544). There is no control command at all between arming and the stop: no SENSE_ON / SENSE_OFF, no reset, no status record. The input device stayed open the whole time.
- The tail: a touch sequence ends with `ev=c0` at 312.523 s; 0.66 s later a new sequence starts with `ev=40` at 313.182 s; nothing follows. (In this buffer every touch sequence starts with `ev=40` and ends with `ev=c0`.) So this stop came right after the first record of a touch, with no release record after it. The two stops of 2.20 came after a release.
- Pauses between records: 21 gaps above 2 s, the longest 41.2 s (ending at 87.04 s), then 17.0 s, 13.6 s, 5.6 s. The chip reported again after every one of them.
- "panel id 81 02 25" (panel power-on) is logged at 8.14 s (boot), 317.33 s and 381.05 s. There is none between 8.14 s and 313.18 s. The one at 317.33 s comes 4.1 s AFTER the stop.
- Nothing else in the kernel log between 90 s and 376 s.

**What this changes.**
- "A host command caused the stop": now ruled out for this stop with certainty, because there was no host command at all in the window (2.20 had only the last command before the stop).
- H5 (panel power cycle or session change): no panel power cycle precedes this stop; it is weakened for this boot. The panel power-ons at 317.3 s and 381.1 s are not yet explained. INFERENCE: manual power-key off/on revive attempts by Baraa; to be confirmed.
- H7 (the chip stops after an idle pause): weakened. The chip survived pauses of up to 41 s and stopped 0.66 s after a release, in the middle of use. Pauses of 1, 2 and 5 minutes are still untested.
- H1 (the chip stops by itself) remains; it now has two shapes that a recorder can tell apart: a stop after a release (2.20, twice) and a stop right after a touch-down (this boot).

**Candidates added (INFERENCE, not tested).**
- H8: the stop is tied to time since boot, not to touch. Last records at 241.9 s (boot 2) and 313.2 s (this boot); boot 1 was never timed. A chip-side or host-side timer in the range of 4 to 5 minutes after boot would fit. Two data points only. The new journal window in the dump (below) shows what userspace did around 313 s.
- H9: the chip hangs while processing a touch (firmware lock-up on a pattern or on noise), so the death rate follows the amount of touching. It fits a stop in mid-sequence; it does not explain the stops after a release.

**Tooling added (PC tests pass, shellcheck clean).**
- `--touch-trace=dump` now also prints the journal lines of ALL units within 30 s of the last record (monotonic clock, at most 150 lines), so the userspace event nearest the stop is in the same capture.
- `--touch-poke=STEP` (`scripts/phone-touch-poke.sh`, `scripts/test-phone-touch-poke.sh`): ONE transfer through the debugfs raw knob of patch 0004, no unbind. STEP is `read` (`87+17`), `senseon` (`C010`), `scanmode` (`A00001`), `reset` (`FA2000002481`) or `hex:<bytes>`. It first requires 3 s of dragging with a flat interrupt count (otherwise NOT-DEAD, nothing sent), then sends, waits 2 s without a finger (interrupts there are the chip answering, a reset raises its own), then 8 s with a finger. Verdicts: REVIVED, CHIP-RESPONDED, NO-CHANGE. It also classifies the rx bytes: ALL-00 / ALL-FF (the chip drove nothing) or DATA.

**Tests that follow (no kernel change).**
1. With touch dead: `--touch-poke=read --touch-trace=dump`, then `senseon`, `scanmode`, `reset` in that order, one per run; the first REVIVED names the missing command. The recorder shows each poke with the task that sent it.
2. A boot with no touch at all for 6 minutes after arming, then drag: separates H8 (dead regardless of touch) from H9 (dead only after touching).
3. Keep the dump's journal window of every further death next to its record tail.

Status: open.

### 2.22 One SPI read revived the dead chip, and its event FIFO was full (2026-10-24 02:09, same boot as 2.21)

Capture: `notes/2026-10-24-poke-read` (the run of `--touch-poke=read --touch-trace=dump`). The boot clock at the dump is 17686 s, but 15854 s of it were suspended: dmesg has `PM: suspend entry (deep)` at 1390.7 s, so deep suspend now works. The trace and journal clocks do not count the suspend; every time below is on that clock.

**FACT (seen in the files).**
- No record between 313.182 s and 1816.913 s (largest gap 1503.7 s). The panel power-ons at 317.3 s, 381.1 s and 489.7 s did not bring touch back.
- The first transfer after the stall is `sh` pid 4727 at 1816.913095: 18 bytes, `87` plus zeros, rx `00 87 00 ...` (no event). That is our poke (step `read`) through the raw knob.
- 100 us later the IRQ thread reads `80 d8 b9 a8 09 07 09 3f 03 55`. Byte 7 of the event (the "events left" field, mask 0x1f) is `3f`, so left = 31, the largest value the field holds. The coordinates `d8 b9 a8 09 07 09` are those of the touch-down at 313.18 s. The driver then sends `C0 62` (clear events; the driver does this when left >= 31, patch 0002) and the next read returns `43 01 62`. From 1816.918 s on the reports are normal.
- In all 4810 records before the stall left = 0. The host never fell behind.
- Around 1816.9 s the journal has: `Power key pressed short` 1816.199 (logind), panel power-on 1816.288, kwin `Atomic commit failed: EBUSY` 1816.756, the lock screen QML 1817.28. The collector sessions c5 (1811 s) and c6 (1826 s) are two runs with the same label; the second overwrote the first, so the output of the run that did the poke is lost. The surviving `touch-poke.txt` is the second run: NOT-DEAD (279 interrupts in 3 s), nothing sent.
- gpio25 read high at the dump of 2.21 (375 s, touch dead).

**INFERENCE (reasoned, not verified).**
- The chip was alive and kept queueing events while its INT line stayed high. The stall is chip-side INT logic, not a lost interrupt on the SoC side (the line was high, and at the revival the FIFO held at least 31 events). This sharpens H1 into H10: after some read the chip stops asserting INT for later events until the host reads the FIFO again.
- The full FIFO is the consequence of the stall, not its cause (left = 0 in every record before it).
- The reviver is the read: it is the first transfer after the stall, and three panel power-ons and the user's drags in the 25 minutes before did not revive it. Confounders: this stall ended after a deep suspend and resume, and a power key press and a panel power-on came 0.7 s and 0.6 s before the poke. A repeat with the screen on, no power key and no suspend separates them.
- H8 (time since boot) and H9 (hang while processing a touch) are not needed to explain this. H5 and H7 stay weak.
- Fix direction, untested, needs a kernel change: a fallback in the driver that reads the FIFO when the chip is silent. During a touch (between touch-down and release) a delayed work reads one event if no interrupt came within about 30 ms; while the input device is open, a slow idle read (for example every 100 ms) also covers a stall after a release. An `87` read that returns no event is harmless (it did exactly that here).

**Tooling.** `collect-phone-state.sh` no longer writes over an earlier capture: reusing a label the same day goes to `<label>-2`, `-3`, and so on.

**Next.**
1. Repeat on the next stall: `--touch-poke=read --touch-trace=dump` with the screen on, no power key, no suspend, to confirm the read alone revives it (a first run that is NOT-DEAD costs nothing).
2. If it holds, build the fallback (needs the user's go-ahead: kernel and package change) and watch whether any stall outlives it.

Status: open; a candidate cause and a candidate fix, one confounded observation.

### 2.23 The second stall and the second revival: the read alone does it (2026-10-24 02:26, `notes/2026-10-24-poke-read2`)

Same boot as 2.21 and 2.22. Times are on the trace / journal clock (no suspended time).

**FACT (seen in the files).**
- Touch worked from the revival at 1816.9 s. Pauses of 50.5 s, 60.2 s, 39.7 s and 299.3 s (ending at 2520.9 s) were survived without any help, so an idle pause alone does not stop the chip (H7 is out for pauses up to 5 minutes).
- Second stall: the last record is a touch-down (`40 da a3 0b 08 06 06 20 03 3d`) at 2773.163 s; then nothing until 2820.679 s (47.5 s). In the pre phase of the poke run the interrupt count stayed at 16754 for 3 s while Baraa dragged, gpio25 high.
- At 2820.679313 `sh` (pid 6411) sent `87` + 17 zeros through the knob: rx has no event. At 2820.679509 the IRQ thread read `80 da a3 0b 08 06 06 1f 02 3c`: the coordinates of the touch-down, events left = 31. The driver sent `C0 62` (clear events), the next read returned `43 01 62`, and normal reports followed. This is the same sequence as in 2.22.
- This time there is no power key, no panel power-on and no suspend in the window: the journal window around the poke has only ssh, sudo and NetworkManager lines (plus a kwin lock-screen QML message 1.5 s after the poke, unexplained), and dmesg has nothing after 2780 s. The confounders of 2.22 are gone.
- Both stalls of this boot began right after a touch-down record. In this boot's buffer there are 832 touch-downs of touch id 0 and 828 releases of touch id 0 (and 43 / 46 for id 1); the difference of 4 includes the two stalled touch-downs. About 1 stall per 440 touch-downs.
- The poke's write returned an error both times, although the transfer went out (the recorder has it, task `sh`). busybox `printf` exits non-zero without a message when `write()` fails, so the script took its SEND-FAILED exit right after the transfer. That is why the first poke run (session c5, 1811 s) was over after 4.6 s, and why the second printed SEND-FAILED. The cause of the write error is unknown.

**INFERENCE.**
- H10 holds twice, with a clean control: after a touch-down the chip delivers it and then does not assert INT for the following events, which pile up (left = 31 at the revival). One host read of the event FIFO, even one that returns no event, makes it assert INT again at once (the IRQ thread ran 100 to 200 us after the poke both times).
- So the driver does not need the chip's INT to restart it: a read is the kick. The fallback of 2.22 stands. What the data supports: a short timer while a touch is active (between touch-down and release) covers both stalls seen in this boot. A slow idle read would also cover a stall after a release (the stops of 2.20), at the cost of a few reads a second while the input device is open.
- Why the chip stalls after a touch-down is not explained (the stalled touch-downs have the same bytes as the 800 normal ones). Candidates left: the chip's INT logic; something in how our driver reads right after a touch-down.

**Tooling.** `phone-touch-poke.sh` sends with `dd`, so the errno is printed, and it goes on with the settle and watch phases after a write error (`write=ERR` in the RESULT line); a knob that is not a writable file still aborts with exit 3.

Status: open. Cause of the chip stall unknown; recovery by one read demonstrated twice.

### 2.24 Root-cause plan for the INT stall (2026-10-24, after 2.21 to 2.23; Baraa's decision: find the cause and prevent it, no standing workaround)

What is established (2.21 to 2.23): after a touch-down record the chip sometimes stops asserting INT; it keeps queueing events (left = 31 at the revival); one host read of the event FIFO restarts INT; the host never fell behind (left = 0 in every earlier record); about 1 stall per 440 touch-downs; two stalls in this boot, no other.

**FACT from the vendor tree and DT (read in the files, this session).**
- Samsung's `stm_ts_spi_read` (`stm_spi.c:700`) is one full-duplex transfer of `rlen + 1 + tlen` bytes with tx = command + zeros, the same 18-byte `87` shape as ours. Its IRQ thread does what ours does: read one event, read `left` more, clear events at `left >= 31`.
- **Chip select.** Samsung's DT has `sec,gpio_spi_cs = <&tlmm 0x2f 0>` (gpio47) and the driver drives it by hand around every `spi_sync` (low before, high after: `stm_spi.c:843-851`); the pinctrl fragment of the touch SPI pins (fragment 70) muxes only gpio44, 45, 46 (MISO, MOSI, CLK), never gpio47. INFERENCE: the vendor kernel uses CS as a plain GPIO for this chip and not the controller's hardware CS (another pinctrl state could still mux gpio47; not searched). Our DT uses the SoC default: `qup_spi4_cs` muxes gpio47 to the serial engine and `spi-geni-qcom` asserts and deasserts it with its own commands. Not yet read: how that driver times CS against the clock, and whether our 18-byte transfers go through the GPI DMA engine (our DT enables `gpi_dma1`, spi4's `dmas` point at it) instead of the FIFO.
- **Extra host traffic in Samsung's driver.** After every IRQ batch `stm_ts_external_func` calls `sec_input_set_temperature(..., IN_IRQ)`, and `stm_ts_print_info_work` calls it every 30 s (`stm_fn.c:972-986`); the chip write is `3C <temperature>` (`stm_fn.c:1124`). Samsung has no stall watchdog. INFERENCE: if any SPI transaction re-arms a stalled INT, Samsung's regular writes would hide the stall.
- The same Samsung init that 2.12 lists and our driver lacks: `C0 13` (force calibration), `C0 62` (clear events), `A0 00 01` (scan mode MS+SS), plus the function writes (`C1 0D` is `ENABLE_VSYNC`; the DT has `sync-reportrate-120`; `C0 34` is the report rate; `C0 3D` is FOD INT control; `C0 3B` FOD finger merge). Which of these Samsung sends on this device was not read to the end.
- Not the screen position: 42 of the 832 touch-downs of this boot are at x 3350 to 3600, where both stalled touch-downs were (x 3466 / y 2968 and x 3488 / y 2619); none of the others stalled.
- Inside a touch the gap between two records is at most 18 ms (frame time 8.3 ms), apart from a few chip pauses of 131 ms to 1 s that end with a `43 11 xx` status record or an enter without a release.

**Hypotheses (INFERENCE), each with the test that would settle it.**
- H11, a race inside the chip: INT is asserted when an event is pushed while no SPI transaction is running; a push that lands during our read (or right at its end) is swallowed, INT stays high and later pushes do not re-assert it until the next CS cycle. Would explain: stall after a touch-down (the chip pushes extra records there), no host command involved, one read recovers. Test: the timing of INT against the read, per read (extra trace events, below), and a delay or a clock change that moves the window (kernel knobs).
- H12, the chip-select behaviour: hardware CS from `spi-geni-qcom` (command-based, GPI DMA) differs from Samsung's software CS in setup and hold time and in what the chip sees at the end of a transfer. Test: DT only, `cs-gpios` on gpio47 with the pin muxed as GPIO; and the same without `dmas` (FIFO mode).
- H13, missing configuration: scan mode, clear events, calibration, vsync, report rate, FOD INT control leave the chip in a state that Samsung's driver never has. Test: send the missing commands with the raw knob and soak.
- H14, the SPI clock: 10 MHz is Samsung's value too, but the clock the engine really produces is not known. Test: per-transfer `speed_hz` (kernel knob) or `spi-max-frequency` in the DT.

**Method.** The stall rate is about 1 per 440 touch-downs, so an experiment needs rapid tapping: about 3 taps a second give a stall every 2 to 3 minutes if nothing changes, and 2000 touch-downs without one (about 11 minutes) is a result. Every run keeps the recorder armed and ends with `--touch-trace=dump`, so the touch-downs and stalls can be counted from the buffer, not from memory.

**Tooling added (PC tests pass, shellcheck clean).** `--touch-trace=arm` now also records `spi:spi_transfer_start` and `irq:irq_handler_entry` (irq of the touch chip) with the stop records, so every read has three timestamps: INT noticed, transfer start, transfer stop (`EXTRA=0` turns this off). The collector arms with a 12 MB buffer per CPU (`DM1Q_TRACE_BUF_KB` changes it), enough for a whole soak at three events per read.

**Next (in this order).**
1. Soak with the new recorder, tapping; at the first stall `--touch-poke=hex:D10000+8 --touch-trace=dump` (a read that is not the event FIFO) shows whether any transaction restarts INT or only the FIFO read does (E1), then `--touch-poke=read` to revive.
2. Timing analysis of INT, start and stop for the stalled touch-downs against the normal ones (H11).
3. DT-only variants (H12, H14), then the raw-knob init parity (H13), then kernel knobs (delay, speed) if the timing points to a race. Kernel changes are asked for before they are made.

Status: open.

### 2.25 Two separate defects: an IRQ storm around suspend (cause found) and the INT stall at touch transitions (2026-10-24 10:48, `notes/2026-10-24-soak1`, `-soak1-stall`)

**Defect A: the touch IRQ is killed by the kernel after a suspend.**

FACT (dmesg of `soak1-stall`, same boot as 2.21 to 2.23, monotonic clock):
- `3724.926 PM: suspend entry (deep)`; the non-boot CPUs are back up at 3725.283, so the system woke again 0.36 s after entering suspend (an immediate wakeup).
- `3725.314 fts2ba61y spi0.0: Attempted to sync while suspend` (the SPI core refuses a transfer while its controller is suspended).
- `3728.543 irq 178: nobody cared`, naming `irq_default_primary_handler threaded fts2ba61y_irq_handler`: the kernel disabled the touch IRQ after the spurious-interrupt limit.
- The resume itself took 48 s: `ath11k_pci ... pci_pm_resume_early returns -110` at 3751.57 and `pci_pm_resume returns -110` at 3773.13, `PM: suspend exit` at 3773.137.
- At the `soak1` arm (uptime 48641 s, monotonic about 3820 s) the touch was dead with gpio25 LOW (INT asserted, nobody reading) and an interrupt count of 204822 (it was about 17k at the end of the previous capture). The arm's rebind revived it (new input device `input4` at 3821.3 s).
- Our driver (patch 0002) has no `dev_pm_ops`, does not touch its IRQ in suspend or resume, and returns `IRQ_NONE` whenever a read fails (`fts2ba61y_irq_handler`, also for `left >= 31`).

INFERENCE: the touch INT was low during the interrupted suspend (a touch or the wake itself); the IRQ was re-enabled by the PM core before the SPI controller was resumed, the thread's read failed, `IRQ_NONE` left the level-low line asserted, and the line fired about 30000 times a second until the kernel disabled it, about 3 s after the first failure. The 48 s resume (the Wi-Fi card failing, docs/02 of today) kept the controller suspended long enough for the storm to finish. Only a rebind restores it. This is a fully explained cause, and it is independent of the chip stall below. Fix direction (a kernel change, to be asked for): `dev_pm_ops` that call `disable_irq` in suspend and `enable_irq` in resume (the resume of the SPI device runs after its controller's), and no `IRQ_NONE` storm on read errors.

**Defect B: the INT stall at touch transitions (2.21 to 2.23), reproduced with a tap soak.**

FACT (`soak1-stall`, recorder armed at 3821 s with the new events; 5299 reads in 133 s):
- 416 touch-downs and 416 releases of touch id 0; the last record is a release at 3933.457778. Then nothing until our poke at 3953.07 s (19.6 s). In the poke's pre phase the count stayed at 210067 during a 3 s drag, gpio25 high. One stall per about 416 touch-downs, as estimated.
- E1: the poke `D1 00 00` + 8 zeros (a register read, not the event FIFO) returned data (`00 d1 00 00 00 00 10 00 0f ff 0f`) and did NOT restart INT (settle 2 s and drag 8 s: count flat at 210067). One trial.
- Timing of the 5245 complete reads (INT noticed, transfer start, transfer stop): INT to start min 13 us, median 95, p90 140, p99 204, max 561; start to stop min 65, median 117, p90 168, p99 254, max 437; INT to INT median 8.327 ms. The last read before the stall: 137 us and 116 us, ordinary.
- Stall positions so far: touch-down (2.21), touch-down (2.23), release (this one), and release, release in 2.20. None after a move, although moves are 4391 of 5245 reads (84%) in this soak.

INFERENCE: the stall is tied to touch-state transitions, not to the read timing of the last read. Under H11 the chip's firmware switches state at a touch-down or a release and its INT logic can lose the next assertion. A kick by the event-FIFO read restarts it, a register read does not.

**Next.**
1. The phone is probably still stalled: `--touch-poke=read --touch-trace=dump` shows whether this stall also had a full FIFO (left = 31) before it is revived.
2. The kernel batch (to be approved): the fix for defect A, and research knobs for defect B (delay before the first read of an IRQ, per-transfer clock, counters of stalls and transitions).

Status: A explained (fix pending); B open.

### 2.26 Patch 0005 (package r11): the suspend fix and the stall instruments; a read revived four of four stalls (2026-10-24 evening)

**FACT (captures `soak1-stall2` and `soak1-stall2-2`).**
- `--touch-poke=read` revived two more stalls, so a read of the event FIFO has now revived four of four (2.22, 2.23 and these two); the `D1` register read of 2.25 revived none (one trial).
- Third stall: the last read before it is the release at 3933.458 s (the one of 2.25); silent for 2010 s of the trace clock (two suspends in between, at 4864.9 s and 5858.8 s, neither followed by "nobody cared"); the poke at 5943.498 s; the IRQ read right after it is a touch-down with the left byte `3f` (left = 31).
- Fourth stall: the last read before it is a MOVE (`80`) at 6150.478 s; silent for 24.3 s; the poke at 6174.828 s; the IRQ read right after it is a move with the left byte `1f` (left = 31). 135 touch-downs of touch id 0 happened between the two pokes.
- So the six stalls known have these last records: touch-down (2.21), touch-down (2.23), release (2.25), move (this one), and release, release (2.20). The reading of 2.25 that stalls happen only at touch-down and release is withdrawn: they are enriched there (5 of 6, against 16% of the reads being touch-downs or releases in the soak) but not limited to it.
- Correction to 2.23: it says the knob's write returned an error. With `dd` as the writer the write has returned ok in every run since (`write=ok`), so the non-zero exit of the earlier `printf` was a busybox quirk (cause not found), not the knob.

**What patch 0005 does** (`kernel/patches/0005-*`, pmaports copy `add-fts2ba61y-suspend-and-stall.patch`, `pkgrel=11`; it applies on 0002 and 0004 and compiles against 7.3-rc3 with clang `-Wall -Wextra` without a warning: `bash scripts/compile-check-fts2ba61y.sh --patched`; it has NOT run on hardware).
1. Defect A (2.25): `dev_pm_ops` disable the interrupt in suspend and enable it in resume (the device resumes after its SPI controller); a failing read is reported as handled up to 100 times in a row (1 to 2 ms apart) before it is reported as unhandled; a full queue (left = 31) is cleared, the touches are released, and it is counted, instead of failing the interrupt.
2. Instruments in `/sys/kernel/debug/spi0.0/` next to `raw`, all idle at their defaults: `stats` (irqs, polls, events, press, move, release, overflow, errors, stalls, stall_after_none/press/move/release), `stats_reset`, `poll_ms` (0 = off; after that many ms without an interrupt, read the queue once: an interrupt within 2 ms after an empty read, or events in the read, count as one stall, classified by the last event; the read also recovers the touch), `read_delay_us` (wait before the first read of every interrupt) and `speed_hz` (the SPI clock at run time). With the defaults the driver behaves as r9 apart from point 1.
3. Tools: `collect-phone-state.sh <label> --touch-set=poll_ms=150 --touch-stats[=reset]` (`scripts/phone-touch-stats.sh`, PC tests pass) sets the knobs, prints knobs and counters and the stalls per 1000 touch-downs.

**Experiments with r11 (all at run time, no rebuilds).**
- A: sleep and wake the phone with a finger on the screen and touch it afterwards; the log must not show "nobody cared".
- B (baseline, touch stays usable): `--touch-set=poll_ms=150 --touch-stats=reset`, tap for about 10 minutes, `--touch-stats`. The counters give the stall rate per 1000 touch-downs and the event before each stall.
- C (H11, a race with our read): the same with `read_delay_us=300`, then `1000`. A rate that falls with the delay puts the stall in the first 100 to 300 us after INT.
- D (H14, the clock): the same with `speed_hz` 5000000 and 20000000.
- A rate that moves in none of them points at the chip select and DMA mode (H12, devicetree only) or at the missing init (H13). An arm needs about 1500 touch-downs: at the rate of this boot (1 in 300 to 440) a clean arm of that size has a chance of about 2% by luck.

Status: A has a candidate fix (untested on hardware); B has instruments (untested on hardware).

### 2.27 What the poll really found: a stall has a signature, the in-kernel counter does not show it (2026-10-24 night, `notes/2026-10-24-r11-b1*`, `-r11-b2*`, `-r11-b3*`)

New tool: `python3 scripts/touch-trace-stalls.py <touch-trace-raw.txt>` (PC test `scripts/test-touch-trace-stalls.sh`). A stall is a kick read (the poll work of patch 0005, or our poke) that returns no event and is followed within 2.5 ms by an IRQ read with `left >= 1`, after at least 100 ms without an IRQ read. A touch-down that merely arrives right after a poll read has `left = 0`: a coincidence.

**FACT.**
- `r11-b1` (poll_ms = 150, 1975 touch-downs, no recorder): the kernel counted 22 stalls (21 after a release) and `overflow 0`. The in-kernel rule (any interrupt within 2 ms plus scheduling slack after an empty poll read) also counts touch-downs that arrive at that moment, which rapid tapping produces all the time: that counter over-counts and is not used.
- `r11-b2`: `poll_ms` was back at 0 (the phone had rebooted), 36 s, 115 touch-downs, no stall: no information.
- `r11-b3` (poll_ms = 150, recorder armed, 150 s, 587 touch-downs, 158 poll reads): 4 stalls (6.8 per 1000 touch-downs) and 2 coincidences (touch-downs 563 us and 1517 us after a poll read, `left = 0`). In the 4 stalls the poll read returned no event, the IRQ thread read 109 to 311 us later and found 9, 9, 10 and 18 events queued; the silence before the kick was 181 to 303 ms. None of the 158 poll reads returned an event itself.
- Three of the four queues start with a touch-down the chip had not announced (idle gaps after the last release: 237, 114 and 201 ms); the fourth starts with a move (the stall began mid-touch). In the case with the 114 ms gap no poll read can have happened between the release and the touch-down (a poll needs 150 ms of silence), and the mid-touch case has no idle gap at all: those two stalls were not caused by a poll read.
- Of the 586 touch-downs that followed a release, 378 followed it by 100 to 150 ms (the tapping rhythm); 12 followed by 200 to 300 ms, and 2 of those 12 stalled.
- `soak1-stall2-2` run through the tool gives its two stalls as they are in 2.26 (queues of 32 after a poke).

**INFERENCE.**
- The poll recovers a stall within one poll tick (150 to 300 ms) in 4 of 4 cases here; the touch stays usable with it.
- The stall rate with the poll (4 in 587) is above the 1 in 300 to 440 of the runs without one; with four events that is not significant, but it is no sign that the poll lowers the rate.
- Stalls begin mostly at a touch-down after a release (3 of 4 here), sometimes mid-touch; the earlier stalls of 2.21 and 2.23 began right after a touch-down read, so no single event type is the trigger.
- The in-kernel stall counter should demand `left >= 1` on the IRQ read after the poll read; until then `touch-trace-stalls.py` on a recorder dump is the measurement.

**Next: the experiment arms.** Each arm: `--touch-set=...` plus `--touch-trace=arm`, 5 minutes of rapid tapping (about 1000 touch-downs, about 7 stalls at the baseline rate), then `--touch-trace=dump`, then the tool. Baseline (`read_delay_us=0`), `read_delay_us=300`, `read_delay_us=1000`, `speed_hz=5000000`, `speed_hz=20000000`.

Status: open.

### 2.28 Status, the baseline arm, and the poll at every boot (2026-10-25; FACT unless marked)

**Where the touch work stands.**
- Defect A (the IRQ killed after a suspend, 2.25): cause known; fixed in r11; the fix is still untested on hardware (a sleep and wake with the screen on is the test).
- Defect B (the chip stops asserting INT, 2.21 to 2.27): cause in the chip not known. What helps is known: a read of the event queue restarts it (4 of 4 stalls revived by our poke, 4 of 4 caught by the poll in `r11-b3`), and the r11 poll does that within 150 to 300 ms.

**Baseline arm (`arm0`, `arm0-dump`): the A/B plan does not work with arms of this size.** Same settings as `r11-b3` (poll 150 ms, delay 0, 10 MHz): 964 touch-downs in 256 s, and `touch-trace-stalls.py` finds no stall inside the window (one queue of 20 at the very first IRQ read after the recorder was armed, which can only be a stall that began before the recording), against 4 stalls in 587 touch-downs in `r11-b3`. At 6.8 per 1000, 0 in 964 has a chance of about 0.15%. So the stall rate is not constant between runs. What differed (FACT from the dumps): the tapping (`r11-b3`: 25% of the touch-downs came less than 100 ms after the previous release and few two-finger events; `arm0`: 2% under 100 ms, 143 move events of a second or third finger), the time since boot (1250 to 1400 s against 1690 to 1945 s) and the screen area tapped. None of them is shown to matter. Comparing `read_delay_us` or `speed_hz` arms of 1000 touch-downs against such a baseline cannot separate an effect from this variation, so that plan is dropped until a stimulus with a stable stall rate is found.

**Weak lead (INFERENCE, 3 events).** The three stalls of `r11-b3` that began with a touch-down came after fewer touches than usual in the previous 10 s (7, 30 and 39 touch-downs against a mean of 44) and 1 s (3, 3, 3 against a mean of 4.1): after a lull, not in the middle of a burst. Three events prove nothing; the earlier stalls were after touch-downs and moves in other contexts.

**Change: the poll at every boot.** `phone-boot-setup.sh touch-poll[=MS]` (default 150) installs `dm1q-touch-poll.service`, which sets `poll_ms` once the debugfs knob exists, and applies it now when the knob is there; `undo-touch-poll` removes it (`collect-phone-state.sh <label> --boot-setup=touch-poll`). It costs one 18-byte read per poll while the line is silent. It is a recovery, not the explanation; it stays on until the cause is found and removed.

Status: A awaiting the sleep test; B open, recovered by the poll.

### 2.29 Defect A is fixed on the phone (2026-10-25 morning, `notes/2026-10-25-suspend1`, r11 kernel, poll_ms = 150)

FACT. Two deep suspends in this boot (`PM: suspend entry (deep)` at 37039.8 s and 37290.4 s of the kernel clock): touch worked after both (Baraa), and the log has neither "Attempted to sync while suspend" nor "nobody cared". Both resumes logged `fts2ba61y spi0.0: event queue was full, cleared` (37065.827 s and 37339.239 s): the chip had queued events while the system slept, and the r11 driver clears them instead of failing the interrupt. The counters over the whole boot: 2529 touch-downs, `overflow 2` (those two resumes), `errors 0`. The in-kernel `stalls 40` is the over-counting rule of 2.27 and is not a stall count. With the poll on for hours of use no stall went unrecovered: apart from the two resumes the queue was never found full.

Also FACT, from the same log: the suspend does not last. The non-boot CPUs are back up 0.6 s after "suspend entry" (`Disabling non-boot CPUs` at 37290.959 s, `Enabling non-boot CPUs` at 37291.000 s), so something wakes the system at once; then the Wi-Fi card is restarted (`mhi mhi0: Requested to power ON`, `Device failed to enter MHI Ready` after 26 s) and the resume lasts 26 to 49 s, with wlan0 gone afterwards (`failed to enable PMF QOS: -108`). Baraa's workaround while this is open: deep suspend off in the Plasma Mobile settings (the screen locks and turns off, but there is no deep suspend: bad for the battery).

Status: A closed. B (the INT stall) open and recovered by the poll (2.28). The Wi-Fi resume is docs/02 of 2026-10-24 and below.
