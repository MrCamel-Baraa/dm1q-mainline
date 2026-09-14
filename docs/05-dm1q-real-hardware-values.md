# dm1q real hardware values — extracted from crDroid downstream source

Date: 2026-09-14
Source: `_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`
(real Samsung downstream devicetree, decompiled/flattened DTB — labels are
lost, phandles are numeric, structured as DT overlay fragments rather than
a clean node tree)

## Methodology and its limits

This file is a **dtc-decompiled DTB**, not hand-written source — node labels
were resolved away, leaving only numeric phandles and node names like
`fixed_regulator@2`. Extraction here is regex/line-window based (two small
scripts in `notes/extract_regulators.py` and `notes/extract_pinctrl.py`),
not a real DT-semantics parser. Good enough to plan and write dm1q's own
clean devicetree from; not a substitute for checking specifics again when
actually writing a given node, especially anything phandle-cross-reference
dependent.

## Regulators (28 real `regulator-name` definitions found)

**Panel fixed regulators (GPIO-controlled, not PMIC LDOs):**
- `panel_vddr` — GPIO-controlled fixed regulator
- `panel_vci` — GPIO-controlled fixed regulator
- `panel_vdd3` — GPIO-controlled fixed regulator
- `display_panel_avdd` — 5.500V

**s2mpb02 — a real Samsung LSI sub-PMIC, not previously known to this
project.** Likely dedicated to camera/display rails (18 LDOs + 2 bucks + 1
buck-boost is a classic camera-PMIC channel count):
| Regulator | Voltage |
|---|---|
| s2mpb02-l1 | 0.925V |
| s2mpb02-l2 | 1.000V |
| s2mpb02-l3 | 1.100V |
| s2mpb02-l4 | 0.925V |
| s2mpb02-l5 | 1.050V |
| s2mpb02-l6 – l10 | 1.800V |
| s2mpb02-l11, l13 | 3.200V |
| s2mpb02-l12, l14, l15, l16 | 2.800V |
| s2mpb02-l17, l18 | 2.200V |
| s2mpb02-b1 (buck1) | 0.925V |
| s2mpb02-b2 (buck2) | 1.300V |
| s2mpb02-bb (buck-boost) | 3.400V |

**Other:**
- `VDD_BTP_1P8` — 1.800–1.810V (fingerprint sensor rail — BTP = likely
  "biometric touch processor" or similar Samsung naming)
- `hap-swr-slave-reg`, `dummy_vreg` — present, no voltage set at this node

**Not recovered here: the real PM8550/PM8550B/PM8550VE/PM8550VS SPMI
regulator channel-to-consumer mapping.** These PMIC LDO/SMPS subnodes exist
(confirmed in docs/02-open-questions-and-risks.md item 2) but don't carry
descriptive `regulator-name` properties in this decompiled file — recovering
which consumer uses which PM8550 channel needs real phandle
cross-referencing, not text extraction. Treat as a follow-up task for when
actually writing specific consumer nodes, not a blocker for starting.

## Key GPIO numbers (direct properties, not pinctrl-state indirection)

| Signal | Property | GPIO (hex → decimal) |
|---|---|---|
| Touch reset | `goodix,reset-gpio` | 0x18 → **GPIO24** |
| Touch IRQ | `goodix,irq-gpio` | 0x19 → **GPIO25** |
| WLAN enable | `wlan-en-gpio` | 0x50 → **GPIO80** |
| WLAN reset | `qcom,wl-reset-gpio` | 0x50 → **GPIO80** (same pin as enable) |
| BT enable | `qcom,bt-en-gpio` | 0x51 → **GPIO81** |
| BT reset | `qcom,bt-reset-gpio` | 0x51 → **GPIO81** (same pin as enable) |
| WLAN/BT sw-ctrl | `qcom,sw-ctrl-gpio` | 0x52 → **GPIO82** |
| WLAN/BT XO clock req | `qcom,xo-clk-gpio` | 0xcc → **GPIO204** |
| Panel reset | `qcom,platform-reset-gpio` | 0x7d → **GPIO125** |
| Panel TE (path A) | `qcom,platform-te-gpio` | 0x56 → **GPIO86** |
| Panel TE (path B) | `qcom,platform-te-gpio` | 0x57 → **GPIO87** (second
  panel/DSI path — matches the dual-sourced panel situation) |

All `0xffffffff` first cells are the resolved (placeholder) phandle to the
TLMM GPIO controller in this decompiled file — the second hex value in each
`<0xffffffff 0xNN ...>` tuple is the actual GPIO pin number.

## Pinctrl states (663 pin-group entries found)

Full table in `notes/dm1q-pinctrl-table.txt` (663 lines) — too large to
usefully inline here. Format: `node_name  pins  function  pull  drive_mA`.
Representative examples:
- `key_vol_up_default` → gpio6, function=normal, pull=pull-up
- `sd_card_det_default` → gpio12, function=normal, pull=pull-up
- `display_panel_avdd_default` → gpio11, function=normal, pull=disable,
  drive=3mA
- `eusb2_reset_ctrl_default` → gpio4, function=normal, pull=disable,
  drive=2mA

## Regenerating this data

```
python3 notes/extract_regulators.py _scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
python3 notes/extract_pinctrl.py _scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
```
Both scripts take a `.dts` path as their only argument — point them at a
different board revision (`dm1q_eur_openx_w00_r01` through `r13`) to compare
across revisions if needed.
