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

## 2. Touch (Task B) — scoping, 2026-10-12 (nothing flashed yet)

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
- **B2:** port the upstream FTS2BA61Y driver (latest posted version) as a kernel patch -> r6 build (user's
  sudo) -> `scripts/refresh-phone-modules.sh` (rule 6). Try without a firmware blob first.
- Open: IRQ polarity / type for GPIO25 on this chip (RFC used level-low, then moved to DT); whether the
  panel variant (`_boe` firmware) matters.
