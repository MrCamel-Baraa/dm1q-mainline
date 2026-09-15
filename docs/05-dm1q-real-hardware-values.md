# dm1q real hardware values — extracted from crDroid downstream source

Date: 2026-09-14
Source: `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`
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

**Not recovered here via simple text extraction: the general PM8550/
PM8550B/PM8550VE/PM8550VS SPMI regulator channel-to-consumer mapping** for
most consumers. These PMIC LDO/SMPS subnodes exist (confirmed in
docs/02-open-questions-and-risks.md item 2) but don't carry descriptive
`regulator-name` properties in this decompiled file. **Exception, resolved
below: WLAN/BT (QCA6490)** — its mapping *was* fully recovered, not via text
extraction but via reading Samsung's own DTB+DTBO overlay fixup tables
directly (see the dedicated section further down). The same fixup-table
method should work for other consumers too if/when needed — it's a matter
of doing it per-consumer as the devicetree gets written, not a blanket
upfront blocker.

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

## WLAN/BT (QCA6490) regulator supply mapping — resolved 2026-09-14

**The architectural wall we hit, and why it doesn't matter:** Qualcomm's
downstream Android driver models PMIC regulators through an RPMh ARC voting
layer (`../_scratch/crdroid-dm1q-dts/qcom/kalama-regulators.dtsi`, internal
codenames like `pm_v6e_l1`) — a completely different abstraction from
mainline's `qcom,rpmh-regulator` binding (`vreg_l1b`-style direct-named
nodes). There's no clean automatic translation between the two, and that's
fine — dm1q's mainline devicetree needs the mainline convention regardless
of what Samsung's Android driver does internally.

**The actual resolution — direct evidence, not inference.** Found the real
overlay fixup tables in dm1q's own devicetree source (search for
`qcom,cnss-qca6490:.*-supply` — these are Samsung's own DTB+DTBO merge
symbol tables, listing exactly which board-level regulator phandle each
named supply property resolves to). **This is direct, unambiguous evidence
from dm1q's own source, not cross-referenced inference from gts9u.**

| Supply property | Board regulator (from dm1q's own fixup table) | Confidence |
|---|---|---|
| `vdd-wlan-io-supply` | **L15B** | Direct evidence from dm1q source |
| `vdd-wlan-dig-supply` | **S4E** | Direct evidence from dm1q source |
| `vdd-wlan-rfa1-supply` | **S6G** | Direct evidence from dm1q source |
| `vdd-wlan-rfa2-supply` | **S4G** | Direct evidence from dm1q source |
| `vdd-wlan-aon-supply` | **S2G** | Direct evidence from dm1q source |

**Correction to an assumption made earlier in this same investigation:**
initially assumed QCA6490 would use the same 7 supply property names as
gts9u's WCN7850 (`vdd`, `vddio`, `vddio1p2`, `vddaon`, `vdddig`,
`vddrfa1p2`, `vddrfa1p8`) since both are ath11k/ath12k-family. **That
assumption was wrong and is corrected here**: dm1q's own fixup table shows
QCA6490's actual downstream driver only has 5 named supplies
(`vdd-wlan-io`, `vdd-wlan-dig`, `vdd-wlan-rfa1`, `vdd-wlan-rfa2`,
`vdd-wlan-aon`) — no separate main `vdd` or `vddio1p2` rail exists in this
driver's binding at all. This is a genuinely different (simpler) binding
than WCN7850's, consistent with QCA6490 being older/simpler silicon.
**When writing dm1q's mainline devicetree, check mainline's actual QCA6490
binding (not the WCN7850/ath12k one used as a starting assumption) for the
correct property names — likely closer to this 5-rail downstream scheme
than to gts9u's 7-rail one.**

The RPMh resource IDs (S2G/S4E/S4G/S6G) cross-confirm exactly against the
PDC table evidence found earlier in this same investigation and against
gts9u's independently-confirmed mainline mapping for the same resource IDs
— two independent pieces of evidence agreeing is a good sign the underlying
platform-level resource assignment (not board-specific) is being read
correctly. L15B (the `vdd-wlan-io` LDO) is a new confirmation not
previously cross-checked against gts9u.

**Methodology credit:** the general technique — cross-referencing a
downstream PDC voting table against a mainline regulator mapping — is the
same one the gts9u author used; their own inline comment (`/* Stock Kiwi v2
votes PM8550VS-G L3 through its WCN PDC map. */` — "Kiwi" is Qualcomm's
internal codename for WCN7850) confirms they did the same kind of
downstream-source cross-reference, not a guess. For dm1q specifically, the
final resolution above came from an even more direct source (dm1q's own
overlay fixup table), which is why it's high-confidence rather than
inferred-by-analogy.

## Regenerating this data

```
python3 notes/extract_regulators.py ../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
python3 notes/extract_pinctrl.py ../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
```
Both scripts take a `.dts` path as their only argument — point them at a
different board revision (`dm1q_eur_openx_w00_r01` through `r13`) to compare
across revisions if needed.
