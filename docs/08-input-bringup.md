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

## 2. Touch (Task B) — scoping notes, not started

See docs/02 item 16 and docs/05 "Touch controller ... CORRECTION 2026-10-12". Order of work:
(1) prior-art check for FTS2BA61Y/SPI upstream and in postmarketOS; (2) `&spi4` + spidev placeholder
to prove the SE answers; compare Samsung's SPI pins / CS (GPIO47) with mainline's `qup_spi4_*`
groups first; (3) find the touch LDOs with the docs/05 fixup-table method; (4) driver
(kernel change -> r6 -> `refresh-phone-modules.sh`).
