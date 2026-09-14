# gts9u devicetree vs. plain mainline: what's board-specific

Date: 2026-09-13

## Methodology (and its limits)

Compared `sm8550-samsung-gts9uwifi.dts` (from the verified-legitimate
`agcarbajo/postmarketos-galaxy-tab-s9-ultra` repo — see docs/03-references.md
for the verification writeup) against the four upstream files it `#include`s:
`sm8550.dtsi`, `pm8550.dtsi`, `pm8550vs.dtsi`, `pmk8550.dtsi`, pulled directly
from `torvalds/linux` (sparse clone, `arch/arm64/boot/dts/qcom/` only, ~10MB).

**This was a regex heuristic** (`label: nodename {` definitions and `&label`
references), not a real DT-semantics-aware diff. It will miss things like
`aliases` node entries and can't perfectly distinguish "board enables an
existing SoC-level bus" from "board defines something genuinely new" in every
case. Treat this as a first-pass map for planning, not a verified spec.
Result: 105 labels appear in the board file that don't appear in the four
upstream includes. Full list in `_scratch/gts9u-board-specific-labels.txt`.

## Grouped by what it means for dm1q's own work

**SoC-level blocks being enabled/wired up for this board** (not new hardware,
just board-specific enablement/pinout — dm1q will need the same *kind* of
work, with different real values from the crDroid tree):
`i2c4, i2c6, i2c12, i2c_hub_3/6/8/9, i2c_master_hub_0, uart7, uart14, sdhc_2,
pcie0/pcie0_phy/pcieport0, usb_1/usb_1_hsphy/usb_dp_qmpphy, ufs_mem_hc/
ufs_mem_phy, mdss/mdss_dsi0/mdss_dsi0_phy/mdss_dp0, gpu, remoteproc_adsp,
tlmm, dispcc, qupv3_id_0/1, gpi_dma1/2, apps_rsc, hwfence_shbuf`

**Board-specific PMIC voltage rail definitions** — each board configures its
own subset/voltages of the PM8550-family regulator outputs directly in the
board .dts (confirmed this is normal upstream practice, not gts9u-specific
weirdness, by checking the real `sm8550-hdk.dts`/`sm8550-qrd.dts` reference
boards, which do the same). dm1q will need its own full set of these with
real values from crDroid, not gts9u's:
`vreg_l1b_1p8, vreg_l1e_0p88, vreg_l1g_1p2, vreg_l3e_1p2, vreg_l3f_0p88,
vreg_l3g_1p2, vreg_l5b_3p104, vreg_l8b_1p8, vreg_l9b_2p9, vreg_l10b_1p8,
vreg_l11b_1p2, vreg_l12b_1p8, vreg_l13b_3p0, vreg_l14b_3p2, vreg_l15b_1p8,
vreg_l16b_3p0, vreg_l17b_2p5, vreg_s2g_0p98, vreg_s4e_0p952, vreg_s4g_1p352,
vreg_s5g_1p0, vreg_s6g_1p904, vreg_pmu_aon_0p59, vreg_pmu_btcmx_0p85,
vreg_pmu_pcie_0p9, vreg_pmu_pcie_1p8, vreg_pmu_rfa_0p8, vreg_pmu_rfa_1p2,
vreg_pmu_rfa_1p8, vreg_pmu_rfa_cmn, vreg_pmu_wlcx_0p8, vreg_pmu_wlmx_0p85,
pm8550_gpios, pm8550vs_d, pm8550vs_d_gpios, pmk8550, pmk8550_gpios,
pmk8550_sleep_clk`

**Board-specific pinctrl (GPIO mux) states** — genuinely per-board wiring,
needs dm1q's own real values from the crDroid GPIO/pinctrl tables:
`bt_default, dmic45_default, dmic67_default, eusb2_reset_default,
cs35l45_gpio_default, hall_cover_n, sdc2_card_det_n, volume_up_n,
sm5714_connector, sm5714_hs_in, sm5714_otg_det_default, sm5714_sbu_out,
sm5714_ss_in, sm5714_usbpd_int, sm5714_vbus_dischg_default,
tdm0_clk_active, tdm0_din_active, tdm0_dout_active, tdm0_ws_active,
usb_c_sbu_mux, usb_c_sbu_mux_in, ps5169_ss_in, ps5169_ss_out,
display_avdd, speaker_vdd, sde_te, panel0_in`

**Board-specific peripherals/ICs (not present in either SoC or dm1q, since
this is a tablet)** — not useful as a reference for dm1q's phone-specific
parts, but confirms the general pattern for how third-party ICs get wired
into the devicetree: `cs35l45` (Cirrus speaker amp), `sm5714` (Silicon Mitus
USB-PD/charger — dm1q likely uses a different part), `ps5169` (Parade USB
redriver), `wcn7850_pmu`/`wlan_en` (**note: gts9u uses WCN7850 — dm1q uses
QCA6490, confirmed directly from real dm1q devicetree source 2026-09-13,
correcting an earlier WCN6855 assumption — see
docs/02-open-questions-and-risks.md item 1; this is a genuinely different
chip either way, don't copy the wcn7850 nodes directly**), `battery`,
`hall_cover_n` (tablet-specific, no phone equivalent).

## Takeaway for Phase 1 Step 2

The *shape* of the work (enable SoC buses, define board regulators, define
pinctrl states, wire up board ICs) transfers directly as a template. The
*values* mostly don't — dm1q has a different WCN chip, different PMIC IC
part, different board layout, and is a phone not a tablet. Next real step:
extract the equivalent real values (GPIO numbers, regulator names/voltages,
I2C bus assignments) from the crDroid downstream device tree for dm1q, using
this gts9u structure as the skeleton to fill in.
