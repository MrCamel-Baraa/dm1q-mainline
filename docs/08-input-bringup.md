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
  experiments, only then the driver update with Samsung's init sequence) are in `notes/2026-10-20-handoff-touch.md` sections 3 and 4. Status: handed to a fresh chat, nothing measured yet.
