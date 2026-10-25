# 12 - Battery and charger bring-up

Started 2026-10-25. Confidence tags: CONFIRMED (seen in a log or in source), INFERRED (reasoned, not checked), TODO.

## 1. Result in one paragraph

The phone has no battery because nothing in our device tree describes it. It is NOT a pmic_glink / ADSP problem
(the handoff's first theory). On the S23 (dm1q) the gauge, the charger and the USB-C PD controller are all on an I2C bus:
a Maxim MAX77705 at 0x66, plus an NXP PCA9481 direct charger at 0x57. Mainline has drivers for the MAX77705 parts, and
our kernel already builds them as modules. What is missing is only the devicetree: the hub I2C bus, the pmic, charger and
fuel-gauge nodes and a battery node. No kernel config change is needed.

## 2. What the phone showed (CONFIRMED, user paste 2026-10-25)

- `ls /sys/class/power_supply/` printed nothing (empty).
- `/sys/class/remoteproc/` has no entries at all (no ADSP/CDSP remoteproc is registered; separate problem, audio step).
- dmesg has no `pmic_glink`, `battmgr` or `charger` lines. Only: `acpi_battery_init returned -19` and
  `bq27xxx_battery_i2c_driver_init returned 0` (bq27xxx loaded, no such device).
- The kernel cmdline carries Samsung bootloader arguments (`sec-battery.*`, `s2miw04_charger...`, `common_muic...`).
  They only show the downstream stack is Samsung's own `sec-battery`; mainline ignores them.
- Running kernel config (`/proc/config.gz`): `I2C_QCOM_GENI=y`, `MFD_MAX77705=m`, `CHARGER_MAX77705=m`,
  `BATTERY_MAX17042=m`, `LEDS_MAX77705=m`, `QCOM_Q6V5_PAS=m`, `QCOM_PMIC_GLINK=m`, `UCSI_PMIC_GLINK=m`;
  `SENSORS_MAX77705` is not set. (Correction: the first version of this page said the config lacked these; it only looked at our
  fragment, not the arm64 defconfig underneath.)
- `/sys/bus/i2c/devices/` lists only `0-004f` (INFERRED: the eUSB2 repeater on i2c6). No hub I2C bus is enabled.

## 3. Hardware per Samsung's S911B source (CONFIRMED)

Source: `_scratch/samsung-opensource-s911b/.../samsung/diamond/dm1q/dm1q_eur_openx_w00_r09.dts` (r13 has the same nodes).

- `battery` node: `compatible = "samsung,sec-battery"`, fuelgauge `max77705-fuelgauge`, charger `sec-direct-charger`
  (main charger `max77705-charger`, direct charger `pca9481-charger`).
- `max77705@66`, `compatible = "maxim,max77705"`, on `qupv3_hub_i2c8` (QUP I2C master hub, SDA/SCL = gpio206/gpio207,
  same pins as mainline `hub_i2c8_data_clk`). IRQ: TLMM GPIO 133 (0x85), flags 1 = active low. Pinctrl `if_pmic_irq`:
  gpio133, input-enable, bias-disable.
- Sub-device I2C addresses come from Samsung's MFD core (`drivers/mfd/maxim/max77705.c`): MUIC 0x25 (0x4A>>1),
  charger 0x69 (0xD2>>1), fuel gauge 0x36 (0x6C>>1), debug 0x62 (0xC4>>1). This matches the upstream S9 layout.
- `pca9481@57` (`nxp,pca9481`) on the same bus. Direct (fast) charger.
- Battery numbers in the downstream node: `chg_float_voltage` 4420 mV, `standard_curr` 2800 mA, `max_charging_current` 3150 mA,
  `battery_full_capacity` 3900, `sw_v_empty_voltage` 3200 mV, `fg_resistor = 5`.
- Wireless chargers (s2miw04 at 0x3b / 0x5b) are on `qupv3_hub_i2c5`. Not needed for a first pass.
- Zero hits for `pmic_glink`, `pmic-glink` or `battmgr` in the dm1q DT.

## 4. What mainline already has (CONFIRMED in `_scratch/linux-build/full`, 7.3-rc3 tree)

- I2C hub: `qcom,geni-se-i2c-master-hub` (`soc/qcom/qcom-geni-se.c`) and `qcom,geni-i2c-master-hub` (`i2c-qcom-geni.c`).
  `sm8550.dtsi` has `i2c_master_hub_0` (geniqup@9c0000) and `i2c_hub_0..9`, all `status = "disabled"`.
- MFD `drivers/mfd/max77705.c`, `maxim,max77705`: IRQ controller for sub devices (0 charger, 1 topsys, 2 fuelgauge, 3 USB-C),
  plus rgb LED and haptic cells.
- Charger `drivers/power/supply/max77705_charger.c`, `maxim,max77705-charger`: a standalone i2c driver (own regmap, IRQ from the
  MFD irq chip), reads `monitored-battery` and programs the float voltage from `voltage-max-design-microvolt`.
- Fuel gauge `drivers/power/supply/max17042_battery.c`, `maxim,max77705-battery`.
- Reference DT: `sdm845-samsung-starqltechn.dts` (pmic@66, charger@69, fuel-gauge@36 as sibling nodes on one bus,
  `maxim,rsns-microohm = <5000>`).
- No PCA9481 driver found in this tree.

## 5. What our tree lacks (CONFIRMED)

- `dts/dm1q/dm1q.dts` enables no I2C master hub or hub I2C, and has no pmic, charger, fuel-gauge or battery node.

## 6. DTS (APPLIED 2026-10-25 to dts/dm1q/dm1q.dts and the pmaports copy; compiles with the kernel's dtc; NOT yet on the phone)

```
battery: battery {
	compatible = "simple-battery";
	voltage-min-design-microvolt = <3200000>;   /* downstream sw_v_empty 3200 mV (INFERRED mapping) */
	voltage-max-design-microvolt = <4420000>;   /* downstream chg_float_voltage 4420 mV */
	charge-full-design-microamp-hours = <3900000>; /* downstream battery_full_capacity 3900 (INFERRED) */
	constant-charge-current-max-microamp = <1000000>; /* conservative bring-up value, raise later */
};

&i2c_master_hub_0 { status = "okay"; };

&i2c_hub_8 {
	status = "okay";

	max77705: pmic@66 {
		compatible = "maxim,max77705";
		reg = <0x66>;
		interrupt-parent = <&tlmm>;
		interrupts = <133 IRQ_TYPE_LEVEL_LOW>;
		interrupt-controller;
		#interrupt-cells = <1>;
		pinctrl-names = "default";
		pinctrl-0 = <&max77705_int_default>;
	};

	max77705_charger: charger@69 {
		compatible = "maxim,max77705-charger";
		reg = <0x69>;
		monitored-battery = <&battery>;
		interrupt-parent = <&max77705>;
		interrupts = <0>;
	};

	fuel-gauge@36 {
		compatible = "maxim,max77705-battery";
		reg = <0x36>;
		power-supplies = <&max77705_charger>;
		maxim,rsns-microohm = <5000>;
		interrupt-parent = <&max77705>;
		interrupts = <2>;
	};
};

&tlmm {
	max77705_int_default: max77705-int-default-state {
		pins = "gpio133";
		function = "gpio";
		input-enable;
		bias-disable;
	};
};
```

Build/flash plan: DTS-only change (new patch or dts update + pkgrel bump with sha512), flash, read `/sys/class/power_supply/`
and `dmesg | grep -iE 'max77705|max17042|i2c'`.

## 7. Risks and unknowns

- RISK: the upstream MFD probe returns -ENODEV unless the PMIC revision register reads Pass3
  (`Rev.0x.. is not tested`). Samsung's firmware blob is named `max77705C_bolt_pass2`, so the S23 chip may be Pass2. The first
  boot will tell (dmesg prints the revision). If it is Pass2, the fix is a small MFD driver change (ask first).
- SAFETY: the charger driver programs the float voltage from the battery node. The 4.42 V value is Samsung's, but do not leave the
  phone charging unattended until the first charging test has been watched (voltage and current via sysfs).
- INFERRED: `fg_resistor = 5` means a 5 mOhm sense resistor (matches starqltechn). INFERRED: `battery_full_capacity 3900` is the design capacity.
- TODO: whether the I2C master hub needs anything beyond clocks/CX/interconnects (e.g. an ADSP-owned resource) is unverified.
- TODO: I2C bus speed (draft uses the 100 kHz default; downstream value not checked).
- TODO: MAX77705 USB-PD controller firmware (downstream `max77705C_bolt_pass2.h`); mainline does not handle USB-C here, so
  USB-C role/PD stays out of scope for the first pass.
- TODO: PCA9481 direct charger has no mainline driver; fast charging is out of scope for the first pass.
- Separate from battery: no remoteproc exists in `/sys/class/remoteproc`. That belongs to the audio step
  (docs/02 item 17, docs/07 15.6).

## 8. Applied 2026-10-25

- `dts/dm1q/dm1q.dts` carries the block of section 6 (appended at the end); the pmaports copy `sm8550-samsung-dm1q.dts` is identical.
- APKBUILD: pkgrel 12, checksum of the DTS updated. DTS only, no kernel code or config change, so the r11 module tree on the rootfs stays valid.
  r12 is not built: image sets take the DTS from `dts/dm1q/dm1q.dts` (`scripts/make-dtb-image-set.sh`).
- Checked: `cpp` + the kernel's own dtc (`~/.cache/dm1q-kernel-src/out-real/scripts/dtc/dtc`) compile it with no new warnings; pmic@66, charger@69,
  fuel-gauge@36, the battery node, `i2c_hub_8` and `i2c_master_hub_0` are in the DTB.
- TODO after flashing: `ls /sys/class/power_supply/`, `dmesg | grep -iE 'max77705|max17042|i2c'`, and the PMIC revision line (Pass3 risk, section 7).

## 9. Image set v22 (built 2026-10-25, NOT flashed)

- `../_scratch/pmos-v22-battery` = `scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --ref-set ../_scratch/pmos-v21-r11-pm-stall --apk <linux-samsung-dm1q-mainline-7.3_rc3-r11.apk>`
  (same kernel r11 and ramdisk as v21; only the DTB differs; no `--new-kernel`, no module refresh needed).
- Checked in the new DTB: gpu `okay` and the `a740_zap.mbn` firmware-name still present (the v20 pitfall of docs/11 9.14), `i2c_hub_8` `okay`,
  pmic@66 (interrupt = gpio133 level-low), charger@69, fuel-gauge@36 and the simple-battery node present; the rest of the diff against v21 is phandle renumbering.
- Rollback: `../_scratch/pmos-v21-r11-pm-stall`.

## 10. First boot with v22 (2026-10-25 18:19): the hub I2C works, the MFD refuses Pass2 (CONFIRMED)

Phone log: `max77705 0-0066: error -ENODEV: Rev.0x2 is not tested`, `probe of 0-0066 with driver max77705 returned 19`;
`max77705-charger` (0-0069) and `max17042` (0-0036) return -517 and sit in `deferred probe pending: supplier 0-0066 not ready`.
`/sys/class/power_supply/` is still empty.

- GOOD: the I2C master hub, the bus (clocks, pins, power domain) and the chip all work: the PMIC revision register at 0x66 was read.
  The "hub needs an ADSP-owned resource" worry from section 7 did not happen. Charger and gauge are only waiting for the pmic.
- The Pass2 risk of section 7 is real: upstream `drivers/mfd/max77705.c` accepts only `MAX77705_PASS3`; this chip reads revision 2.
- Samsung's downstream core (`drivers/mfd/maxim/max77705.c`) has a table `{id 0x5 rev 0x3 PASS3}, {0x5, 0x4 PASS4}, {0x15, 0x2 PASS2 "MD15"}`,
  so revision 2 is the MD15 variant and is a supported, shipping chip. Downstream charger and fuel-gauge sources contain no revision checks;
  the revision only selects the USB-C PD firmware update path (and one PASS1-only register offset), none of which mainline has. INFERRED: the ID
  register (0x00) of this chip reads 0x15; not read yet.
- Fix: accept Pass2 next to Pass3 in the MFD probe. Draft: `notes/2026-10-25-0006-mfd-max77705-accept-pass2.patch` (applies to 7.3-rc3, not
  yet in kernel/patches or the APKBUILD). It is a kernel code change, so it needs a package build (r12 with the patch), a flash of
  boot + vendor_boot and a refresh of the rootfs modules (the max77705 module changes).

## 11. Patch 0006 applied (2026-10-25, package r12; not built, not flashed)

- `kernel/patches/0006-mfd-max77705-accept-PMIC-revision-Pass2.patch` = `pmaports/.../add-max77705-accept-pass2.patch` (identical), listed in `source`
  after `add-fts2ba61y-suspend-and-stall.patch`, checksum added; `pkgrel=12` (set earlier for the DTS) now carries kernel code, so the r12 comment says so.
  The patch applies to a pristine 7.3-rc3 (`patch --dry-run`); it touches only `drivers/mfd/max77705.c`.
- Steps for the user: `pmbootstrap checksum linux-samsung-dm1q-mainline && pmbootstrap build linux-samsung-dm1q-mainline` (needs his root rights for the chroot),
  then the image set from the r12 apk with `--new-kernel`, flash boot + vendor_boot, then `scripts/refresh-phone-modules.sh --apk <r12 apk> --reboot`.
- Expected on the phone: no "Rev.0x2 is not tested" line; `max77705`, `max77705-charger`, `max17042` bind; `power_supply` shows a battery and a charger.

## 12. v23 / package r12 on the phone: the battery works (2026-10-25 18:35, CONFIRMED)

Boot of the r12 kernel (`uname -v` = `#13-samsung-dm1q-mainline`) after refreshing the rootfs modules. `power_supply` lists `max170xx_battery` and
`max77705-charger`. dmesg: `probe of 0-0066 with driver max77705 returned 0`, `probe of 0-0069 with driver max77705-charger returned 0`,
`probe of max77705-battery.1.auto with driver max17042 returned 0`; the earlier -517 lines were the deferrals before the pmic came up. Harmless lines:
`max77705-rgb/charger/haptic: Failed to locate of_node` (the MFD cells have no child nodes; the charger is a sibling i2c node) and
`max77693-haptic: failed to get pwm device` (the vibrator is not described yet).

`uevent` readings (phone on a USB cable, screen on): status Charging, health Good, 3.883 V, capacity 51 %, 31.8 C, current_now 121 mA, cycle count 189,
charge_now 754 mAh of charge_full 1456 mAh (51.8 %, consistent with capacity 51). Charger: online, type USB, charge type Fast, constant charge voltage 4.42 V
(our battery node), constant charge current 500 mA, input current limit 500 mA.

What the numbers say:
- The voltage, temperature, percentage and cycle count are plausible; the gauge's own state survived from Android.
- `voltage_max` 4.34 V / `voltage_min` 3.04 V are the gauge's recorded min/max (max17042 reads the MinMaxVolt register), not configuration.
- The charge limits of 500 mA (input and charge) are the charger's register defaults: the mainline charger driver programs only the float voltage from
  the battery node, not `constant-charge-current-max`, and nothing detects the charger type. On the downstream phone the USB-C controller in the
  MAX77705 (BC1.2 / PD, Samsung's max77705 usbc/muic drivers) sets the input limit; mainline has no driver for it. `input_current_limit` and
  `constant_charge_current` are writable in sysfs, and the driver has an AICL work item that adjusts the input limit.
- OPEN: the gauge's absolute capacity looks about 2.6 times too small: `charge_full_design` 1482 mAh and `charge_full` 1456 mAh against 3900 mAh in Samsung's DT
  (design capacity register 0x5ca = 1482 in downstream `battery0,capacity`). The percentage is self-consistent, so it is the unit scale
  (`maxim,rsns-microohm`, 5000 as in starqltechn) or Samsung's own register convention. `current_now` is scaled the same way. Not resolved.
- UNVERIFIED: that charging terminates (status Full, current falls to the 151 mA termination current the gauge reports) at 4.42 V. Watch one full charge before
  leaving the phone charging unattended.
