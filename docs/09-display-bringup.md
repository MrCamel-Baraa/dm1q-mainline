# 09 -- Display bring-up (MDSS/DPU + DSI + panel), dm1q

Started 2026-10-13. **Status (2026-10-14): research done, panel driver written and compile-checked, DT merged, package r7 prepared. No APK built, nothing flashed or run on the phone yet.**
Labels: FACT = quoted from a file in the repo/_scratch; INFERENCE = reasoned, not verified.

## 0. Summary

- **This unit's panel is the Samsung S6E3FAC / AMB606AW01** (FACT, XBL log, 2.1). The LX83118 second source is not what is in this phone. Closes the open question of docs/02 3b for this unit.
- **The init byte sequence exists, and docs/05 was wrong that it was missing** (FACT, 3). It is in the downstream DT as `$`-indirected properties (`samsung,mdss_dsi_on_tx_cmds_revA = "$POWER_ON_PRE_SETTING"`) and, independently, the Samsung bootloader (XBL) logs every DSI packet it sends for this exact unit. The two agree packet for packet.
- Mode: DSI0 only, 4 lanes, **command mode** with TE, **DSC 1.1** (8 bpc, 8 bpp, 2 slices of 540x117), 1080x2340@120, lane rate 951.08 Mbit/s (FACT, 4).
- Rails and GPIOs are known. AVDD (5.5 V) is **not** driven by any GPIO as far as the live pin dump shows (5); the 2026-10-13 guess "PM8550 gpio11" is refuted.
- Prior art: upstream has SM8550 MDSS/DPU/DSI/PHY, no S6E3FAC driver. The same-SoC, same-ABL gts9uwifi port already drives a Samsung command-mode DSC panel on mainline-style msm (6).
- Patch 0003 (panel driver, binding, Kconfig/Makefile) compiles as a module with W=1 against 7.3-rc3; the canonical DTS now carries the display nodes; package r7 is prepared (`DRM_MSM=m`, decision in 8). Next: you build r7 (sudo), then first light (11).

## 1. Baseline
Display = bootloader framebuffer through simpledrm (`framebuffer0` @ 0xb8000000, `dm1q.dts` ~line 123). Before r7 no `&mdss`/DSI/panel nodes are enabled.
**Live check of the running r6 kernel, 2026-10-14** (`notes/2026-10-14-display-baseline/display-redacted.txt`, FACT): kernel `#7-samsung-dm1q-mainline`; `CONFIG_DRM_MSM=m`, `SM_DISPCC_8550=m`, `SM_GPUCC_8550=m`, `QCOM_LLCC=m`, `BACKLIGHT_CLASS_DEVICE=y`, `DRM_SIMPLEDRM=y`, no S6E3FAC driver; `msm.ko`, `dispcc-sm8550`, `gpucc-sm8550`, `llcc-qcom`, `drm_display_helper` are on the rootfs; dispcc, gpucc and llcc are loaded; **the GPU SMMU `3da0000.iommu` is bound (arm-smmu)**, so the r5-era deferral is gone; `card0` = simple-framebuffer, `fb0` = simpledrmdrmfb 1080x2340, stride 4320, 32 bpp; no mdss/dpu/dsi/phy device exists; the cmdline has `clk_ignore_unused`, `pd_ignore_unused` and `regulator_ignore_unused`; the panel pins read as in section 5. The handoff's "no DRM_MSM" meant "not built in".

## 2. Which panel

### 2.1 Evidence (FACT)
`notes/2026-09-28-pmos-v1-hang/last_kmsg.txt` (XBL part, excerpt in `notes/2026-10-13-display-bringup/xbl-display-init.txt`):

- `Add S6E3FAC_AMB606AW01_FHD Panel` and `[SDE] Add DM1_LX83118_CM002_FHD Panel` (both registered, HW_REV 0xD)
- DDI ID read by DCS 0xDA/0xDB/0xDC = `0x81 0x02 0x25` -> `lcd_id : 0x810225`
- `check_support_panel_S6E3FAC_AMB606AW01: panel is supported`, `Selected[0] - Panel Name : S6E3FAC_AMB606AW01_FHD_dsc_`
- the cmdline later carries `msm_drm.lcd_id=810225` (`DisplayUtils` lines)

One unit only; other S23s may carry the LX83118. A mainline driver should read 0xDA-0xDC and refuse other IDs.

### 2.2 The LX83118 data, for the record
`DM1_LX83118_CM002_PDF.h` (Samsung GPL tree) is a C byte array holding ASCII text; decode: `re.findall(r"0x([0-9a-fA-F]{2})", s)` -> bytes. It gives that panel's script (same shape: `W 0x11`, DSC `WT 0x0A ...`, 951 Mbps FFC sets). Not needed for this unit; kept out of the repo.

## 3. Init data

### 3.1 Where it was (and why it was missed)
Panel node `DM1_S6E3FAC_AMB606AW01` in `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts` (line 8462, ends ~8982). Command scripts are properties with upper-case names (`POWER_ON_PRE_SETTING`, `DSC_SETTING`, `POWER_ON_POST_SETTING`, `POWER_OFF_SETTTING` [sic], ...) in a small DSL (`W` generic write, `WT` long write, `Delay`, `IF VRR ... THEN`, `0xXX` = runtime-filled). The per-revision properties reference them by `$name`: `samsung,mdss_dsi_on_tx_cmds_revA = "$POWER_ON_PRE_SETTING"`, `samsung,dsi_on_post_tx_cmds_revA = "$POWER_ON_POST_SETTING"`, `samsung,mdss_dsi_off_tx_cmds_revA = "$POWER_OFF_SETTTING"`. A search for `qcom,mdss-dsi-on-command` or for `F0 5A 5A` as a C initialiser (docs/05) cannot see them. Readable dump: `notes/2026-10-13-display-bringup/dt-panel-DM1_S6E3FAC_AMB606AW01.txt` (made by `notes/extract_panel_dt.py`).

The GPL C/.h of this panel directory has no DCS tables (the 11.9 MB .h is self-mask / mAFPC image data: `self_mask_img_data`, `mafpc_img_data`). `panel_data_file/*.dat` empty (docs/05). Not needed any more.

### 3.2 Effective wire sequence (FACT: XBL log; DT agrees)
All register writes go out as **generic long write (type 0x29)**, even 1-byte ones; `0x11`/`0x29` as DCS short (0x05); compression mode type 0x07; PPS type 0x0A. Level keys are unlocked once (`samsung,allow_level_key_once` is set, so the DT's repeated lock/unlock pairs are suppressed on the wire) and locked after display-on. Key polarity: 9F unlock = `A5 A5`, lock = `5A 5A`; F0 and FC unlock = `5A 5A`, lock = `A5 A5`.
`B0 hh ll rr` selects register `rr` offset `hhll` for the next `rr` write (Samsung "gpara").

```
reset: pin low ~1 ms, high, >=10 ms (XBL waited ~25 ms before the first packet)
 1  9F A5 A5 ; F0 5A 5A ; FC 5A 5A                          unlock
 2  11                                                      sleep out      ; wait ~10 ms
 3  B0 00 AC F6 ; F6 25 ; B0 00 09 F6 ; F6 22 ; B0 00 0F F6 ; F6 01 ; F4 44 ; 60 00 ; F7 0F
                                                            wait ~110 ms (DT "Delay 110ms", XBL: 107 ms)
 4  35 00                                                   TE on (vblank)
 5  B9 61 00 01 00 00 01 00 00 00 00 00 00 04 94 00 00 00 00 00 10   (VRR 120HS)
 6  2A 00 00 04 37 ; 2B 00 00 09 23                         page address 1080 x 2340
 7  B0 00 36 C5 ; C5 11 ; B0 00 3E C5 ; C5 40 F1 3F 99 ; B0 00 56 C5 ; C5 40 F1 3F 99   (FFC set 0 = 951 Mbps)
 8  B0 00 02 F8 ; F8 00 ; E5 15 ; B0 00 3D F4 ; F4 10 ; ED 00 40 42 01
 9  07 01 (compression on) ; PPS (0x0A, 128 B, see 3.3)
10  BD 21 81 ; B0 00 2F BD ; BD 00 02 ; F7 0F               fixed TE
11  F2 01 ; B0 00 08 F2 ; F2 00 0C ; B0 00 8B 98 ;
    98 09 40 09 40 09 40 09 40 09 40 09 40 09 40 09 40 09 40 09 40 09 40 08 54 08 54 01 7A 01 7A 01 7A ;
    60 00 ; F7 0F                                           async 120HS
12  B0 01 95 92 ; 92 02 ; F7 0F ; B0 00 0E 94 ; 94 01 ; F7 0F ; B0 00 19 A3 ; A3 01 ;
    B0 00 1A CB ; CB 12 ; B0 00 2E CB ; CB 12 ; F7 0F ; B0 00 33 F2 ; F2 F0
13  B0 00 4E 98 ; 98 00 ; B0 00 4E 98 ; 98 00 01 7A ; B0 00 51 98 ; 98 01 ;
    B0 00 01 BD ; BD 81 ; B0 00 04 BD ; BD 03 ; B0 00 30 BD ; BD 02
14  B0 01 47 98 ; 98 55 80 01 ; B0 01 56 98 ; 98 00 1F ; 55 02          (ACL 15 %)
15  B0 00 09 87 ; 87 00 00 00 ; B0 00 85 93 ; 93 00 ; B0 00 01 B1 ; B1 1E ; F7 0F
16  B0 00 0D 94 ; 94 70 0F ; 53 28 ; 51 07 FF ;
    B0 02 79 92 ; 92 <35 B IRC table, DT "IRC MODERATO"> ; F7 0F
17  29                                                      display on     ; DT: wait 20 ms
18  FC A5 A5 ; F0 A5 A5 ; 9F 5A 5A                          lock
```
Off (DT `POWER_OFF_SETTTING`): `28`, `10`, wait 120 ms, then reset low (`samsung,mdss-dsi-off-reset-delay-us` = 2000), rails off.

The log also shows self-mask (P-hole) writes after display-on (`75`, `4C`, `5C`, `7A`, with `F0 5A 5A`): not needed for light.

### 3.3 DSC PPS (FACT, DT `DSC_SETTING`; XBL's first 21 bytes match)
Decoded (script in the session; reproduce with the 89 bytes of the DT): version 1.1, bpc 8, line_buf_depth 9, convert_rgb 1, block_pred 1, bpp 8.0 (128/16), pic 1080x2340, **slice 540x117 (2 per line, 20 per column)**, chunk 540, initial_xmit_delay 512, initial_dec_delay 526, scale init 32 / incr 2916 / decr 7, first_line_bpg 12, nfl_bpg 212, slice_bpg 223, initial_offset 6144, final_offset 4336, flatness 3..12, rc_model_size 8192, edge 6, quant_incr_limit 11/11, tgt_offset 3/3, standard 8-bpp rc_buf_thresh and range tables. The DT lists 89 bytes; the rest of the 128-byte packet is zero. **Verified by hand against the 7.3-rc3 helpers** (`dsi_populate_dsc_params` + `drm_dsc_compute_rc_parameters`, which msm runs on the panel's `drm_dsc_config`): from only pic 1080x2340, slice 540x117, 8 bpc, 8 bpp they give groups_per_line 180, chunk 540, initial_scale 32, scale_decrement 7, final_offset 4096+240 = 4336, nfl_bpg 212, slice_bpg 223, scale_increment 2916, initial_dec_delay 526 -- every one equals Samsung's PPS. So the panel driver supplies geometry only.
Mainline's msm DSI sends the PPS itself from a `drm_dsc_config` (gts9uwifi does this with `drm_dsc_pps_payload_pack`), so the panel driver must fill `dsc` and not send a hand-made 0x0A -- same conclusion as gts9uwifi (docs/panel-ana38407-bringup.md there).

### 3.4 Differences and gaps between the two sources
| Item | DT | XBL | Use |
|---|---|---|---|
| IRC table (`92` after `B0 02 79 92`), byte 5 | `0F` | `01` | XBL (what actually ran on this unit); rest of the table from DT. Why it differs is unknown (INFERENCE: runtime-selected by IRC mode / revision). |
| `0xXX` placeholders (B1=1E, 55=02, 51=07 FF, 53=28, 93=00, 87=00 00 00, AOR 98=00 01 7A, 94=70 0F) | unresolved | resolved | XBL |
| Long payloads (PPS, 98, 92) | full | cut by the log line | DT |
| GLUT / gamma (`B0 00 A1 93` + 144 B) | placeholders | not sent at boot | skip for first light |

### 3.5 Brightness
No PWM: DCS `0x53 0x28` (brightness control on, dimming) and `0x51 hi lo`. Boot value `07 FF`. gts9uwifi (same Samsung DDIC family) measured that bit 11 wraps, i.e. 11 bits with 0x07FF as full scale; the driver uses a RAW backlight with max 0x07FF (FACT for gts9uwifi, INFERENCE that it carries over; Samsung's candela table has HBM raw values above 0x07FF, which this driver does not use). DT `bl-max-level` = 0x1fe (510) is Samsung's platform scale, not the DCS range.

## 4. Link and mode (FACT unless marked)
| Item | Value | Source |
|---|---|---|
| Controller / PHY | DSI0 / DSI0 PHY (`qcom,dsi-ctrl-num` 0, phy 0) | DT |
| Type | `dsi_cmd_mode`, 4 lanes, RGB888 24 bpp, `bl_ctrl_dcs`, virtual channel 0 | DT |
| TE | GPIO86 (`te-pin-select` 1; XBL: "Configure GPIO 86 for TE line, alt_func=1"); `samsung,delayed-display-on` | DT, XBL |
| Mode | 1080x2340, 120 Hz base; porches h 92/30/30, v 84/84/72 (downstream numbers; placeholders in command mode); `mdp-transfer-time-us` 7533 | DT |
| Lane rate | `panel-clockrate` 951 080 000 (= FFC "951 Mbps") | DT |
| Refresh variants | `fhd120hs`, `fhd60phs`, `fhd30phs`, `fhd24phs`, `fhd10phs` all at the same lane rate; others selected by commands (`VRR ...` in the script) | DT |
| DSC | 2 encoders, slice 540x117, 8 bpc, 8 bpp, block prediction, `compression-mode = "dsc"` | DT |
| Topology | `qcom,display-topology = <1 1 1 2 2 1>`, default index 1 (INFERENCE: = 2 LM, 2 DSC, 1 interface, i.e. the 2-slice DSC merge into one DSI), `lm-split` 540/540 | DT |
| Flags | `tx-eot-append`, `rx-eot-ignore`, `samsung,mdss-dsi-sot-hs-mode`, `samsung,esc-clk-128M`, `t-clk-pre` 27 / `t-clk-post` 13 | DT |
| Physical size | 64 x 140 mm | DT |
| Bandwidth check | DSC payload 1080*2340*8*120 = 2.43 Gbit/s; 4 x 951 Mbit/s = 3.80 Gbit/s | computed |

**Lane rate, verified in source** (`drivers/gpu/drm/msm/dsi/dsi_host.c`, 7.3-rc3): `dsi_get_pclk_rate()` = `mode->clock` scaled by `new_htotal/htotal` with `new_hdisplay = ceil(hdisplay * 8 bpp / (8 bpc * 3)) = 360`, byte clock = pclk * 24 / (8 * 4 lanes), bit rate = 8 * byte clock = 6 * pclk. Samsung's own porches (htotal 1232, vtotal 2580, 120 Hz -> clock 381 427 kHz) give new_htotal 512, pclk 158 515 200 Hz, **951.09 Mbit/s per lane** against the downstream 951.08. The driver's one mode uses exactly those numbers.

## 5. Board resources
| Resource | Value | Source |
|---|---|---|
| Panel reset | TLMM 125 (live: output high); XBL: low, low, high (~1 ms each), DT `reset-sequence <1 10>` | DT, XBL, live pin dump |
| TE | TLMM 86, mdp_vsync (live: func1), 2 mA (same as sm8550-qrd `sde_te`) | DT, `notes/dm1q-pinctrl-table.txt`, live pin dump |
| `panel_vdd3` | fixed regulator, TLMM 21 (live: output high), 1.8 V, post-on 0 ms | DT (`fixed_regulator@1`, supply entry 0), live pin dump |
| `panel_vci` | fixed regulator, TLMM 20 (live: output high), 3.0 V, post-on 1 ms, post-off 1 ms | DT (`fixed_regulator@0`, entry 1) |
| `panel_vddr` | fixed regulator, TLMM 187 (live: output high), 1.3 V, post-on 12 ms, post-off 10 ms | DT (`fixed_regulator@2`, entry 2) |
| `display_panel_avdd` | 5.5 V, ramp 233 us, `regulator-boot-on` in Samsung's DT. **No GPIO drives it**: the regulator node has no `gpio`, and the kernel's view of the pins on a running boot with the panel lit (`notes/2026-10-13-display-bringup/live-pin-state.txt`) shows PM8550 gpio11 (the candidate from the pinctrl node name) as input/low/pull-down and TLMM 202 (gts9uwifi's AVDD pin) as input/low. Source of the rail unknown (INFERENCE: always-on from a PMIC/sub-PMIC outside our DT). Not modelled; if the panel stays dark with correct init, this is the first suspect. | DT, live pin dump |
| DSI controller `vdda-1p2` | L3E (= `vreg_l3e_1p2` in dm1q.dts) | DT fixup table; same as gts9uwifi, sm8550-qrd |
| DSI PHY `vdda-0p9` | L1E (= `vreg_l1e_0p88`) | same |
| Display connector detect | TLMM 108 (`samsung,ub-con-det`; XBL `ub_con(108) val: 0`) | DT, XBL |
| ESD | IRQ TLMM 186, falling | DT (`samsung,esd-irq-gpio1`) |
| Order (downstream) | vdd3 -> vci -> vddr (12 ms) -> reset; AVDD order unknown | DT supply entries |

gts9uwifi differs (AVDD on TLMM 202, vci = L13B); do not copy its rails.

## 6. Prior art (rule 4)
- **Upstream SM8550 display**: `sm8550.dtsi` has `mdss` (`qcom,sm8550-mdss`), `mdss_mdp` (`qcom,sm8550-dpu`), `mdss_dsi0`/`mdss_dsi1`, `mdss_dsi0_phy`, `mdss_dp0`, `dispcc` (no `status` line in the local copy, i.e. enabled). `mdss` is `status = "disabled"`; `gpu` is `status = "disabled"`. `sm8550-qrd.dts` enables `mdss`, `mdss_dsi0` (`vdda` = L3E, panel `visionox,vtdr6130`, pinctrl `sde_dsi_active/suspend` + `sde_te`), `mdss_dsi0_phy` (`vdds` = L1E). `sm8550-samsung-q5q.dts` (Z Fold5) has **no** display nodes (grep empty). Mainline DPU already carries SM8650 on the same MDSS 9.0 base (lore, 2023-10).
- **Samsung panel drivers upstream**: S6E3FA7 (Pixel 3a), S6E3FA2 (S5), S6E3FC2X01 (OnePlus 6T), S6E8FC0-M1906F9 (v7 posted 2026-03-20), S6E3HA8, SOFEF00. **No S6E3FAC / AMB606AW01** in three web searches (negative result, not proof). XBL itself falls back to `vtdr6130_144hz_fhd_dsc_cmd` as the generic panel name, irrelevant to Linux.
- **Closest working analog: gts9uwifi** (`../_scratch/gts9u-pmos-ref`): same SoC, same Samsung ABL/XBL, Samsung ANA38407 command-mode DSI, 4 lanes, DSC 1.1, 2 slices, 8 bpp; kernel 7.2-rc3 + its own panel driver `panel-samsung-ana38407.c` (GPL-2.0, 556 lines). Its patch list has **no** DPU/DSI/DSC patches (only DP and GPU/KMS split), so the upstream msm path handles this class of panel. Lessons recorded there (`docs/panel-ana38407-bringup.md`):
  1. PPS from `drm_dsc_config`, not a hand DCS 0x0A.
  2. `DISPLAY_ON` belongs in `enable`, not `prepare` (`delayed-display-on`); otherwise colour noise.
  3. DDIC init order matters (rev-C/D: unlock-block settings before `SLEEP_OUT`); a panel that reads ID `00 00 00` after a warm reboot stays black until a second prepare cycle.
  4. `&xo_board` clock-frequency is needed (dm1q.dts already has it).
  5. Config: `DRM_MSM=y` needs `QCOM_LLCC=y` (msm depends on it), `SM_DISPCC_8550=y`, `SM_GPUCC_8550=y`, `BACKLIGHT_CLASS_DEVICE`; they never load modules.
- No dm1q/S23 display work found upstream (search 2026-10-13).

## 7. DT (merged into dts/dm1q/dm1q.dts, compiles)
The block at the end of `dts/dm1q/dm1q.dts` (reviewed copy with provenance per value: `notes/2026-10-13-display-bringup/dm1q-display-nodes.dts.txt`): three GPIO fixed regulators (`panel_vdd3/vci/vddr`, TLMM 21/20/187), their pinctrl, `sde_te` (gpio86), `sde_dsi_active/suspend` (gpio125), `&mdss`, `&mdss_dsi0` (`vdda` = L3E) with `panel@0` (`samsung,s6e3fac-amb606aw01`, our own compatible), `&mdss_dsi0_out` (lanes 0-3), `&mdss_dsi0_phy` (`vdds` = L1E). No AVDD node (5). The pmaports copy is synced.
Verified 2026-10-14: compiles with the documented `cpp | dtc` (no new warning; the `avoid_unnecessary_addr_size` warning on `dsi@ae94000` disappears) and with the kernel's own dtc through `scripts/make-dtb-image-set.sh` (`../_scratch/pmos-v14-display-dtonly-check`, r6 kernel + this DT, **not flashed**). Bindings are not schema-checked (no `dtschema` on the PC).
`&gpu` stays disabled (the sm8550.dtsi default): msm's master bind would otherwise wait for the Adreno/GMU/GPU-SMMU chain (`3da0000.iommu` defers while `gpucc` is a module) and block the display (INFERENCE from the msm component model; gts9uwifi did the opposite and built gpucc in).
The three rails are `regulator-boot-on` fixed regulators. The running cmdline has `regulator_ignore_unused` (live check, section 1), so they are not switched off at late init even before a panel driver consumes them; the screen does not go dark from that, which also removes the only reason to avoid the optional DT-only boot of the v14 set.

## 8. `DRM_MSM` `=m` vs `=y` (decision: `=m`)
| | `=m` | `=y` |
|---|---|---|
| Kconfig | works on the base: `QCOM_LLCC=m`, `SM_DISPCC_8550=m` (FACT, pmaports base config, checked on the 2026-10 `.config` files and in the r7 `olddefconfig` run) | `DRM_MSM` has `depends on QCOM_LLCC \|\| QCOM_LLCC=n` (7.3-rc3 Kconfig), so LLCC must go `=y`; DISPCC, panel and the selected DRM_EXEC/GPUVM/SCHED/BUDDY all become built-in: bigger Image, more base-config churn |
| Failure mode | an msm probe error/oops happens in a udev worker after the rootfs is mounted; USB networking and ssh are already up; msm can be blacklisted from the rootfs (`/etc/modprobe.d`) without reflashing | the same fault is an initcall before the rootfs: a hang or oops can mean no ssh and a recovery flash |
| Iteration | panel/msm module changes need no new boot image except through the kernel package (modules still come from the APK) | every change is a new boot image |
| Handoff | simpledrm shows the bootloader framebuffer until `msm.ko` loads a few seconds after the rootfs mount; msm then removes it | msm is early; the real panel shows the console from the start |
| Why gts9uwifi chose `=y` | "never autoloads modules" in its setup | not our situation: r6 loads modules after switch_root (WLAN, touch are modules and work) |
| Cost of `=m` | no display driver in the initramfs: irrelevant until there is an encrypted-root unlocker; module signing/BTF handling is already solved by `refresh-phone-modules.sh` (docs/07 15.12) | none for first light |
`=m` for first light; revisit `=y` when the display works and an early graphical console or unlock screen is wanted. The fragment sets `DRM_MSM`, `SM_DISPCC_8550` and the panel explicitly so a base-config change cannot drop them.

## 9. Package r7 (prepared, not built)
- `kernel/patches/0003-drm-panel-add-Samsung-S6E3FAC-AMB606AW01-panel-driver.patch` (21 KB; panel driver 494 lines, DT binding, Kconfig, Makefile), copied to the package as `add-s6e3fac-amb606aw01-panel.patch`. Checks done: `git apply --check` clean on the 7.3-rc3 tree; the driver compiles as a module with `W=1` (clang, arm64) with no warning; `merge_config` + `olddefconfig` of the fragment on top of an existing config keeps `DRM_MSM=m`, `SM_DISPCC_8550=m`, `DRM_PANEL_SAMSUNG_S6E3FAC_AMB606AW01=m`, `DRM_SIMPLEDRM=y`.
- `config-dm1q.fragment`: those four lines. `sm8550-samsung-dm1q.dts`: synced from `dts/dm1q/dm1q.dts`. `APKBUILD`: `pkgrel=7`, new source, `sha512sums` computed here with Python (`pmbootstrap checksum` should leave them unchanged; tell me if it does not).
- Driver design, in the order the bootloader does it: power vdd3 -> vci (1 ms) -> vddr (12 ms); reset low ~2 ms, high, 15 ms; read 0xDA-0xDC (warn, do not refuse, on a mismatch with 81 02 25); unlock keys; the sequence of 3.2 up to the IRC table; `DISPLAY_ON` + 20 ms + key lock in `enable()` (`delayed-display-on`); `prepare_prev_first` so the PPS is built after the DSI host filled the DSC config; one 1080x2340 mode with Samsung's 120 Hz porches; DCS writes (types 0x05/0x15/0x39, as gts9uwifi does on a Samsung DDIC) instead of the generic 0x29 the bootloader uses (risk 2).
- Rollback: `../_scratch/pmos-v13-touch-driver` (r6 boot + vendor_boot). Going back also means refreshing the rootfs module tree to r6's (`refresh-phone-modules.sh --apk <r6 apk>`), because the modules are per kernel build (docs/07 15.12).

**Built 2026-10-14 21:37** (`linux-samsung-dm1q-mainline-7.3_rc3-r7.apk`, 95.8 MB; `pmbootstrap checksum` changed nothing). Checked: the APK holds `msm.ko` and `panel-samsung-s6e3fac-amb606aw01.ko`; its config has `DRM_MSM=m`, `SM_DISPCC_8550=m`, the panel `=m`, `DRM_SIMPLEDRM=y`, `QCOM_LLCC=m`, `LOCK_DOWN_KERNEL_FORCE_NONE=y`, `TOUCHSCREEN_FTS2BA61Y=m`. Image set `../_scratch/pmos-v15-display-r7` (`make-dtb-image-set.sh ... --new-kernel`: OK, PCIe fix present, DTB contains the panel node); `check-kernel-module-key.py` MATCH between that boot.img and the r7 module tree; `refresh-phone-modules.sh --dry-run`: 2009 modules, release 7.3.0-rc3. boot.img sha256 `01387627...`, vendor_boot.img `56f259f4...`.

## 10. Open items and risks
1. AVDD source (5). If the panel lights but stays dark/black with the right ID, look here first.
2. Packet type: the bootloader sends every register write as generic long write (0x29); the driver uses DCS writes (INFERENCE: accepted by the DDIC, as on gts9uwifi; unverified). Fallback: `mipi_dsi_generic_write_*`/`mipi_dsi_device_transfer` with an explicit type.
3. IRC byte 5 (3.4): driver uses the bootloader's `0x01`.
4. Brightness range (3.5): 0x07FF assumed full scale.
5. Warm-reboot DDIC state (gts9uwifi saw ID `00 00 00` and a dark panel until a second prepare cycle).
6. (Resolved 2026-10-14, section 1: running config, cmdline flags, modules on the rootfs.)
7. (Resolved: `3da0000.iommu` is bound; `&gpu` stays disabled anyway.)
8. Samsung's hypervisor may restrict some display blocks (handoff note); gts9uwifi's success on the same bootloader family is encouraging, not proof for the phone.
9. DSC with 2 encoders merged into one DSI on DPU 9.0: gts9uwifi's 2-slice panel works, so INFERENCE that it transfers.
10. **`disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` (WARN at dispcc probe)**, present in every captured boot since v8 (`notes/2026-10-05-v8-wlan-rails/dmesg.txt` ... `notes/2026-10-14-display-baseline/`; clk-rcg2.c:136 via `clk_rcg2_shared_init` -> parking the MDP RCG on its safe source). FACT: the MDP RCG keeps the bootloader's configuration (rate 85.7 MHz in `clk_summary`) and the console stays on screen. INFERENCE, not verified: the RCG's update bit never clears because the bootloader left it running from a source Linux does not control yet (dispcc reconfigures its PLLs at probe). Risk: when the DPU later asks for a higher MDP rate (a 120 Hz DSC panel needs far more than 85 MHz) the same update can time out (`-EBUSY`), and `msm` then fails at DPU power-up. If first light dies there, the dmesg shows `clk_set_rate`/`dpu` errors on `disp_cc_mdss_mdp_clk`; candidates: building `SM_DISPCC_8550=y` (gts9uwifi does and does not document this WARN), or a dispcc patch that does not park an RCG that is running. gts9uwifi's notes contain no occurrence of it. Do not pre-empt this; see what r7 does.
11. First-light failure signatures to read from dmesg: `msm_dpu`/`dsi` probe errors (clocks, supplies, `-EPROBE_DEFER` loops on the panel), `panel id` line, `DSI error`/`ack` lines, `drm ... [drm] fb0:` only once msm is bound.
Optional read of the bootloader's DSI/MDP registers with `mmio-read-aarch64` is not recommended now: mode, lane rate and DSC are already known, and reading display registers with gated clocks can fault the bus (cf. the NoC resets of docs/01). Only after checking `clk_summary` (the probe prints it) and only if first light fails.

## 11. Next steps
You (sudo / phone / flashing):
1. Done 2026-10-14: `bash scripts/collect-phone-state.sh display-baseline --display` (results in section 1; raw files stay uncommitted, `display-redacted.txt` is committed).
2. Build r7 (2026-10-14 pitfall: the ISP hijacks plain-HTTP requests, redirecting them to a portal page, and pmbootstrap cached that page as ten bogus APKINDEX files, so `apk-tools-static` / `bash` were "not found". Fix: pmbootstrap mirrors set to https (`pmbootstrap config mirrors.pmaports|systemd|alpine`) and the poisoned 8674-byte index files in `cache_apk_*` deleted with sudo): `pmbootstrap checksum linux-samsung-dm1q-mainline && pmbootstrap build linux-samsung-dm1q-mainline` (sudo). Tell me "done" and whether `checksum` changed anything.
Me, after "done": `bash scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --out ../_scratch/pmos-v15-display-r7 --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r7.apk --new-kernel`, `scripts/check-kernel-module-key.py`, verification that the built config has the four options, then the exact flash/refresh commands (module refresh first while the phone still boots r6, then TWRP flash of `boot` + `vendor_boot` with `scripts/flash-recovery.sh`).
Optional DT-only step before r7: flash `boot` + `vendor_boot` of `../_scratch/pmos-v14-display-dtonly-check` (r6 kernel, no module refresh needed). It exercises mdss/dsi/phy/regulator/pinctrl probing without the panel driver; the DSI host then waits for the missing panel, so simpledrm stays. It is harmless for the screen (7) but also cannot show the MDP-clock risk of item 10, which only appears once msm binds. I recommend skipping it and going straight to r7.

## 12. Evidence index
- `notes/2026-10-13-display-bringup/xbl-display-init.txt` -- XBL excerpt, panel ID and DSI packets
- `notes/2026-10-13-display-bringup/dt-panel-DM1_S6E3FAC_AMB606AW01.txt` -- decoded panel node
- `notes/2026-10-13-display-bringup/live-pin-state.txt` -- kernel's view of the panel pins on a running boot
- `notes/2026-10-13-display-bringup/dm1q-display-nodes.dts.txt` -- reviewed DT nodes with provenance
- `notes/extract_panel_dt.py` -- extractor; `scripts/phone-display-probe.sh` + `scripts/test-phone-display-probe.sh` (`collect-phone-state.sh --display`)
- `kernel/patches/0003-*.patch` -- the driver
- Sources: `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts` (8462-8982, 790-820, 10325), `../_scratch/samsung-opensource-s911b/.../display-drivers/msm/samsung/`, `../_scratch/gts9u-pmos-ref/docs/panel-ana38407-bringup.md` and `.../linux-samsung-gts9uwifi-mainline/`, `../_scratch/linux-mainline/arch/arm64/boot/dts/qcom/sm8550{,-qrd}.dts*`, `../_scratch/linux-build/full` (7.3-rc3: `drivers/gpu/drm/msm/dsi/dsi_host.c`, `drm_dsc_helper.c`, `msm/Kconfig`).
