# 09 -- Display bring-up (MDSS/DPU + DSI + panel), dm1q

Started 2026-10-13. **Status: research + draft only. Nothing built, flashed or run on the phone yet.**
Labels: FACT = quoted from a file in the repo/_scratch; INFERENCE = reasoned, not verified.

## 0. Summary

- **This unit's panel is the Samsung S6E3FAC / AMB606AW01** (FACT, XBL log, 2.1). The LX83118 second source is not what is in this phone. Closes the open question of docs/02 3b for this unit.
- **The init byte sequence exists, and docs/05 was wrong that it was missing** (FACT, 3). It is in the downstream DT as `$`-indirected properties (`samsung,mdss_dsi_on_tx_cmds_revA = "$POWER_ON_PRE_SETTING"`) and, independently, the Samsung bootloader (XBL) logs every DSI packet it sends for this exact unit. The two agree packet for packet.
- Mode: DSI0 only, 4 lanes, **command mode** with TE, **DSC 1.1** (8 bpc, 8 bpp, 2 slices of 540x117), 1080x2340@120, lane rate 951.08 Mbit/s (FACT, 4).
- Rails and GPIOs are all known except the AVDD gate (INFERENCE, 5).
- Prior art: upstream has SM8550 MDSS/DPU/DSI/PHY, no S6E3FAC driver. The same-SoC, same-ABL gts9uwifi port already drives a Samsung command-mode DSC panel on mainline-style msm (6).
- Draft DT nodes compile (7). Next real step is a panel driver (patch 0003) + kernel config (r7).

## 1. Baseline (from docs/02 item 18 and the handoff)

Display = bootloader framebuffer through simpledrm (`framebuffer0` @ 0xb8000000, `dm1q.dts` ~line 123). No `&mdss`/DSI/panel nodes enabled. The running r6 config was not re-read this session; the `~/.cache/dm1q-kernel-src/out-*/.config` files (2026-10-01/08, pre-r6) show `DRM_MSM=m`, `SM_DISPCC_8550=m`, `SM_GPUCC_8550=m`, `QCOM_LLCC=m`, `QCOM_GPI_DMA=m`, `BACKLIGHT_CLASS_DEVICE=y`, no S6E3FAC driver. So the handoff's "no DRM_MSM" is probably "not built in"; **verify against r6** (`zcat /proc/config.gz` on the phone) before deciding r7's config.

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
Decoded (script in the session; reproduce with the 89 bytes of the DT): version 1.1, bpc 8, line_buf_depth 9, convert_rgb 1, block_pred 1, bpp 8.0 (128/16), pic 1080x2340, **slice 540x117 (2 per line, 20 per column)**, chunk 540, initial_xmit_delay 512, initial_dec_delay 526, scale init 32 / incr 2916 / decr 7, first_line_bpg 12, nfl_bpg 212, slice_bpg 223, initial_offset 6144, final_offset 4336, flatness 3..12, rc_model_size 8192, edge 6, quant_incr_limit 11/11, tgt_offset 3/3, standard 8-bpp rc_buf_thresh and range tables. The DT lists 89 bytes; the rest of the 128-byte packet is zero. Mainline's msm DSI sends the PPS itself from a `drm_dsc_config` (gts9uwifi does this with `drm_dsc_pps_payload_pack`), so the panel driver must fill `dsc` and not send a hand-made 0x0A -- same conclusion as gts9uwifi (docs/panel-ana38407-bringup.md there).

### 3.4 Differences and gaps between the two sources
| Item | DT | XBL | Use |
|---|---|---|---|
| IRC table (`92` after `B0 02 79 92`), byte 5 | `0F` | `01` | XBL (what actually ran on this unit); rest of the table from DT. Why it differs is unknown (INFERENCE: runtime-selected by IRC mode / revision). |
| `0xXX` placeholders (B1=1E, 55=02, 51=07 FF, 53=28, 93=00, 87=00 00 00, AOR 98=00 01 7A, 94=70 0F) | unresolved | resolved | XBL |
| Long payloads (PPS, 98, 92) | full | cut by the log line | DT |
| GLUT / gamma (`B0 00 A1 93` + 144 B) | placeholders | not sent at boot | skip for first light |

### 3.5 Brightness (INFERENCE)
No PWM: DCS `0x53 0x28` (brightness control on, dimming) and `0x51 hi lo`. Boot value `07 FF`. Samsung's candela table has raw values rising to 2054+ for HBM, so the 0x51 value is probably 12-bit with 0x07FF as the top of the normal range and HBM above it. DT `bl-max-level` = 0x1fe (510, Samsung's platform scale) is not the DCS range. gts9uwifi uses a RAW backlight device on `mipi_dsi_dcs_set_display_brightness_large`. Decide the range from `samsung,ss_candela_map_table_revA` before writing the driver.

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

INFERENCE for the driver: msm computes the DSI bit clock from `mode->clock` (adjusted for DSC compression); choose `clock` so that it lands on 951.08 Mbit/s per lane (gts9uwifi builds `.clock` as total pixels x refresh). Check `drivers/gpu/drm/msm/dsi/dsi_host.c` (`dsi_adjust_pclk_for_compression`) in the kernel tree before fixing the number; it was not read this session.

## 5. Board resources
| Resource | Value | Source |
|---|---|---|
| Panel reset | TLMM 125; XBL: low, low, high (~1 ms each), DT `reset-sequence <1 10>` | DT, XBL |
| TE | TLMM 86, mdp_vsync, pull-down, 2 mA (same as sm8550-qrd `sde_te`) | DT, `notes/dm1q-pinctrl-table.txt` |
| `panel_vdd3` | fixed regulator, TLMM 21, 1.8 V, post-on 0 ms | DT (`fixed_regulator@1`, supply entry 0) |
| `panel_vci` | fixed regulator, TLMM 20, 3.0 V, post-on 1 ms, post-off 1 ms | DT (`fixed_regulator@0`, entry 1) |
| `panel_vddr` | fixed regulator, TLMM 187, 1.3 V, post-on 12 ms, post-off 10 ms | DT (`fixed_regulator@2`, entry 2) |
| `display_panel_avdd` | 5.5 V, ramp 233 us, `regulator-boot-on`. **Gate GPIO not found**: the regulator node has no `gpio`; the pinctrl node `display_panel_avdd_default` configures PM8550 gpio11 as output. INFERENCE: gpio11 on `pm8550_gpios` is the gate. Verify on the live device. | DT |
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

## 7. Draft DT (compiles, not merged)
`notes/2026-10-13-display-bringup/dm1q-display-nodes.dts.txt`: 3 GPIO fixed regulators + AVDD, pinctrl states, `&mdss`, `&mdss_dsi0` + `panel@0` (compatible `samsung,s6e3fac-amb606aw01`, our own name), `&mdss_dsi0_out`, `&mdss_dsi0_phy`. Verified 2026-10-13: appended to a copy of `dm1q.dts` it compiles with the documented `cpp | dtc` command, rc 0, no new warning (the `avoid_unnecessary_addr_size` warning on `dsi@ae94000` disappears). It does **not** verify bindings, and the panel compatible has no driver. Not merged into `dts/dm1q/dm1q.dts` because with `DRM_MSM=m` in the base config, enabling `&mdss` without a panel driver puts an untested probe path into the known-good baseline.
Keep `&gpu` disabled (it is by default): msm's master bind would otherwise wait for the Adreno/GMU/GPU-SMMU chain (`3da0000.iommu` defers while `gpucc` is a module), blocking the display. (INFERENCE from the msm component model; gts9uwifi did the opposite and built gpucc in.)

## 8. Plan for r7 (needs decisions, section 10)
1. New `kernel/patches/0003-drm-panel-add-samsung-s6e3fac-amb606aw01.patch` (+ copy into the pmaports package, sha512sums), driver modelled on `panel-samsung-ana38407.c`: supplies vdd3/vci/vddr/avdd, reset GPIO, ID check 0xDA-0xDC == 81 02 25, init 3.2 in `prepare` (up to step 16), `DISPLAY_ON` in `enable`, `DISPLAY_OFF`/sleep-in in `disable`/`unprepare`, `drm_dsc_config` from 3.3, backlight via 0x51, mode 1080x2340@120 with the clock from section 4. Also a Kconfig/Makefile hunk and a DT binding file (needed only for upstreaming).
2. Config: `DRM_PANEL_SAMSUNG_S6E3FAC_AMB606AW01`, `DRM_MSM`, `SM_DISPCC_8550`, `BACKLIGHT_CLASS_DEVICE`; keep `DRM_SIMPLEDRM=y` as fallback. `=m` (pmOS default, modules now load) vs `=y` (gts9uwifi) is open.
3. DTS: merge section 7 into `dm1q.dts`, re-sync the pmaports copy.
4. r7 build, then `scripts/refresh-phone-modules.sh --apk <apk> --reboot` (docs/06 rule 6), `scripts/check-kernel-module-key.py`.
5. Failure mode: msm removes simpledrm when it binds; a later failure leaves the screen blind, but USB network/ssh stay up, so logs are readable.

## 9. Open items and risks
1. AVDD gate (section 5). 2. Packet type: Samsung sends 1-2 byte writes as long (0x29); `mipi_dsi_generic_write` uses short types for <= 2 bytes (INFERENCE: harmless, unverified; fall back to `mipi_dsi_device_transfer` with explicit type). 3. IRC byte 5 (3.4). 4. Brightness range (3.5). 5. Warm-reboot DDIC state (gts9uwifi 6.3). 6. `mode.clock` for the lane rate. 7. Running r6 config (section 1). 8. Whether the GPU SMMU deferral seen in r5 persists (not re-checked; no longer a blocker if `&gpu` stays disabled). 9. Under Samsung's hypervisor some blocks may be restricted (handoff note): gts9uwifi's success on the same ABL family is encouraging but not proof for the phone. 10. DSC with 2 encoders merging into one DSI: confirm mainline DPU 9.0 picks this topology (gts9uwifi's 2-slice panel works, INFERENCE it transfers).
Optional read of the bootloader's DSI/MDP registers (`mmio-read-aarch64`) is **not** recommended now: mode, lane rate and DSC are already known; reading display registers with gated clocks can fault the bus (cf. the NoC resets of docs/01), so only do it after checking `clk_summary` and only if first light fails.

## 10. Next steps
- Baraa: decide (a) panel driver now, PC-side (recommended, nothing to run on the phone), (b) `DRM_MSM` `=m` vs `=y`, (c) whether a live check of the AVDD GPIO and the running config is wanted first (`bash scripts/collect-phone-state.sh display-baseline`; the script's header does not say it saves `/proc/config.gz` or `/sys/kernel/debug/gpio` for PM8550 gpio11 -- I would add that, with a PC-side test, before asking).
- Claude: write patch 0003 + driver, build checks that need no sudo; you run `pmbootstrap checksum/build` (sudo) for r7.

## 11. Evidence index
- `notes/2026-10-13-display-bringup/xbl-display-init.txt` -- XBL excerpt, panel ID and DSI packets
- `notes/2026-10-13-display-bringup/dt-panel-DM1_S6E3FAC_AMB606AW01.txt` -- decoded panel node
- `notes/2026-10-13-display-bringup/dm1q-display-nodes.dts.txt` -- draft DT
- `notes/extract_panel_dt.py` -- extractor
- Sources: `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts` (8462-8982, 790-820, 10325), `../_scratch/samsung-opensource-s911b/.../display-drivers/msm/samsung/`, `../_scratch/gts9u-pmos-ref/docs/panel-ana38407-bringup.md` and `.../linux-samsung-gts9uwifi-mainline/`, `../_scratch/linux-mainline/arch/arm64/boot/dts/qcom/sm8550{,-qrd}.dts*`.
